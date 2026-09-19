import Foundation
import ItchyCore
import Testing

@testable import ItchyServices

/// The formatter is the one piece of the transform layer with real grammar in
/// it, so it is tested directly as well as through the two transforms that use
/// it.
struct JSONFormatterTests {
  @Test("Pretty-printing uses a two-space indent")
  func prettyIndent() throws {
    let output = try JSONFormatter.format(#"{"a":1,"b":[1,2]}"#, style: .pretty)
    #expect(
      output == """
        {
          "a": 1,
          "b": [
            1,
            2
          ]
        }
        """)
  }

  /// The reason this does not go through `JSONSerialization`: a dictionary has
  /// no order to preserve, and §7.2 requires that keys keep theirs.
  @Test("Key order is preserved")
  func keyOrder() throws {
    let source = #"{"zebra":1,"apple":2,"middle":3}"#
    let pretty = try JSONFormatter.format(source, style: .pretty)
    #expect(
      pretty.range(of: "zebra")?.lowerBound ?? source.startIndex
        < (pretty.range(of: "apple")?.lowerBound ?? source.startIndex))
    #expect(try JSONFormatter.format(pretty, style: .minified) == source)
  }

  /// The second reason: a round trip through `Double` rewrites numbers, and a
  /// pad holding an identifier past 2^53 would come back a different number.
  @Test(
    "Numbers keep the spelling they were written with",
    arguments: ["1.0", "1e10", "-0.5", "9007199254740993", "1.230"])
  func numberSpelling(number: String) throws {
    let source = "{\"n\":\(number)}"
    #expect(try JSONFormatter.format(source, style: .minified) == source)
  }

  @Test(
    "Minifying removes all whitespace between tokens",
    arguments: [
      ("{ \"a\" : 1 }", #"{"a":1}"#),
      ("[\n  1,\n  2\n]", "[1,2]"),
      ("{}", "{}"),
      ("[]", "[]"),
      (#"{"a":{"b":{}}}"#, #"{"a":{"b":{}}}"#),
    ])
  func minify(source: String, expected: String) throws {
    #expect(try JSONFormatter.format(source, style: .minified) == expected)
  }

  @Test("Strings pass through with their escapes intact")
  func escapes() throws {
    let source = #"{"a":"line\nbreak \"quoted\" é \\"}"#
    #expect(try JSONFormatter.format(source, style: .minified) == source)
  }

  @Test(
    "Malformed input is rejected rather than half-formatted",
    arguments: [
      "{",
      "{\"a\":}",
      "{\"a\" 1}",
      "[1,]",
      "{'a':1}",
      "{\"a\":01}",
      "{\"a\":+1}",
      "{\"a\":.5}",
      "{\"a\":1}extra",
      "nul",
      "{\"a\":\"unterminated}",
      #"{"a":"\q"}"#,
      #"{"a":"\u12"}"#,
      "",
    ])
  func malformed(source: String) {
    #expect(!JSONFormatter.isValid(source), "\(source) was accepted")
    #expect(throws: JSONFormatter.Failure.self) {
      try JSONFormatter.format(source, style: .pretty)
    }
  }

  @Test(
    "Top-level scalars are JSON too",
    arguments: ["1", "\"text\"", "true", "false", "null"])
  func topLevelScalars(source: String) throws {
    #expect(try JSONFormatter.format(source, style: .minified) == source)
  }

  @Test("A failure names where it stopped")
  func failureOffset() throws {
    do {
      _ = try JSONFormatter.format(#"{"a":1,}"#, style: .pretty)
      Issue.record("expected a failure")
    } catch let failure as JSONFormatter.Failure {
      #expect(failure.offset > 0)
      #expect(failure.message.contains("character"))
    }
  }

  /// §7.2 caps the predicate's parsing. Above the cap it must assume applicable
  /// rather than parse, and the failure then arrives from `apply`.
  @Test("Above the parse cap the predicate stops parsing and apply reports instead")
  func parseCap() async throws {
    let large = String(repeating: "x", count: JSONPredicate.parseCap + 1)
    let input = TransformInput(plainText: large)
    #expect(JSONPrettyTransform().applicability(to: input).isApplicable)
    await #expect(throws: TransformError.self) {
      try await TransformRunner().run(JSONPrettyTransform(), on: input)
    }
  }

  @Test("Below the cap, text that is not JSON is simply not offered")
  func belowCapPredicate() {
    #expect(!JSONPrettyTransform().applicability(to: TransformInput(plainText: "not json")).isApplicable)
    #expect(JSONMinifyTransform().applicability(to: TransformInput(plainText: #"{"a":1}"#)).isApplicable)
  }
}
