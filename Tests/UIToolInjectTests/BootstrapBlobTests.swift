import TestSupport
import Testing

@testable import UIToolInject

// SPEC: domain.uitool.injection
//
// The injected region's layout: the right size, the two code blobs at their fixed
// offsets, and the two strings where the shellcode expects to read them.
@Suite(.spec("domain.uitool.injection"))
struct BootstrapBlobTests {

  /// Read a little-endian instruction word at a byte offset.
  private func word(_ region: [UInt8], at offset: Int) -> UInt32 {
    UInt32(region[offset]) | UInt32(region[offset + 1]) << 8 | UInt32(region[offset + 2]) << 16
      | UInt32(region[offset + 3]) << 24
  }

  private func sampleRegion(path: String = "/tmp/libUIToolBoot.dylib") -> [UInt8] {
    BootstrapBlob.build(
      codeBase: 0x1_0000_0000, stackBase: 0x2_0000_0000,
      pthreadCreate: 0x1_8000_0000, dlopen: 0x1_8001_0000, dlsym: 0x1_8002_0000,
      dylibPath: path)
  }

  @Test func `the region is exactly the fixed size`() {
    #expect(sampleRegion().count == BootstrapBlob.regionSize)
  }

  @Test func `the mach blob starts by loading the pthread_t out-param into x0`() {
    // First instruction is movz x0, #<low lane of stackBase>. stackBase low 16 = 0.
    #expect(word(sampleRegion(), at: 0) == 0xD280_0000)
  }

  @Test func `the mach blob ends in a spin so the bootstrap thread parks`() {
    // 19 words: 4 (x0) + 1 (x1) + 4 (x2) + 4 (x3) + 4 (x16) + 1 (blr) + 1 (b .).
    // The branch-to-self is the last word, at byte 18*4.
    #expect(word(sampleRegion(), at: 18 * 4) == ARM64.branchToSelf)
  }

  @Test func `the thunk opens at its offset with a frame push`() {
    #expect(word(sampleRegion(), at: BootstrapBlob.thunkOffset) == ARM64.pushFPLR)
  }

  @Test func `the thunk returns at its tail`() {
    // 20 words: stp, movz, 4, blr, movn, 4, 4, blr, blr, ldp, ret. ret is word 19.
    #expect(word(sampleRegion(), at: BootstrapBlob.thunkOffset + 19 * 4) == ARM64.ret)
  }

  @Test func `the dylib path is written NUL-terminated at its offset`() {
    let path = "/tmp/libUIToolBoot.dylib"
    let region = sampleRegion(path: path)
    let bytes = Array(
      region[BootstrapBlob.pathOffset..<(BootstrapBlob.pathOffset + path.utf8.count)])
    #expect(bytes == Array(path.utf8))
    #expect(region[BootstrapBlob.pathOffset + path.utf8.count] == 0)
  }

  @Test func `the boot symbol is written NUL-terminated where the thunk looks`() {
    let region = sampleRegion()
    let symbol = BootstrapBlob.bootSymbol
    let bytes = Array(
      region[BootstrapBlob.symbolOffset..<(BootstrapBlob.symbolOffset + symbol.utf8.count)])
    #expect(bytes == Array(symbol.utf8))
    #expect(region[BootstrapBlob.symbolOffset + symbol.utf8.count] == 0)
  }
}
