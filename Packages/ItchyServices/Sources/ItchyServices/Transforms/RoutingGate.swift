import Foundation
import ItchyCore

/// Whether a transform is allowed to run under a pad's routing policy (§7.3
/// step 2, `FR-9.2`).
///
/// A decision, returned as an enumeration and made by a pure function, so that
/// the rule can be tested without a transform, a pad or a network (D-11). It is
/// stated now rather than in R4 because the whole point of there being one call
/// site for `Transform.apply` is that the policy is enforced there; a runner
/// that ignores routing is a runner someone has to remember to fix later.
public enum RoutingDecision: Sendable, Equatable {
  case allowed
  /// The pad forbids it outright.
  case refused(reason: String)
  /// The pad asks each time. No transform in R2 requires the network, so
  /// nothing reaches this case yet; the consent prompt is R4's work, and until
  /// it exists the runner treats this as a refusal rather than assuming a yes.
  case needsConsent
}

public enum RoutingGate {
  public static func decide(requiresNetwork: Bool, policy: RoutingPolicy) -> RoutingDecision {
    guard requiresNetwork else { return .allowed }
    switch policy {
    case .remotePermitted: return .allowed
    case .askEachTime: return .needsConsent
    case .localOnly:
      return .refused(reason: "This pad is set to local-only, and this operation needs the network.")
    }
  }
}
