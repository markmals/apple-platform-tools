import TestSupport
import Testing

@testable import UIToolInject

// SPEC: domain.uitool.injection
//
// The arm64 wide-move encoding the bootstrap blobs are built from. Expected words
// are derived by hand from the A64 movz/movk encoding, not read back from the
// implementation, so a regression in the encoder is caught against an independent
// oracle.
@Suite(.spec("domain.uitool.injection"))
struct ARM64EncodingTests {

  @Test func `loadImmediate64 of zero is movz then three lsl movk`() {
    // movz x0,#0 ; movk x0,#0,lsl16 ; movk x0,#0,lsl32 ; movk x0,#0,lsl48
    #expect(
      ARM64.loadImmediate64(into: 0, 0) == [0xD280_0000, 0xF2A0_0000, 0xF2C0_0000, 0xF2E0_0000])
  }

  @Test func `loadImmediate64 splits a full 64-bit value into four lanes`() {
    // x5 = 0xDEAD_BEEF_CAFE_F00D — lanes F00D / CAFE / BEEF / DEAD into reg 5.
    #expect(
      ARM64.loadImmediate64(into: 5, 0xDEAD_BEEF_CAFE_F00D)
        == [0xD29E_01A5, 0xF2B9_5FC5, 0xF2D7_DDE5, 0xF2FB_D5A5])
  }

  @Test func `the register field lands in the low five bits`() {
    // movz into x16: base 0xD2800000 with register 16 (0x10) in bits [4:0].
    #expect(ARM64.loadImmediate64(into: 16, 0)[0] == 0xD280_0010)
  }
}
