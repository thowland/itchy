import Foundation
import ItchyCore

/// Wording and validation for the Models settings section (D-11, §10, §12).
enum ModelSettingsModel {
  static let sectionTitle = "Models"

  static let localHeading = "On this Mac"
  static let localEndpointLabel = "Endpoint"
  static let localModelLabel = "Model"

  static let remoteHeading = "Remote"
  static let remoteEndpointLabel = "Endpoint"
  static let remoteModelLabel = "Model"
  static let remoteKeyLabel = "API key"

  /// Said where somebody is about to set up a remote model, because it is the
  /// moment the guarantee stops being automatic.
  static let localCaption =
    "Itchy looks here first, always. A model running on this Mac sends nothing "
    + "anywhere, so no pad's routing policy has to permit it."

  static let remoteCaption =
    "Only pads you have set to allow it — or that ask each time — will use this. "
    + "If the local model cannot be reached, Itchy fails rather than sending your "
    + "text here instead."

  /// `FR-9.5`, said plainly at the field.
  static let keyCaption =
    "Kept in your Keychain. It is never written to Itchy's files or its log."

  static func keyDisplay(hasKey: Bool) -> String {
    hasKey ? "Stored in the Keychain" : "Not set"
  }

  static let clearKeyLabel = "Remove"

  /// What the section says about itself when nothing is set up. A scratchpad
  /// with no model configured is the normal state, not a misconfiguration.
  static func status(_ settings: ModelSettings) -> String {
    switch (settings.hasLocalModel, settings.hasRemoteModel) {
    case (false, false):
      return "No model configured. The model-backed transforms are hidden from the "
        + "pad menu until one is."
    case (true, false):
      return "Using \(settings.localModel) on this Mac."
    case (false, true):
      return "Using \(settings.remoteModel), remotely. Pads set to local only cannot "
        + "use it."
    case (true, true):
      return "Using \(settings.localModel) on this Mac, with \(settings.remoteModel) "
        + "available to pads that permit it."
    }
  }

  /// Ollama's own default, offered as a hint rather than filled in, because a
  /// wrong model name produces a clearer failure than a guessed one.
  static let localModelPlaceholder = "llama3.2"
  static let remoteEndpointPlaceholder = "https://api.example.com"
  static let remoteModelPlaceholder = "gpt-4o-mini"

  /// Trims what somebody pasted. A trailing slash on an endpoint produces a
  /// double slash in the path and a 404 that looks like the server is missing.
  static func cleaned(endpoint: String) -> String {
    var value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasSuffix("/") { value.removeLast() }
    return value
  }

  static func cleaned(name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func settings(
    from current: ModelSettings,
    localEndpoint: String? = nil,
    localModel: String? = nil,
    remoteEndpoint: String? = nil,
    remoteModel: String? = nil
  ) -> ModelSettings {
    ModelSettings(
      localEndpoint: cleaned(endpoint: localEndpoint ?? current.localEndpoint),
      localModel: cleaned(name: localModel ?? current.localModel),
      remoteEndpoint: cleaned(endpoint: remoteEndpoint ?? current.remoteEndpoint),
      remoteModel: cleaned(name: remoteModel ?? current.remoteModel))
  }
}
