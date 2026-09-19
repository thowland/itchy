import Foundation

/// The port the loopback MCP server may be asked to bind (§11.1).
///
/// §11.1 asked for "8-something in the ephemeral-adjacent range, configurable"
/// and declined to give a number. 8899 is well clear of the 49152–65535 range
/// macOS hands out ephemerally, so it cannot collide with a port the system
/// assigned to something else, and it is neither a registered service nor a
/// common development default.
///
/// Zero is permitted and means "any free port". It is what the tests bind, and
/// it is the reason the *bound* port rather than the configured one is what goes
/// into `endpoint.json`: asking for 8899 and getting 8899 is the common case,
/// not a guarantee.
public enum MCPBounds {
  public static let defaultPort = 8899

  /// Zero is the ephemeral request; 1–1023 are privileged and an accessory
  /// application cannot bind them, so offering them would be offering a failure.
  public static let minimumPort = 0
  public static let maximumPort = 65_535

  /// The lowest port that can actually be bound without privilege. A configured
  /// value between 1 and this is raised to the default rather than clamped to
  /// 1024, because a person who typed 80 wanted a working server, not port 1024.
  public static let lowestUnprivilegedPort = 1_024

  public static func clamp(_ requested: Int) -> Int {
    guard requested != 0 else { return 0 }
    guard requested >= lowestUnprivilegedPort else { return defaultPort }
    return min(requested, maximumPort)
  }
}
