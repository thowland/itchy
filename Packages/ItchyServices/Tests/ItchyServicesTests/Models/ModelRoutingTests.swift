import Foundation
import ItchyCore
import Testing

@testable import ItchyServices

/// Sprint 10's decisions: where a model transform's text goes, and the one
/// place it must never go.
@Suite("Model routing")
struct ModelRoutingTests {
  private let local = ModelSettings(localModel: "llama3.2")
  private let remote = ModelSettings(
    localModel: "", remoteEndpoint: "https://api.example.com", remoteModel: "big")
  private let both = ModelSettings(
    localModel: "llama3.2", remoteEndpoint: "https://api.example.com", remoteModel: "big")

  // MARK: - FR-9.4, the guarantee

  /// The requirement in one test: "failure to reach [the local endpoint] MUST
  /// NOT fall back to a remote service under any policy." Exhaustive over the
  /// policies and over whether a remote is configured, because "under any
  /// policy" is a claim about all of them.
  @Test("An unreachable local model never becomes a remote request")
  func noFallbackToRemote() {
    for policy in RoutingPolicy.allCases {
      for settings in [local, remote, both] {
        let after = ModelRouter.afterLocalFailure(settings: settings, policy: policy)
        #expect(after != .remote, "fell back to remote under \(policy)")
        guard case .refusedByPolicy(let reason) = after else {
          Issue.record("expected a refusal under \(policy), got \(after)")
          continue
        }
        #expect(reason.contains("could not be reached"))
        #expect(reason.contains("does not send text to a remote service"))
      }
    }
  }

  // MARK: - FR-9.1 and FR-9.2 applied

  @Test("Local is preferred whatever the policy says, because it sends nothing")
  func localFirst() {
    for policy in RoutingPolicy.allCases {
      #expect(
        ModelRouter.destination(prefersRemote: false, settings: local, policy: policy) == .local)
      #expect(
        ModelRouter.destination(prefersRemote: false, settings: both, policy: policy) == .local)
    }
  }

  @Test("A transform that wants remote gets it only where the pad permits")
  func remoteNeedsPermission() {
    #expect(
      ModelRouter.destination(prefersRemote: true, settings: remote, policy: .remotePermitted)
        == .remote)
    #expect(
      ModelRouter.destination(prefersRemote: true, settings: remote, policy: .askEachTime)
        == .needsConsent)
  }

  /// A local-only pad with no local model is refused rather than quietly served
  /// from somewhere else.
  @Test("Local-only with nothing local is a refusal, not a remote call")
  func localOnlyWithoutLocal() {
    let destination = ModelRouter.destination(
      prefersRemote: true, settings: remote, policy: .localOnly)
    guard case .refusedByPolicy(let reason) = destination else {
      Issue.record("expected a refusal, got \(destination)")
      return
    }
    #expect(reason.contains("local only"))
  }

  /// Wanting remote and having only local is the one permitted fallback, and it
  /// goes in the safe direction.
  @Test("Wanting remote with only a local model stays local")
  func fallsBackOnlyInward() {
    #expect(
      ModelRouter.destination(prefersRemote: true, settings: local, policy: .remotePermitted)
        == .local)
  }

  @Test("Nothing configured says so, which is not the same as a refusal")
  func unconfigured() {
    for policy in RoutingPolicy.allCases {
      #expect(
        ModelRouter.destination(prefersRemote: false, settings: ModelSettings(), policy: policy)
          == .unconfigured)
    }
  }

  // MARK: - Settings

  @Test("A model is configured only when both its endpoint and name are set")
  func configuration() {
    #expect(ModelSettings().isConfigured == false)
    #expect(ModelSettings(localModel: "x").hasLocalModel)
    #expect(ModelSettings(localEndpoint: "", localModel: "x").hasLocalModel == false)
    #expect(ModelSettings(localModel: "   ").hasLocalModel == false)
    #expect(remote.hasRemoteModel)
    #expect(both.isConfigured)
  }

  @Test("The defaults are Ollama's, and nothing is configured out of the box")
  func defaults() {
    #expect(ModelSettings.defaultLocalEndpoint == "http://127.0.0.1:11434")
    #expect(ModelSettings().isConfigured == false)
    #expect(AppSettings().models == ModelSettings())
  }

  // MARK: - FR-9.6, the menu

  /// "Deterministic operations presented first" is the requirement, not a
  /// preference.
  @Test("Model transforms come after every deterministic group")
  func deterministicFirst() {
    let models = ModelTransforms.all(client: { nil }, model: { "m" })
    let groups = TransformRegistry.groups(includingModels: models)
    #expect(groups.count == TransformRegistry.deterministicGroups.count + 1)
    #expect(groups.last?.map(\.id) == ModelTransforms.identifiers)
    let deterministic = groups.dropLast().flatMap { $0 }
    #expect(deterministic.allSatisfy { !ModelTransforms.identifiers.contains($0.id) })
  }

  @Test("With no model configured the menu is exactly what it was")
  func noModelsNoGroup() {
    #expect(
      TransformRegistry.groups(includingModels: []).count
        == TransformRegistry.deterministicGroups.count)
  }

  @Test("A model transform is a transform, with a stable id and a title")
  func modelTransformsAreTransforms() {
    let models = ModelTransforms.all(client: { nil }, model: { "m" })
    #expect(models.count == 3)
    #expect(models.allSatisfy { !$0.id.isEmpty && !$0.title.isEmpty })
    #expect(Set(models.map(\.id)).count == models.count)
  }

  @Test("A model transform is not offered for empty text")
  func applicability() {
    let model = ModelTransforms.all(client: { nil }, model: { "m" })[0]
    #expect(model.applicability(to: TransformInput(plainText: "text")) == .applicable)
    if case .applicable = model.applicability(to: TransformInput(plainText: "   ")) {
      Issue.record("empty text should not be offered")
    }
  }

  /// Through the runner rather than straight at the transform, because that is
  /// the only path production has — `Scripts/arch-lint.sh` holds `apply` to one
  /// call site, and a test that goes round it is testing something nothing does.
  @Test("With no client the transform fails with something to do about it")
  func unconfiguredTransform() async {
    let model = ModelTransforms.all(client: { nil }, model: { "m" })[0]
    await #expect(throws: TransformError.self) {
      try await TransformRunner().run(model, on: TransformInput(plainText: "text"))
    }
  }
}
