import Foundation
import ItchyCore

/// A model-backed transform (`FR-9.6`).
///
/// It is a `Transform` like every other one, appears in the same menu, and
/// takes the same route through `TransformRunner` — which is the position the
/// requirement is defending. There is no model panel and no conversation view,
/// because the moment the model gets its own surface it stops being one more
/// thing you can do to a pad and becomes what the application is for.
public struct ModelTransform: Transform {
  public let id: String
  public let title: String
  /// The instruction, already wrapped in `ModelPrompt.rule`.
  public let task: String
  /// Whether this one would rather have a larger, remote model. `ModelRouter`
  /// decides what it actually gets, and a pad set to local-only still keeps it
  /// local.
  public let prefersRemote: Bool

  private let client: @Sendable () async -> (any ModelClient)?
  private let model: @Sendable () async -> String

  public init(
    id: String,
    title: String,
    task: String,
    prefersRemote: Bool = false,
    client: @escaping @Sendable () async -> (any ModelClient)?,
    model: @escaping @Sendable () async -> String
  ) {
    self.id = id
    self.title = title
    self.task = task
    self.prefersRemote = prefersRemote
    self.client = client
    self.model = model
  }

  /// False for a local model, which is the ordinary case: nothing leaves the
  /// machine, so the routing policy has nothing to gate. The provider sets this
  /// to true when the destination it resolved is remote, and `RoutingGate` then
  /// applies the pad's policy exactly as it does to any other network work.
  public var requiresNetwork: Bool { prefersRemote }

  /// Cheap, because it runs on every menu open (`FR-6.3`). It does not ask
  /// whether the model is reachable — that would put an HTTP call behind
  /// opening a menu.
  public func applicability(to input: TransformInput) -> Applicability {
    guard !input.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .notApplicable(reason: "There is no text to work on.")
    }
    return .applicable
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    guard let client = await client() else {
      throw TransformError.failed(
        reason: "No model is configured. Choose one in Settings → Models.")
    }
    let name = await model()
    do {
      let answer = try await client.complete(
        ModelRequest(
          instruction: ModelPrompt.instruction(task),
          text: input.plainText,
          model: name))
      let cleaned = ModelAnswer.cleaned(answer)
      guard !cleaned.isEmpty else {
        throw TransformError.failed(reason: ModelFailure.emptyAnswer.reason)
      }
      return .plainText(cleaned)
    } catch let failure as ModelFailure {
      throw TransformError.failed(reason: failure.reason)
    }
  }
}

/// The model-backed set (`FR-9.6`).
///
/// Three, and all three transform the text rather than talk about it. That is
/// the line `CON-1` and the vision document draw: "summarise this" produces
/// text that replaces text, where "what do you think of this" produces a
/// conversation, and a scratchpad that answers questions is on its way to being
/// a chat window with a save button.
public enum ModelTransforms {
  public static func all(
    client: @escaping @Sendable () async -> (any ModelClient)?,
    model: @escaping @Sendable () async -> String
  ) -> [ModelTransform] {
    [
      ModelTransform(
        id: "model.tidy",
        title: "Tidy Prose",
        task: "Rewrite the text so it reads clearly and plainly. Keep the meaning, "
          + "the voice and the approximate length. Fix grammar and punctuation.",
        client: client, model: model),
      ModelTransform(
        id: "model.summarise",
        title: "Summarise",
        task: "Replace the text with a short summary of it — a few sentences at most, "
          + "or a short list if the text is a list of things.",
        client: client, model: model),
      ModelTransform(
        id: "model.bullets",
        title: "To Bullet Points",
        task: "Rewrite the text as a short list of bullet points, one per line, each "
          + "beginning with a hyphen and a space. Keep every substantive point.",
        client: client, model: model),
    ]
  }

  /// Stable identifiers, named once so the menu ordering and the tests agree.
  public static let identifiers = ["model.tidy", "model.summarise", "model.bullets"]
}
