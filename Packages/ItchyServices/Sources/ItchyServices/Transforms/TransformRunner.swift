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
  private let consent: any ConsentProviding
  /// Only needed to describe what is about to be sent, and only when the pad
  /// asks each time.
  private let subject: ConsentSubject

  public init(
    policy: RoutingPolicy = .default,
    consent: any ConsentProviding = DeclinesConsent(),
    subject: ConsentSubject = ConsentSubject()
  ) {
    self.policy = policy
    self.consent = consent
    self.subject = subject
  }

  public func run(_ transform: any Transform, on input: TransformInput) async throws -> TransformOutput {
    switch RoutingGate.decide(requiresNetwork: transform.requiresNetwork, policy: policy) {
    case .allowed:
      break
    case .refused(let reason):
      throw TransformError.notApplicable(reason: reason)
    case .needsConsent:
      // `askEachTime` means asked, and a no is a refusal rather than a failure:
      // nothing went wrong, the person said not this time.
      let allowed = await consent.request(
        ConsentRequest(
          padName: subject.padName,
          transformTitle: transform.title,
          endpoint: subject.endpoint,
          characters: input.plainText.count))
      guard allowed else {
        throw TransformError.notApplicable(
          reason: "Not sent. This pad asks before anything leaves the machine.")
      }
    }
    if case .notApplicable(let reason) = transform.applicability(to: input) {
      throw TransformError.notApplicable(reason: reason)
    }
    return try await transform.apply(to: input)
  }
}
