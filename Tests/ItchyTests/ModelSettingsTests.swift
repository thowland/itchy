import AppKit
import ItchyCore
import ItchyServices
import Testing

@testable import Itchy

/// Sprint 10 through the interface: the routing control, the Models section,
/// and the guarantee that a remote key never lands anywhere it should not.
@MainActor
@Suite("Models and routing in the interface")
struct ModelSettingsTests {
  private func makeCoordinator() -> (PadCoordinator, PadStorageLayout, URL, any MCPTokenStore) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-models-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let layout = PadStorageLayout(root: root)
    let credentials = InMemoryTokenStore()
    let coordinator = PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions(),
      tokenStore: InMemoryTokenStore(), modelCredentials: credentials)
    return (coordinator, layout, root, credentials)
  }

  // MARK: - FR-9.5

  /// The acceptance criterion: "the support directory and logs contain no
  /// credential material after a remote transform."
  ///
  /// Checked by putting a key in, doing everything that writes — settings,
  /// the log, a pad save — and then reading every byte of both.
  @Test("A remote key reaches the Keychain and nothing else")
  func keyGoesNowhereElse() async throws {
    let (coordinator, layout, root, credentials) = makeCoordinator()
    let logPath = root.appendingPathComponent("model.log").path
    defer {
      DebugLog.shared.disable()
      try? FileManager.default.removeItem(at: root)
    }
    DebugLog.shared.enable(atPath: logPath, version: "test")

    let secret = "sk-SECRET-KEY-VALUE-0123456789"
    coordinator.setRemoteAPIKey(secret)
    coordinator.setModelSettings(
      ModelSettings(
        localModel: "llama3.2", remoteEndpoint: "https://api.example.com",
        remoteModel: "big"))
    // Everything that writes to disk, so the check is not vacuous.
    _ = try await coordinator.store.createPad(name: "scratch")
    DebugLog.shared.record(.modelRun("model.tidy", destination: "remote", characters: 12))
    DebugLog.shared.disable()

    #expect(try credentials.load()?.value == secret)

    for file in try FileManager.default.subpathsOfDirectory(atPath: root.path) {
      let path = root.appendingPathComponent(file).path
      guard let data = FileManager.default.contents(atPath: path) else { continue }
      let text = String(bytes: data, encoding: .utf8) ?? ""
      #expect(!text.contains(secret), "the key reached \(file)")
      #expect(!text.contains("SECRET"), "something key-shaped reached \(file)")
    }
  }

  @Test("Clearing the field removes the key rather than storing an empty one")
  func clearingTheKey() throws {
    let (coordinator, _, root, credentials) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.setRemoteAPIKey("a-key")
    #expect(coordinator.hasRemoteAPIKey)
    coordinator.setRemoteAPIKey("   ")
    #expect(try credentials.load() == nil)
    #expect(coordinator.hasRemoteAPIKey == false)
  }

  // MARK: - FR-9.3

  /// "The policy is legible without opening settings, and changes immediately
  /// when altered."
  @Test("A pad shows its routing policy once a model is configured")
  func policyIsVisible() {
    #expect(
      StatusBarModel.showsRouting(modelConfigured: false, policy: .localOnly) == false)
    #expect(StatusBarModel.showsRouting(modelConfigured: true, policy: .localOnly))
    // And whenever the person has moved it off the default, model or not.
    #expect(
      StatusBarModel.showsRouting(modelConfigured: false, policy: .remotePermitted))
    for policy in RoutingPolicy.allCases {
      #expect(!StatusBarModel.routingLabel(policy).isEmpty)
    }
  }

  @Test("Changing the policy on a pad takes effect immediately")
  func policyChanges() async throws {
    let (coordinator, _, root, _) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    let created = try await coordinator.store.createPad(name: "scratch")
    await coordinator.refresh()
    #expect(coordinator.pads.first?.routingPolicy == .localOnly)

    coordinator.setRoutingPolicy(created.id, .askEachTime)

    await expect("the policy to change") {
      coordinator.pads.first?.routingPolicy == .askEachTime
    }
  }

  @Test("Every policy has a choice and only the risky ones carry a note")
  func policyWording() {
    for policy in RoutingPolicy.allCases {
      #expect(!PadSettingsModel.routingChoice(policy).isEmpty)
    }
    #expect(PadSettingsModel.routingNote(.localOnly) == nil)
    #expect(PadSettingsModel.routingNote(.remotePermitted)?.contains("remote model") == true)
    #expect(PadSettingsModel.routingNote(.askEachTime)?.contains("ask") == true)
  }

  // MARK: - FR-9.6

  @Test("Model transforms appear only once a model is configured")
  func transformsAppearWithAModel() async throws {
    let (coordinator, _, root, _) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(coordinator.isModelConfigured == false)
    #expect(coordinator.modelTransforms.isEmpty)

    coordinator.setModelSettings(ModelSettings(localModel: "llama3.2"))

    #expect(coordinator.isModelConfigured)
    #expect(coordinator.modelTransforms.map(\.id) == ModelTransforms.identifiers)
    #expect(coordinator.modelTransform(id: "model.tidy") != nil)
    #expect(coordinator.modelTransform(id: "case.upper") == nil)
  }

  // MARK: - Settings wording

  @Test("The section says what is set up, including nothing")
  func statusWording() {
    #expect(ModelSettingsModel.status(ModelSettings()).contains("No model configured"))
    #expect(ModelSettingsModel.status(ModelSettings(localModel: "m")).contains("on this Mac"))
    let remote = ModelSettings(
      localModel: "", remoteEndpoint: "https://x.example", remoteModel: "big")
    #expect(ModelSettingsModel.status(remote).contains("local only"))
  }

  /// A trailing slash makes a double slash in the path and a 404 that looks
  /// like the server is missing.
  @Test("A pasted endpoint is tidied rather than taken literally")
  func endpointCleaning() {
    #expect(ModelSettingsModel.cleaned(endpoint: " http://x:1/// ") == "http://x:1")
    #expect(ModelSettingsModel.cleaned(name: "  llama3.2 ") == "llama3.2")
    let settings = ModelSettingsModel.settings(
      from: ModelSettings(), localEndpoint: "http://y:2/", localModel: " m ")
    #expect(settings.localEndpoint == "http://y:2")
    #expect(settings.localModel == "m")
  }

  @Test("The key field says where the key goes")
  func keyWording() {
    #expect(ModelSettingsModel.keyCaption.contains("Keychain"))
    #expect(ModelSettingsModel.keyCaption.contains("never written"))
    #expect(ModelSettingsModel.keyDisplay(hasKey: true).contains("Keychain"))
    #expect(ModelSettingsModel.keyDisplay(hasKey: false) == "Not set")
    #expect(ModelSettingsModel.remoteCaption.contains("fails rather than sending"))
  }
}
