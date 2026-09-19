import Foundation

/// Where model-backed transforms send text (`FR-9.4`, `FR-9.5`, §12).
///
/// Two destinations, and they are not interchangeable. The local one is a model
/// running on this Mac and is the default for everything; the remote one is a
/// service, is never reached without the pad's policy allowing it, and is never
/// reached as a *fallback* — `FR-9.4` is explicit that failing to reach the
/// local endpoint must not send the text somewhere else instead.
public struct ModelSettings: Sendable, Codable, Equatable {
  /// Ollama's default. A URL rather than a host so that someone running a
  /// different local server can point at it without a new setting.
  public static let defaultLocalEndpoint = "http://127.0.0.1:11434"

  public var localEndpoint: String
  /// Empty until a model is chosen. Empty is the honest default: guessing a
  /// name produces "model not found" from a server that is working perfectly.
  public var localModel: String

  /// An OpenAI-compatible endpoint. Empty unless the person has set one up.
  public var remoteEndpoint: String
  public var remoteModel: String

  public init(
    localEndpoint: String = ModelSettings.defaultLocalEndpoint,
    localModel: String = "",
    remoteEndpoint: String = "",
    remoteModel: String = ""
  ) {
    self.localEndpoint = localEndpoint
    self.localModel = localModel
    self.remoteEndpoint = remoteEndpoint
    self.remoteModel = remoteModel
  }

  /// Whether local inference is set up well enough to try.
  public var hasLocalModel: Bool {
    !localModel.trimmingCharacters(in: .whitespaces).isEmpty
      && !localEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
  }

  public var hasRemoteModel: Bool {
    !remoteModel.trimmingCharacters(in: .whitespaces).isEmpty
      && !remoteEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
  }

  /// What the interface means by "a model is configured" — either will do, and
  /// it is what decides whether a pad shows its routing policy (`FR-9.3`).
  public var isConfigured: Bool { hasLocalModel || hasRemoteModel }
}
