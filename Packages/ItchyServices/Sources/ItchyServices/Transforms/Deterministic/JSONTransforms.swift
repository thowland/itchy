import Foundation
import ItchyCore

/// Pretty-printing and minifying, sharing a predicate (§7.2).
///
/// The predicate parses to decide, which is honest but not free, and it runs on
/// every menu open. §7.2 caps that: above `parseCap` the predicate assumes the
/// text is applicable rather than parsing it, and a parse failure then surfaces
/// at apply time through `FR-6.6` instead. The cost of being wrong is a message;
/// the cost of parsing four megabytes on every menu open is a menu that stutters.
public enum JSONPredicate {
  /// Public because it is a stated boundary rather than an implementation
  /// detail: §7.2 fixes it, and the behaviour on each side of it differs.
  public static let parseCap = 256 * 1024

  internal static func applicability(to input: TransformInput) -> Applicability {
    guard case .applicable = TextPredicate.hasText(input) else {
      return .notApplicable(reason: "There is no text to transform.")
    }
    guard input.plainText.utf8.count <= parseCap else { return .applicable }
    guard JSONFormatter.isValid(input.plainText) else {
      return .notApplicable(reason: "This text is not JSON.")
    }
    return .applicable
  }

  internal static func format(_ input: TransformInput, style: JSONFormatter.Style) throws -> TransformOutput {
    do {
      return .plainText(try JSONFormatter.format(input.plainText, style: style))
    } catch let failure as JSONFormatter.Failure {
      throw TransformError.failed(reason: "This text is not JSON: \(failure.message).")
    }
  }
}

/// Two-space indent, keys left in the order they were written (§7.2).
public struct JSONPrettyTransform: Transform {
  public let id = "json.pretty"
  public let title = "Pretty-print JSON"
  public let requiresNetwork = false

  public init() {}

  public func applicability(to input: TransformInput) -> Applicability {
    JSONPredicate.applicability(to: input)
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    try JSONPredicate.format(input, style: .pretty)
  }
}

/// The same walk, emitting no whitespace at all (§7.2).
public struct JSONMinifyTransform: Transform {
  public let id = "json.minify"
  public let title = "Minify JSON"
  public let requiresNetwork = false

  public init() {}

  public func applicability(to input: TransformInput) -> Applicability {
    JSONPredicate.applicability(to: input)
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    try JSONPredicate.format(input, style: .minified)
  }
}
