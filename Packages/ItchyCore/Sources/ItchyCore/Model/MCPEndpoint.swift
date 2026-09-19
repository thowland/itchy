import Foundation

/// What `endpoint.json` holds (§11.1).
///
/// The shim reads this to find the running server. It carries the *bound* port,
/// which is not necessarily the configured one, and the process that bound it,
/// so that a file left behind by a crash can be recognised as stale rather than
/// connected to.
public struct MCPEndpoint: Sendable, Codable, Equatable {
  public let host: String
  public let port: Int
  public let processIdentifier: Int32
  public let startedAt: Date

  public init(host: String = MCPEndpoint.loopbackHost, port: Int, processIdentifier: Int32, startedAt: Date) {
    self.host = host
    self.port = port
    self.processIdentifier = processIdentifier
    self.startedAt = startedAt
  }

  /// Written rather than derived at read time. `FR-8.3` binds loopback and
  /// nothing else, and a shim that reads the host from the file rather than
  /// assuming it will keep working if that ever becomes configurable — which it
  /// will not, but the file costs nothing to write honestly.
  public static let loopbackHost = "127.0.0.1"

  public var url: String { "http://\(host):\(port)/mcp" }
}
