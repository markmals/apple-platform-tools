import Darwin

// SPEC: domain.uitool.injection
/// The cooperative attach-to-running injector: acquire the target's task port,
/// write the bootstrap region ([[BootstrapBlob]]) into it, and run it on a fresh
/// mach thread. This is the package's one irreducible unsafe boundary — every
/// call here is a mach kernel trap that reaches across the process line, which is
/// `@unsafe` in any language (Swift or Rust); the language choice only quarantines
/// it, it cannot make cross-process injection safe. Everything dangerous lives in
/// this one file; the bytes it writes and the addresses it computes are pure,
/// tested code elsewhere. Plain arm64 only (no PAC) — the arm64e/unrestricted
/// path is deferred.
public enum RemoteInjector {

  /// Inject `dylibPath` into `pid`. Returns 0 on success, or a non-zero stage
  /// code the caller maps to the error vocabulary:
  ///   1  task_for_pid denied (missing debugger entitlement / not permitted)
  ///   2  could not allocate the code region in the target
  ///   3  dylib path too long for the injected region
  ///   4  could not write the bootstrap into the target
  ///   5  could not make the bootstrap executable
  ///   6  could not allocate the bootstrap stack
  ///   7  could not create the bootstrap thread
  ///   8  could not resolve dlopen / dlsym / pthread_create_from_mach_thread
  public static func inject(pid: Int32, dylibPath: String) -> Int32 {
    var task: task_t = 0
    guard task_for_pid(mach_task_self_, pid, &task) == KERN_SUCCESS else {
      return 1  // task_for_pid denied — entitlement / permission
    }

    let pathLength = dylibPath.utf8.count + 1
    guard BootstrapBlob.pathOffset + pathLength <= BootstrapBlob.regionSize else {
      mach_port_deallocate(mach_task_self_, task)
      return 3
    }

    // Resolve in this process; the shared dyld cache slide carries to the target.
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    guard let pthreadCreate = dlsym(rtldDefault, "pthread_create_from_mach_thread"),
      let dlopenAddress = dlsym(rtldDefault, "dlopen"),
      let dlsymAddress = dlsym(rtldDefault, "dlsym")
    else {
      mach_port_deallocate(mach_task_self_, task)
      return 8
    }

    // Writable region: the bootstrap stack (grows down from the top) plus, at its
    // base, the pthread_t out-param libpthread writes through. Separate from the
    // code region — putting it in execute-only memory faults the pthread create.
    var stack: mach_vm_address_t = 0
    let stackSize: mach_vm_size_t = 0x80000  // 512 KB
    guard mach_vm_allocate(task, &stack, stackSize, VM_FLAGS_ANYWHERE) == KERN_SUCCESS else {
      mach_port_deallocate(mach_task_self_, task)
      return 6
    }
    let pthreadOut = UInt64(stack)  // 8 bytes at the base; the stack grows down from the top
    let stackPointer = (UInt64(stack) + UInt64(stackSize) - 0x100) & ~UInt64(0xF)

    // Execute-only code region: the two blobs and the two strings.
    var base: mach_vm_address_t = 0
    guard
      mach_vm_allocate(task, &base, mach_vm_size_t(BootstrapBlob.regionSize), VM_FLAGS_ANYWHERE)
        == KERN_SUCCESS
    else {
      mach_vm_deallocate(task, stack, stackSize)
      mach_port_deallocate(mach_task_self_, task)
      return 2
    }

    let region = BootstrapBlob.build(
      codeBase: UInt64(base), stackBase: pthreadOut,
      pthreadCreate: UInt64(UInt(bitPattern: pthreadCreate)),
      dlopen: UInt64(UInt(bitPattern: dlopenAddress)),
      dlsym: UInt64(UInt(bitPattern: dlsymAddress)),
      dylibPath: dylibPath)

    let wrote = region.withUnsafeBytes { raw in
      mach_vm_write(
        task, base, vm_offset_t(UInt(bitPattern: raw.baseAddress)),
        mach_msg_type_number_t(BootstrapBlob.regionSize)) == KERN_SUCCESS
    }
    guard wrote else {
      mach_port_deallocate(mach_task_self_, task)
      return 4
    }

    guard
      mach_vm_protect(
        task, base, mach_vm_size_t(BootstrapBlob.regionSize), 0, VM_PROT_READ | VM_PROT_EXECUTE)
        == KERN_SUCCESS
    else {
      mach_port_deallocate(mach_task_self_, task)
      return 5
    }

    // arm64 (no PAC): set the entry pc and stack directly.
    var state = arm_thread_state64_t()
    state.__pc = UInt64(base)
    state.__sp = stackPointer
    let stateCount = mach_msg_type_number_t(
      MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)

    var thread: thread_act_t = 0
    let created = withUnsafeMutablePointer(to: &state) { pointer in
      pointer.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) { rawState in
        thread_create_running(task, ARM_THREAD_STATE64, rawState, stateCount, &thread)
      }
    }
    guard created == KERN_SUCCESS else {
      mach_port_deallocate(mach_task_self_, task)
      return 7
    }

    // The bootstrap mach thread spins after handing off to the real pthread; give
    // it a moment to create that pthread, then terminate it. The dlopen runs on
    // the pthread, independent of this bootstrap thread.
    usleep(200_000)  // 200 ms
    thread_terminate(thread)
    mach_port_deallocate(mach_task_self_, thread)
    mach_port_deallocate(mach_task_self_, task)
    return 0
  }
}
