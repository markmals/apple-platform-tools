// SPEC: domain.uitool.injection
/// Assembles the one read-only region we write into the target: two tiny arm64
/// code blobs plus the two strings they reference. Pure — given the resolved
/// addresses it produces the exact bytes, so the layout is unit-tested without a
/// live target. The two blobs are:
///
///   mach blob @ 0:        pthread_create_from_mach_thread(&pt, NULL, thunk, path); spin.
///   thunk @ `thunkOffset`: dlopen(path, RTLD_NOW); uitool_boot_start = dlsym(RTLD_DEFAULT, name); uitool_boot_start().
///
/// A raw mach thread has no pthread TSD and can't safely call `dlopen`, so the
/// mach blob bootstraps a real pthread (via libpthread's
/// `pthread_create_from_mach_thread`) whose start routine — the thunk — does the
/// `dlopen`. The explicit `dlsym` + call is what makes re-attach work: on an
/// already-resident dylib `dlopen` does not refire the load constructor, so the
/// thunk starts the server directly.
enum BootstrapBlob {
  static let regionSize = 0x2000
  static let thunkOffset = 0x200
  static let pathOffset = 0x400  // the dylib path string (read-only is fine)
  static let symbolOffset = 0x600
  static let bootSymbol = "uitool_boot_start"

  /// Build the region. Addresses are resolved in *our* process; the dyld shared
  /// cache has one slide per boot shared across processes, so `dlopen` / `dlsym`
  /// / `pthread_create_from_mach_thread` sit at the same addresses in the target.
  /// `codeBase` is the region's remote base; `stackBase` is where the bootstrap
  /// thread's `pthread_t` out-param lives (a separate writable region).
  ///
  /// Precondition: the path fits below `symbolOffset` — the caller checks and
  /// returns the path-too-long stage code before allocating, so the array writes
  /// here are always in bounds.
  static func build(
    codeBase: UInt64, stackBase: UInt64,
    pthreadCreate: UInt64, dlopen: UInt64, dlsym: UInt64,
    dylibPath: String
  ) -> [UInt8] {
    let thunkAddr = codeBase + UInt64(thunkOffset)
    let pathAddr = codeBase + UInt64(pathOffset)
    let symbolAddr = codeBase + UInt64(symbolOffset)

    // mach blob: pthread_create_from_mach_thread(&pt, NULL, thunk, path), then spin.
    var machBlob: [UInt32] = []
    machBlob += ARM64.loadImmediate64(into: 0, stackBase)  // x0 = &pt
    machBlob.append(ARM64.movzX1Zero)  // x1 = NULL (attr)
    machBlob += ARM64.loadImmediate64(into: 2, thunkAddr)  // x2 = thunk
    machBlob += ARM64.loadImmediate64(into: 3, pathAddr)  // x3 = path (thunk's arg)
    machBlob += ARM64.loadImmediate64(into: 16, pthreadCreate)
    machBlob.append(ARM64.blrX16)  // call pthread_create_from_mach_thread
    machBlob.append(ARM64.branchToSelf)  // spin until the caller terminates us

    // thunk (the pthread start routine): dlopen the dylib, then dlsym + call the
    // boot symbol directly. RTLD_DEFAULT (-2) finds it regardless of the handle.
    var thunk: [UInt32] = []
    thunk.append(ARM64.pushFPLR)
    thunk.append(ARM64.movzX1RTLDNow)  // x1 = RTLD_NOW
    thunk += ARM64.loadImmediate64(into: 16, dlopen)
    thunk.append(ARM64.blrX16)  // dlopen(path, RTLD_NOW)
    thunk.append(ARM64.movnX0One)  // x0 = RTLD_DEFAULT
    thunk += ARM64.loadImmediate64(into: 1, symbolAddr)  // x1 = "uitool_boot_start"
    thunk += ARM64.loadImmediate64(into: 16, dlsym)
    thunk.append(ARM64.blrX16)  // dlsym(RTLD_DEFAULT, name) → x0
    thunk.append(ARM64.blrX0)  // uitool_boot_start()
    thunk.append(ARM64.popFPLR)
    thunk.append(ARM64.ret)

    var region = [UInt8](repeating: 0, count: regionSize)
    emit(machBlob, at: 0, into: &region)
    emit(thunk, at: thunkOffset, into: &region)
    emit(string: dylibPath, at: pathOffset, into: &region)
    emit(string: bootSymbol, at: symbolOffset, into: &region)
    return region
  }

  /// Write instruction words little-endian at a byte offset. Array subscripting
  /// is bounds-checked — a layout that overflowed the region would trap here
  /// rather than corrupt adjacent memory the way the C `uint32_t *` cast did.
  private static func emit(_ words: [UInt32], at byteOffset: Int, into region: inout [UInt8]) {
    var cursor = byteOffset
    for word in words {
      region[cursor] = UInt8(word & 0xFF)
      region[cursor + 1] = UInt8((word >> 8) & 0xFF)
      region[cursor + 2] = UInt8((word >> 16) & 0xFF)
      region[cursor + 3] = UInt8((word >> 24) & 0xFF)
      cursor += 4
    }
  }

  /// Write a NUL-terminated UTF-8 string at a byte offset.
  private static func emit(string: String, at byteOffset: Int, into region: inout [UInt8]) {
    var cursor = byteOffset
    for byte in string.utf8 {
      region[cursor] = byte
      cursor += 1
    }
    region[cursor] = 0
  }
}
