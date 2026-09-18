import Foundation
import ItchyCore

/// The one place `Transform.apply` is called (§7.3, §12, enforced by
/// `Scripts/arch-lint.sh`).
///
/// Both the menu and — from Sprint 9 — an agent over MCP reach a transform
/// through here, so applicability and routing are checked once, in one order,
/// rather than by two paths that are meant to agree and eventually will not.
/// The runner decides and produces; it does not apply. Putting the output into
/// a pad is the caller's job, which is what leaves `FR-6.6` easy to honour: if
/// this throws, nothing has touched the pad.
public struct TransformRunner: Sendable {
  private let policy: RoutingPolicy

  public init(policy: RoutingPolicy = .default) {
    self.policy = policy
  }

  public func run(_ transform: any Transform, on input: TransformInput) async throws -> TransformOutput {
    switch RoutingGate.decide(requiresNetwork: transform.requiresNetwork, policy: policy) {
    case .allowed:
      break
    case .refused(let reason):
      throw TransformError.notApplicable(reason: reason)
    case .needsConsent:
      throw TransformError.notApplicable(
        reason: "This pad asks before each remote operation, which is not yet supported.")
    }
    if case .notApplicable(let reason) = transform.applicability(to: input) {
      throw TransformError.notApplicable(reason: reason)
    }
    return try await transform.apply(to: input)
  }
}
