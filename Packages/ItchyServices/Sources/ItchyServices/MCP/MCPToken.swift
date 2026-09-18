import Foundation
import ItchyCore

/// The bearer token an agent must present (§11.2, `NFR-3.3`).
///
/// A value, so that generating one, comparing one and storing one are three
/// separate things and only the third needs a Keychain.
public struct MCPToken: Sendable, Equatable {
  public let value: String

  public init(value: String) {
    self.value = value
  }

  /// 32 bytes from the system's CSPRNG, base64url-encoded so that it survives
  /// an `Authorization` header and a shell copy-paste without escaping.
  public static func generate() -> MCPToken {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "the system CSPRNG failed: \(status)")
    return MCPToken(value: base64URL(Data(bytes)))
  }

  /// Compares in time independent of where the first difference falls.
  ///
  /// `==` on `String` returns as soon as it finds a mismatch, and the time it
  /// took is a measurement of how much of the token the caller guessed. This is
  /// a loopback service and the attack is not a realistic one, but the correct
  /// comparison is three lines and arguing about the threat model costs more.
  public func matches(_ presented: String) -> Bool {
    let expected = Array(value.utf8)
    let actual = Array(presented.utf8)
    // Length is not a secret — the encoding fixes it — so returning early here
    // leaks nothing that the format does not already state.
    guard expected.count == actual.count else { return false }
    var difference: UInt8 = 0
    for (lhs, rhs) in zip(expected, actual) {
      difference |= lhs ^ rhs
    }
    return difference == 0
  }

  /// The `Authorization` header value a client sends.
  public var authorizationHeader: String { "Bearer \(value)" }

  /// Extracts the token from an `Authorization` header, or nil if the header is
  /// absent or not a bearer credential.
  public static func presented(inAuthorizationHeader header: String?) -> String? {
    guard let header else { return nil }
    let prefix = "Bearer "
    guard header.hasPrefix(prefix) else { return nil }
    let token = String(header.dropFirst(prefix.count))
    return token.isEmpty ? nil : token
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

/// Whether a request is allowed to proceed (§11.2).
///
/// An enumeration rather than a `Bool`, because "no" has two shapes here and
/// they mean different things to a client: a missing credential is a client
/// that has not been configured, a wrong one is a client that has been
/// configured wrongly or a token that has since been regenerated.
public enum AuthorizationDecision: Sendable, Equatable {
  case allowed
  case missingCredential
  case rejected

  /// Both refusals answer `401` and neither says anything about what pads
  /// exist (§11.2).
  public var statusCode: Int {
    self == .allowed ? 200 : 401
  }
}

public enum MCPAuthorization {
  public static func decide(header: String?, expected: MCPToken?) -> AuthorizationDecision {
    // No token means the server has not been set up; refusing everything is the
    // safe reading, and it is unreachable in practice because the token is
    // generated when the server is first enabled.
    guard let expected else { return .rejected }
    guard let presented = MCPToken.presented(inAuthorizationHeader: header) else {
      return .missingCredential
    }
    return expected.matches(presented) ? .allowed : .rejected
  }
}
