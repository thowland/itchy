import AppKit
import ItchyCore
import ItchyServices

/// Model-backed transforms, and where their text goes (`FR-9.3`–`FR-9.6`).
extension PadCoordinator {
  /// Whether anything model-backed is set up. Decides whether the model
  /// transforms appear in the menu at all, and whether a pad shows its routing
  /// policy (`FR-9.3`).
  var isModelConfigured: Bool { settings.models.isConfigured }

  /// The model transforms, or none. Built per call rather than held, because
  /// the settings they close over change.
  var modelTransforms: [any Transform] {
    guard isModelConfigured else { return [] }
    let settings = settings.models
    let credentials = modelCredentials
    return ModelTransforms.all(
      client: { await Self.client(for: settings, credentials: credentials) },
      model: { settings.hasLocalModel ? settings.localModel : settings.remoteModel })
  }

  /// Local unless there is no local model, which is the safe direction and the
  /// only fallback `FR-9.4` permits.
  private static func client(
    for settings: ModelSettings, credentials: any MCPTokenStore
  ) async -> (any ModelClient)? {
    guard !settings.hasLocalModel else {
      return OllamaClient(endpoint: settings.localEndpoint)
    }
    guard settings.hasRemoteModel, let key = try? credentials.load()?.value else { return nil }
    return RemoteModelClient(endpoint: settings.remoteEndpoint, apiKey: key)
  }

  func setModelSettings(_ models: ModelSettings) {
    settings.models = models
    persistSettings()
    DebugLog.shared.record(
      .modelConfigured(
        local: models.hasLocalModel ? models.localModel : nil,
        remote: models.hasRemoteModel ? models.remoteModel : nil))
  }

  /// `FR-9.5`: the key goes to the Keychain and nowhere else. Never to
  /// `settings.json`, which has no field for it, and never to the log, whose
  /// vocabulary has no factory that takes one.
  func setRemoteAPIKey(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      try? modelCredentials.delete()
      return
    }
    try? modelCredentials.save(MCPToken(value: trimmed))
  }

  var hasRemoteAPIKey: Bool { (try? modelCredentials.load()) != nil }
}

/// Asks the person, with an alert (§12).
///
/// The one prompt in the application besides deleting a pad. `CON-2` forbids
/// save, title and filing prompts; this is none of those — it is the pad's own
/// `askEachTime` policy being honoured, and a policy called "ask me each time"
/// that did not ask would be a lie in a picker.
@MainActor
struct AlertConsent: ConsentProviding {
  func request(_ consent: ConsentRequest) async -> Bool {
    await MainActor.run {
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = consent.title
      alert.informativeText = consent.detail
      alert.alertStyle = .warning
      alert.addButton(withTitle: ConsentRequest.allow)
      alert.addButton(withTitle: ConsentRequest.deny)
      return alert.runModal() == .alertFirstButtonReturn
    }
  }
}
