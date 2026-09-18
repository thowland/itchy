import Foundation
import ItchyCore
import Testing

@testable import ItchyServices

/// A transform that exists only to be refused or to throw, so that the runner's
/// own behaviour can be tested without leaning on what a real transform happens
/// to do today.
private struct StubTransform: Transform {
  let id = "stub"
  let title = "Stub"
  var requiresNetwork = false
  var verdict: Applicability = .applicable
  var failure: TransformError?
  /// Set when `apply` runs, so a test can prove it did not.
  let didApply = Box()

  final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var ran: Bool {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
    func mark() {
      lock.lock()
      value = true
      lock.unlock()
    }
  }

  func applicability(to input: TransformInput) -> Applicability { verdict }

  func apply(to input: TransformInput) async throws -> TransformOutput {
    didApply.mark()
    if let failure { throw failure }
    return .plainText("applied")
  }
}

struct TransformRunnerTests {
  private let input = TransformInput(plainText: "text")

  @Test("An applicable transform runs and returns its output")
  func runsWhenApplicable() async throws {
    let output = try await TransformRunner().run(StubTransform(), on: input)
    #expect(output == .plainText("applied"))
  }

  /// `FR-6.3`: a transform is not merely hidden from the menu when it does not
  /// apply, it is refused if something asks for it anyway — which is the case
  /// that matters once MCP can name a transform by identifier.
  @Test("An inapplicable transform is refused before it runs")
  func refusesWhenInapplicable() async {
    let stub = StubTransform(verdict: .notApplicable(reason: "not this one"))
    await #expect(throws: TransformError.notApplicable(reason: "not this one")) {
      try await TransformRunner().run(stub, on: input)
    }
    #expect(!stub.didApply.ran)
  }

  /// `FR-6.6`: the failure reaches the caller intact, so there is something to
  /// show. That nothing was applied is structural — the runner never applies.
  @Test("A throwing transform surfaces its reason")
  func surfacesFailure() async {
    let stub = StubTransform(failure: .failed(reason: "it broke"))
    await #expect(throws: TransformError.failed(reason: "it broke")) {
      try await TransformRunner().run(stub, on: input)
    }
  }

  // MARK: - Routing (§7.3 step 2)

  @Test(
    "Routing is decided before applicability, and before any work",
    arguments: [
      (RoutingPolicy.localOnly, false),
      (RoutingPolicy.askEachTime, false),
      (RoutingPolicy.remotePermitted, true),
    ])
  func routingGatesNetworkTransforms(policy: RoutingPolicy, allowed: Bool) async {
    let stub = StubTransform(requiresNetwork: true)
    let runner = TransformRunner(policy: policy)
    if allowed {
      await #expect(throws: Never.self) { _ = try await runner.run(stub, on: input) }
    } else {
      await #expect(throws: TransformError.self) { try await runner.run(stub, on: input) }
      #expect(!stub.didApply.ran)
    }
  }

  @Test("A transform that needs no network is unaffected by the policy")
  func localTransformIgnoresPolicy() async throws {
    for policy in RoutingPolicy.allCases {
      let output = try await TransformRunner(policy: policy).run(StubTransform(), on: input)
      #expect(output == .plainText("applied"))
    }
  }

  @Test(
    "The gate's decision is the same one, made without a transform",
    arguments: [
      (false, RoutingPolicy.localOnly, RoutingDecision.allowed),
      (
        true, RoutingPolicy.localOnly,
        .refused(reason: "This pad is set to local-only, and this operation needs the network.")
      ),
      (true, RoutingPolicy.askEachTime, .needsConsent),
      (true, RoutingPolicy.remotePermitted, .allowed),
    ])
  func gateDecisions(requiresNetwork: Bool, policy: RoutingPolicy, expected: RoutingDecision) {
    #expect(RoutingGate.decide(requiresNetwork: requiresNetwork, policy: policy) == expected)
  }
}

struct TransformRegistryTests {
  /// `FR-6.2` names ten operations; the registry holds twelve entries because
  /// case is three of them.
  @Test("Every transform FR-6.2 requires is present")
  func requiredSet() {
    let ids = Set(TransformRegistry.all.map(\.id))
    let required: Set<String> = [
      "flatten", "case.upper", "case.lower", "case.title", "json.pretty", "json.minify",
      "base64.encode", "base64.decode", "url.encode", "url.decode", "whitespace.trim", "lines.sort",
    ]
    #expect(required.isSubset(of: ids))
  }

  @Test("Identifiers are unique, since MCP will name transforms by them")
  func uniqueIdentifiers() {
    #expect(Set(TransformRegistry.all.map(\.id)).count == TransformRegistry.all.count)
  }

  @Test("No transform in the deterministic set needs the network")
  func deterministicSetIsLocal() {
    #expect(TransformRegistry.all.allSatisfy { !$0.requiresNetwork })
  }

  @Test("Lookup by identifier finds what the registry holds, and nothing else")
  func lookup() {
    #expect(TransformRegistry.transform(id: "json.pretty") != nil)
    #expect(TransformRegistry.transform(id: "no.such.transform") == nil)
  }

  /// The menu shows every transform and disables the ones that do not apply, so
  /// the survey must answer for all of them rather than filtering.
  @Test("The survey answers for every transform")
  func survey() {
    let survey = TransformRegistry.survey(for: TransformInput(plainText: #"{"a":1}"#))
    #expect(survey.count == TransformRegistry.all.count)
    let json = survey.first { $0.transform.id == "json.pretty" }
    #expect(json?.applicability.isApplicable == true)
    let flatten = survey.first { $0.transform.id == "flatten" }
    #expect(flatten?.applicability.isApplicable == false)
  }
}
