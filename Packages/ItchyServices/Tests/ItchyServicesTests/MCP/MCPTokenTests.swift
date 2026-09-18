import Foundation
import ItchyCore
import Testing

@testable import ItchyServices

@Suite("MCP token")
struct MCPTokenTests {
  @Test("A generated token is 32 bytes, base64url, and different every time")
  func generation() {
    let first = MCPToken.generate()
    let second = MCPToken.generate()
    #expect(first != second)
    // 32 bytes base64-encoded is 44 characters with padding, 43 without.
    #expect(first.value.count == 43)
    #expect(first.value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
  }

  @Test("A token matches itself and nothing else")
  func matching() {
    let token = MCPToken(value: "abcdef")
    #expect(token.matches("abcdef"))
    #expect(!token.matches("abcdeg"))
    #expect(!token.matches("abcde"))
    #expect(!token.matches(""))
    #expect(!token.matches("abcdefg"))
  }

  @Test(
    "A bearer credential is extracted, and anything else is not",
    arguments: [
      ("Bearer abc", "abc"),
      ("Bearer ", nil),
      ("bearer abc", nil),
      ("Basic abc", nil),
      ("abc", nil),
      (nil, nil),
    ])
  func extraction(header: String?, expected: String?) {
    #expect(MCPToken.presented(inAuthorizationHeader: header) == expected)
  }

  @Test("The header a client sends is the one the server expects")
  func headerRoundTrip() {
    let token = MCPToken.generate()
    #expect(MCPToken.presented(inAuthorizationHeader: token.authorizationHeader) == token.value)
  }
}

@Suite("MCP authorization")
struct MCPAuthorizationTests {
  private let token = MCPToken(value: "secret")

  @Test("The right credential is allowed")
  func allowed() {
    #expect(MCPAuthorization.decide(header: "Bearer secret", expected: token) == .allowed)
  }

  /// The two refusals are distinguished for the client's sake but answer the
  /// same status, and neither says anything about what pads exist (§11.2).
  @Test(
    "Everything else is refused, with 401 either way",
    arguments: [
      (String?.none, AuthorizationDecision.missingCredential),
      ("Bearer wrong", .rejected),
      ("Basic secret", .missingCredential),
    ])
  func refused(header: String?, expected: AuthorizationDecision) {
    let decision = MCPAuthorization.decide(header: header, expected: token)
    #expect(decision == expected)
    #expect(decision.statusCode == 401)
  }

  @Test("With no token configured, nothing is allowed")
  func noToken() {
    #expect(MCPAuthorization.decide(header: "Bearer anything", expected: nil) == .rejected)
  }

  @Test("Only the allowed decision answers 200")
  func statusCodes() {
    #expect(AuthorizationDecision.allowed.statusCode == 200)
  }
}
