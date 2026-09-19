import Foundation
import ItchyCore

/// Every transform the application offers, in menu order (`FR-6.2`).
///
/// `groups` is the only place the set is written down: the menu, MCP's tool
/// surface and the tests all read it, so a transform cannot be added to one and
/// forgotten by the others. The grouping lives here rather than in the menu
/// because "which of these belong together" is a decision, and view files do not
/// make decisions (D-11).
public enum TransformRegistry {
  /// The deterministic set: same input, same output, no model, no network.
  public static let deterministicGroups: [[any Transform]] = [
    [FlattenTransform()],
    [CaseTransform(.upper), CaseTransform(.lower), CaseTransform(.title)],
    [JSONPrettyTransform(), JSONMinifyTransform()],
    [
      Base64EncodeTransform(), Base64DecodeTransform(), URLEncodeTransform(),
      URLDecodeTransform(),
    ],
    [WhitespaceTrimTransform(), SortLinesTransform()],
  ]

  public static let groups: [[any Transform]] = deterministicGroups

  /// The same set with the model-backed transforms after it (`FR-9.6`).
  ///
  /// After, not mixed in, and that ordering is the requirement rather than a
  /// preference: "deterministic operations presented first". The deterministic
  /// ones are instant and certain, and a menu that puts a model call above
  /// `Trim Whitespace` teaches the person that this is a model application
  /// with some utilities attached, which is the reading the vision document
  /// exists to prevent.
  public static func groups(
    includingModels models: [any Transform]
  ) -> [[any Transform]] {
    guard !models.isEmpty else { return deterministicGroups }
    return deterministicGroups + [models]
  }

  public static let all: [any Transform] = groups.flatMap { $0 }

  /// Looked up by the stable identifier, which is what MCP will name a
  /// transform by rather than its title.
  public static func transform(id: String) -> (any Transform)? {
    all.first { $0.id == id }
  }

  /// Every transform paired with whether it is offered for this input, which is
  /// what a menu needs: the inapplicable ones are shown disabled with their
  /// reason rather than hidden, so that the menu's shape does not change under
  /// the cursor (`FR-6.3`).
  public typealias Survey = [(transform: any Transform, applicability: Applicability)]

  public static func survey(for input: TransformInput) -> Survey {
    all.map { ($0, $0.applicability(to: input)) }
  }
}
