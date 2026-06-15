import AgentCLI
import Foundation
import UIToolCore

// SPEC: command.uitool.classes
/// Handles the `classes` op **off the main thread**. Class enumeration/reflection
/// reads thread-safe runtime metadata and touches no view or instance state, so it
/// is not marshaled to the target main thread — a 30k-class `objc_copyClassList`
/// walk would blow the bounded main-thread hop. Dispatched directly by
/// `makeBoundedHandler` on the server's background thread.
enum ClassesHandler {

  static func handle(_ request: WireRequest) -> String {
    if let className = request.className {
      return encode(
        WireResponse<ClassInfo>.success(
          id: request.id, ClassBrowser.reflect(className: className)), id: request.id)
    }
    if let pattern = request.match {
      let result = ClassBrowser.list(
        pattern: pattern, matches: matcher(for: pattern), limit: request.limit ?? 200)
      return encode(WireResponse<ClassList>.success(id: request.id, result), id: request.id)
    }
    return encode(
      WireResponse<ClassList>.failure(
        id: request.id,
        WireError(
          code: "BAD_SELECTOR", message: "classes requires --match or --class",
          recover: "pass --match <regex> or --class <name>")), id: request.id)
  }

  /// A name matcher from the regex; an uncompilable pattern (caught CLI-side first)
  /// degrades to a substring match.
  private static func matcher(for pattern: String) -> (String) -> Bool {
    if let regex = try? Regex(pattern) {
      return { (try? regex.firstMatch(in: $0)) != nil }
    }
    return { $0.contains(pattern) }
  }

  private static func encode<P>(_ response: WireResponse<P>, id: Int) -> String {
    (try? Output.line(response)) ?? "{\"v\":1,\"id\":\(id),\"ok\":false}"
  }
}
