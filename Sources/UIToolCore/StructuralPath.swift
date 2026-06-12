// SPEC: domain.uitool.node-id
/// The structural-path encoding [[domain.uitool.node-id]] commits to: a
/// root-relative breadcrumb of class-mnemonic + same-class-sibling-ordinal
/// segments (`w0/cv/tv0/tr3/c1`). The path is the staleness anchor and a
/// legible handle, so the mnemonic must be **deterministic** (the same class
/// always yields the same token) and **legible** (a reader can guess
/// `NSTableView` from `tv`).
///
/// The window segment (`w<n>`) and a window's content view (`cv`) are fixed
/// tokens minted by the tree walk. Every other descendant's mnemonic is derived
/// here from its runtime class name: drop the framework prefix, then take the
/// initials of the CamelCase words, lowercased — `NSTableView` → `tv`,
/// `NSScrollView` → `sv`, `NSTextField` → `tf`. The spec's `tr`/`c` are
/// illustrative of the *shape*, not a fixed dictionary; what the contract pins is
/// determinism + the `<mnemonic><ordinal>` form, which this rule satisfies.
public enum StructuralPath {
  /// The fixed token for a window's content view.
  public static let contentView = "cv"

  /// The `w<n>` token for the nth top-level window.
  public static func window(_ index: Int) -> String { "w\(index)" }

  /// A deterministic, legible mnemonic for a runtime class name. Strips a leading
  /// framework prefix (`NS`, `_NS`, `CA`, `UI`), then lowercases the initials of
  /// the remaining CamelCase words. A name with no usable letters (or only the
  /// prefix) falls back to the lowercased stripped name, then to `v`, so a
  /// mnemonic is always non-empty.
  public static func mnemonic(forClass className: String) -> String {
    let stripped = stripPrefix(from: className)
    let initials = initials(of: stripped)
    if !initials.isEmpty { return initials }
    let lowered = stripped.lowercased()
    return lowered.isEmpty ? "v" : lowered
  }

  /// Drop a leading framework prefix so the mnemonic reflects the class's role,
  /// not its framework. Only a prefix immediately followed by an uppercase letter
  /// is stripped, so a class like `NSObject` keeps its `O`.
  private static func stripPrefix(from name: String) -> String {
    for prefix in ["_NS", "NS", "CA", "UI"] {
      guard name.hasPrefix(prefix) else { continue }
      let rest = name.dropFirst(prefix.count)
      if let first = rest.first, first.isUppercase {
        return String(rest)
      }
    }
    return name
  }

  /// The lowercased initials of a CamelCase identifier — every uppercase letter
  /// that begins a word. `TableView` → `tv`, `ScrollView` → `sv`. Digits and
  /// later lowercase letters are ignored.
  private static func initials(of name: String) -> String {
    var out = ""
    for character in name where character.isUppercase {
      out.append(Character(character.lowercased()))
    }
    return out
  }
}
