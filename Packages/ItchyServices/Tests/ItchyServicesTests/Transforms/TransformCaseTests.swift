import Foundation
import ItchyCore
import Testing

@testable import ItchyServices

/// Table-driven coverage of the deterministic set (`FR-6.2`): representative,
/// empty, boundary, malformed and multi-byte input for each transform.
///
/// Every case goes through `TransformRunner`, never through a transform
/// directly, because the runner is the only permitted call site for
/// `Transform.apply` (§12) and because that is the path the menu and MCP take.
struct TransformCaseTests {
  private let runner = TransformRunner()

  private func output(_ id: String, _ text: String, mode: PadMode = .plain) async throws -> String {
    guard let transform = TransformRegistry.transform(id: id) else {
      Issue.record("no transform with id \(id)")
      return ""
    }
    let input = TransformInput(plainText: text, padMode: mode)
    guard case .plainText(let result) = try await runner.run(transform, on: input) else {
      Issue.record("\(id) did not return plain text")
      return ""
    }
    return result
  }

  // MARK: - Case

  @Test(
    "Case transforms, including multi-byte input",
    arguments: [
      ("case.upper", "hello ß straße", "HELLO SS STRASSE"),
      ("case.lower", "HELLO Straße", "hello straße"),
      ("case.upper", "café", "CAFÉ"),
      ("case.lower", "ÅNGSTRÖM", "ångström"),
    ])
  func caseChanges(id: String, input: String, expected: String) async throws {
    #expect(try await output(id, input) == expected)
  }

  /// The conservative rule: raise the first letter of a word, leave the rest
  /// alone, so acronyms and internal capitals survive.
  @Test(
    "Title case leaves the interior of a word alone",
    arguments: [
      ("parse the JSON payload", "Parse The JSON Payload"),
      ("mcdonald and McDonald", "Mcdonald And McDonald"),
      ("hello-world foo_bar", "Hello-World Foo_Bar"),
      ("", ""),
    ])
  func titleCase(input: String, expected: String) {
    #expect(CaseTransform.titleCased(input) == expected)
  }

  // MARK: - Base64

  @Test(
    "Base64 round-trips, including multi-byte input",
    arguments: ["hello", "café ☕️", "line\nbreak"])
  func base64RoundTrip(text: String) async throws {
    let encoded = try await output("base64.encode", text)
    #expect(!encoded.contains("\n"))
    #expect(try await output("base64.decode", encoded) == text)
  }

  @Test(
    "Base64 decode is offered only for base64 that decodes to text",
    arguments: [
      ("aGVsbG8=", true),
      ("not base64!", false),
      ("aGVsbG8", false),  // length is not a multiple of four
      ("//79", false),  // valid base64, but the bytes are not UTF-8
      ("  aGVsbG8=  ", true),  // surrounding whitespace is ignored
    ])
  func base64DecodePredicate(text: String, offered: Bool) {
    let applicability = Base64DecodeTransform().applicability(
      to: TransformInput(plainText: text))
    #expect(applicability.isApplicable == offered)
  }

  // MARK: - URL

  @Test(
    "URL encoding is component encoding, not whole-URL",
    arguments: [
      ("a b", "a%20b"),
      ("k=v&j=w", "k%3Dv%26j%3Dw"),
      ("a/b?c", "a%2Fb%3Fc"),
      ("café", "caf%C3%A9"),
      ("safe-._~", "safe-._~"),
    ])
  func urlEncode(input: String, expected: String) async throws {
    #expect(try await output("url.encode", input) == expected)
  }

  @Test(
    "URL decode is offered only for text that carries valid percent-encoding",
    arguments: [
      ("a%20b", true),
      ("plain text", false),  // nothing to decode
      ("%zz", false),  // malformed
    ])
  func urlDecodePredicate(text: String, offered: Bool) {
    #expect(URLDecodeTransform().applicability(to: TransformInput(plainText: text)).isApplicable == offered)
  }

  // MARK: - Whitespace and lines

  @Test(
    "Trimming takes trailing whitespace per line and both ends overall",
    arguments: [
      ("  a  \n  b  \n", "a\n  b"),
      ("a\t\nb", "a\nb"),
      ("a  \r\nb", "a\r\nb"),
    ])
  func trimming(input: String, expected: String) async throws {
    #expect(try await output("whitespace.trim", input) == expected)
  }

  @Test("Trimming is not offered when there is nothing to trim")
  func trimmingDeclinesNoOp() {
    #expect(!WhitespaceTrimTransform().applicability(to: TransformInput(plainText: "a\nb")).isApplicable)
    #expect(WhitespaceTrimTransform().applicability(to: TransformInput(plainText: "a \nb")).isApplicable)
  }

  @Test("Sorting is ascending, localised and stable")
  func sorting() async throws {
    #expect(try await output("lines.sort", "banana\nApple\ncherry") == "Apple\nbanana\ncherry")
    // Équal under a localised comparison, so the original order must survive.
    #expect(try await output("lines.sort", "b\nB") == "b\nB")
  }

  @Test("Sorting needs at least two lines")
  func sortingNeedsTwoLines() {
    #expect(!SortLinesTransform().applicability(to: TransformInput(plainText: "only one")).isApplicable)
    #expect(SortLinesTransform().applicability(to: TransformInput(plainText: "one\ntwo")).isApplicable)
  }

  // MARK: - Flatten

  @Test("Flatten is offered on a styled pad and not on a plain one")
  func flattenPredicate() {
    let styled = TransformInput(plainText: "text", padMode: .styled)
    let plain = TransformInput(plainText: "text", padMode: .plain)
    #expect(FlattenTransform().applicability(to: styled).isApplicable)
    #expect(!FlattenTransform().applicability(to: plain).isApplicable)
  }

  // MARK: - The empty case, across the set

  /// Every transform declines whitespace-only input rather than succeeding by
  /// doing nothing, which is the boundary the whole set shares.
  ///
  /// `whitespace.trim` is the deliberate exception: whitespace-only text is
  /// exactly what it has something to do with, and emptying the pad is the
  /// right answer rather than a no-op dressed as one.
  @Test("No transform but trimming is offered for whitespace-only input")
  func emptyInputIsNeverOffered() {
    for transform in TransformRegistry.all where transform.id != "whitespace.trim" {
      let applicability = transform.applicability(to: TransformInput(plainText: "   \n  ", padMode: .styled))
      #expect(!applicability.isApplicable, "\(transform.id) offered itself for whitespace-only input")
    }
    #expect(WhitespaceTrimTransform().applicability(to: TransformInput(plainText: "   \n  ")).isApplicable)
  }

  @Test("Truly empty input is offered to nothing at all")
  func trulyEmptyIsNeverOffered() {
    for transform in TransformRegistry.all {
      let applicability = transform.applicability(to: TransformInput(plainText: "", padMode: .styled))
      #expect(!applicability.isApplicable, "\(transform.id) offered itself for empty input")
    }
  }
}
