// SPEC: domain.uitool.injection
/// The arm64 instruction words the bootstrap blobs are assembled from. Pure
/// integer encoding — no I/O, no target — so the bytes we inject are unit-tested
/// against independently-derived encodings rather than trusted blind. (Plain
/// arm64, no PAC; the arm64e/ptrauth path is deferred and needs a C shim for the
/// Clang `ptrauth_*` builtins the Swift importer cannot see.)
enum ARM64 {

  /// The four instructions (`movz` + three `movk`) that load a 64-bit immediate
  /// into `x<register>`, 16 bits at a time. Mirrors the standard A64 wide-move
  /// sequence: `movz` clears the register and sets bits [15:0], each `movk`
  /// keeps the rest and overwrites one 16-bit lane (`hw` selects the lane).
  static func loadImmediate64(into register: UInt32, _ value: UInt64) -> [UInt32] {
    func lane(_ shift: UInt64) -> UInt32 { UInt32((value >> shift) & 0xFFFF) }
    func movk(hw: UInt32, _ shift: UInt64) -> UInt32 {
      0xF280_0000 | (hw << 21) | (lane(shift) << 5) | register
    }
    return [
      0xD280_0000 | (lane(0) << 5) | register,  // movz x<r>, #lane0
      movk(hw: 1, 16),  // movk x<r>, #lane1, lsl #16
      movk(hw: 2, 32),  // movk x<r>, #lane2, lsl #32
      movk(hw: 3, 48),  // movk x<r>, #lane3, lsl #48
    ]
  }

  // Fixed instructions the bootstrap blobs use verbatim.
  static let movzX1Zero: UInt32 = 0xD280_0001  // movz x1, #0        (pthread attr = NULL)
  static let movzX1RTLDNow: UInt32 = 0xD280_0041  // movz x1, #2     (RTLD_NOW)
  static let movnX0One: UInt32 = 0x9280_0020  // movn x0, #1 → x0 = -2 (RTLD_DEFAULT)
  static let blrX16: UInt32 = 0xD63F_0200  // blr x16
  static let blrX0: UInt32 = 0xD63F_0000  // blr x0
  static let branchToSelf: UInt32 = 0x1400_0000  // b .  (spin until terminated)
  static let pushFPLR: UInt32 = 0xA9BF_7BFD  // stp x29, x30, [sp, #-16]!
  static let popFPLR: UInt32 = 0xA8C1_7BFD  // ldp x29, x30, [sp], #16
  static let ret: UInt32 = 0xD65F_03C0  // ret
}
