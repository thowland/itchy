import Foundation
import ItchyCore

/// Where to connect, and with what credential (`FR-8.2`, §11.1).
///
/// A value, so that "the server is not running", "there is a stale endpoint
/// file" and "nobody gave me a token" are three outcomes a test can produce
/// rather than three ways for a subprocess to die quietly. A client that
/// launches this thing shows its standard error in a log nobody reads, so
/// whatever goes wrong has to be said in a form the client will surface.
public enum ShimConfiguration {
  /// The environment variable the token is read from.
  ///
  /// Not the Keychain, which is where §11.1 originally put it. Reading the
  /// application's Keychain item from a second binary needs a shared access
  /// group, and the `keychain-access-groups` entitlement is killed at launch by
  /// AMFI on a Developer ID binary with no matching provisioning profile —
  /// measured, not assumed (D-29). The environment variable is what every other
  /// client already does with this token.
  public static let tokenVariable = "ITCHY_TOKEN"

  /// Points the shim at a support directory other than the standard one.
  ///
  /// An argument rather than an environment variable, on purpose: whoever sets
  /// it decides which server the token is handed to, so it should be visible in
  /// the client's configuration and in `ps` rather than inherited invisibly.
  /// It exists because `FR-8.2`'s acceptance criterion — two clients, two
  /// transports, one pad — cannot be demonstrated against a throwaway store
  /// without it.
  public static let supportRootFlag = "--support-root"

  /// The support directory named on the command line, if one was.
  public static func supportRoot(in arguments: [String]) -> String? {
    guard let flag = arguments.firstIndex(of: supportRootFlag) else { return nil }
    let value = arguments.index(after: flag)
    guard value < arguments.endIndex else { return nil }
    return arguments[value]
  }

  public enum Resolution: Sendable, Equatable {
    case ready(url: URL, token: String)
    /// No `endpoint.json`. The server is off, or Itchy is not running.
    case serverNotRunning
    /// An endpoint file whose process is gone — a crash, not a clean stop.
    case staleEndpoint(processIdentifier: Int32)
    case noToken
  }

  /// `isRunning` is passed in rather than asked for, so the stale-file case is
  /// testable without killing a process.
  public static func resolve(
    endpoint: MCPEndpoint?,
    token: String?,
    isRunning: (Int32) -> Bool
  ) -> Resolution {
    guard let endpoint else { return .serverNotRunning }
    guard isRunning(endpoint.processIdentifier) else {
      return .staleEndpoint(processIdentifier: endpoint.processIdentifier)
    }
    guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .noToken
    }
    guard let url = URL(string: endpoint.url) else { return .serverNotRunning }
    return .ready(url: url, token: token)
  }

  /// What to print on standard error when the shim cannot start. Written for
  /// somebody reading a client's log, which is the only place it will appear.
  public static func message(for resolution: Resolution) -> String? {
    switch resolution {
    case .ready:
      return nil
    case .serverNotRunning:
      return "itchy-mcp: Itchy's agent server is not running. Switch it on in "
        + "Itchy → Settings → Agents."
    case .staleEndpoint(let pid):
      return "itchy-mcp: found a stale endpoint file from process \(pid), which is no "
        + "longer running. Itchy did not shut down cleanly; start it again."
    case .noToken:
      return "itchy-mcp: no token. Set \(tokenVariable) to the token shown in "
        + "Itchy → Settings → Agents."
    }
  }
}
