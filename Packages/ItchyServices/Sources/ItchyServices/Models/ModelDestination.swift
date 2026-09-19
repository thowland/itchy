import Foundation
import ItchyCore

/// Which model a transform reaches, and whether it may (`FR-9.4`, §12).
///
/// The decision `FR-9.4` turns on, and the reason it is a value: "failure to
/// reach the local endpoint MUST NOT fall back to a remote service under any
/// policy" is a rule about what this function may return, and a rule about a
/// return value can be tested exhaustively. Written as a fallback inside a
/// client it would be a rule about what somebody remembered not to write.
public enum ModelDestination: Sendable, Equatable {
  case local
  case remote
  /// Nothing to send to. Distinct from a refusal: the person has not set a
  /// model up, which is a different sentence from "this pad forbids it".
  case unconfigured
  /// The pad's policy forbids the only destination that could serve it.
  case refusedByPolicy(reason: String)
  /// The pad asks each time, and nobody has been asked yet.
  case needsConsent
}

public enum ModelRouter {
  /// `prefersRemote` is what a transform asks for, not what it gets. A
  /// transform that would rather use a bigger model still goes local when the
  /// pad says local-only and a local model exists.
  public static func destination(
    prefersRemote: Bool,
    settings: ModelSettings,
    policy: RoutingPolicy
  ) -> ModelDestination {
    // Local first, always, and regardless of preference: it needs no policy,
    // it sends nothing anywhere, and it is the default this project wants.
    if settings.hasLocalModel, !prefersRemote { return .local }

    guard settings.hasRemoteModel else {
      // Wanting remote and having none falls back to local — which is a
      // fallback in the safe direction, and the only one permitted.
      return settings.hasLocalModel ? .local : .unconfigured
    }

    switch policy {
    case .remotePermitted:
      return .remote
    case .askEachTime:
      return .needsConsent
    case .localOnly:
      // Never silently local instead: the transform asked for remote, and a
      // quieter answer from a smaller model is not the same answer.
      guard !settings.hasLocalModel else { return .local }
      return .refusedByPolicy(
        reason: "This pad is set to local only, and no local model is configured.")
    }
  }

  /// What happens when the local endpoint cannot be reached.
  ///
  /// This is `FR-9.4` stated as a function so it can be asserted: there is no
  /// policy, and no combination of settings, under which an unreachable local
  /// model becomes a remote request. The answer is always the same.
  public static func afterLocalFailure(
    settings: ModelSettings, policy: RoutingPolicy
  ) -> ModelDestination {
    .refusedByPolicy(
      reason: "The local model at \(settings.localEndpoint) could not be reached. "
        + "Itchy does not send text to a remote service when the local one is unavailable.")
  }
}
