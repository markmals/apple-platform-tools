import Foundation

public struct AvailabilityOut: Encodable, Sendable {
  public let introduced: String?
  public let deprecated: String?
  public let obsoleted: String?
  public let message: String?

  public init?(_ a: Availability?) {
    guard let a else { return nil }
    introduced = a.introducedString
    deprecated = a.deprecatedString
    obsoleted = a.obsoletedString
    message = a.message
  }
}

public struct SymbolOut: Encodable, Sendable {
  public let name: String
  public let qualified: String
  public let kind: String
  public let declaration: String
  public let availability: AvailabilityOut?

  public init(_ s: Symbol) {
    name = s.names.title
    qualified = s.qualifiedName
    kind = s.kind.identifier
    declaration = s.declaration
    availability = AvailabilityOut(s.macOSAvailability)
  }
}
