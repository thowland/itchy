import Foundation
import ItchyCore
import Testing

@testable import ItchyServices

/// `FR-9.4` against something real.
///
/// These talk to whatever is listening on the Ollama port, which on a
/// development machine is usually Ollama and on CI is usually nothing. Both are
/// covered: the second case *is* the acceptance criterion — "with the local
/// endpoint stopped, a local-only transform fails with a clear message and no
/// outbound connection is made."
@Suite("The local model endpoint")
struct LocalModelTests {
  /// A port nothing is on. Used as the stopped endpoint, so the test does not
  /// have to stop somebody's Ollama to find out what happens when it is down.
  private let stopped = "http://127.0.0.1:9"

  @Test("An unreachable endpoint fails with the endpoint named", .timeLimit(.minutes(1)))
  func unreachable() async {
    let client = OllamaClient(endpoint: stopped)
    do {
      _ = try await client.complete(
        ModelRequest(instruction: "i", text: "t", model: "whatever"))
      Issue.record("a stopped endpoint should not answer")
    } catch let failure as ModelFailure {
      #expect(failure == .unreachable(endpoint: stopped))
      #expect(failure.reason.contains("127.0.0.1:9"))
      #expect(failure.reason.contains("Is it running?"))
    } catch {
      Issue.record("expected a ModelFailure, got \(error)")
    }
  }

  /// The acceptance criterion's second half, as a property of the code rather
  /// than an observation: there is no input to `afterLocalFailure` that yields
  /// a remote destination. The exhaustive version is in `ModelRoutingTests`;
  /// this one pairs it with a real failed call, so the two halves are known to
  /// meet.
  @Test("A real local failure still refuses to go remote", .timeLimit(.minutes(1)))
  func realFailureDoesNotEscalate() async {
    let settings = ModelSettings(
      localEndpoint: stopped, localModel: "whatever",
      remoteEndpoint: "https://api.example.com", remoteModel: "big")
    let client = OllamaClient(endpoint: stopped)

    await #expect(throws: ModelFailure.self) {
      _ = try await client.complete(ModelRequest(instruction: "i", text: "t", model: "whatever"))
    }

    for policy in RoutingPolicy.allCases {
      #expect(ModelRouter.afterLocalFailure(settings: settings, policy: policy) != .remote)
    }
  }

  /// A transform, end to end, against a stopped endpoint: the pad is untouched
  /// and the reason is fit to show somebody.
  @Test("A model transform against a stopped endpoint fails cleanly", .timeLimit(.minutes(1)))
  func transformFailsCleanly() async {
    let transform = ModelTransforms.all(
      client: { OllamaClient(endpoint: stopped) }, model: { "whatever" })[0]
    do {
      // Through the runner: the one call site production has.
      _ = try await TransformRunner().run(transform, on: TransformInput(plainText: "some text"))
      Issue.record("a stopped endpoint should not produce output")
    } catch let error as TransformError {
      #expect(error.reason.contains("Could not reach"))
    } catch {
      Issue.record("expected a TransformError, got \(error)")
    }
  }

  /// Runs only where something is actually listening. On a machine with Ollama
  /// up it proves the client speaks its API; elsewhere it is skipped rather
  /// than failed, because a missing Ollama is not a broken Itchy.
  @Test("A running endpoint answers the version query", .timeLimit(.minutes(1)))
  func reachesARunningOllama() async throws {
    let endpoint = ModelSettings.defaultLocalEndpoint
    guard let url = URL(string: endpoint + "/api/version"),
      let (_, response) = try? await URLSession.shared.data(from: url),
      (response as? HTTPURLResponse)?.statusCode == 200
    else {
      withKnownIssue("no local model server is running", isIntermittent: true) {
        Issue.record("skipped: nothing is listening on \(endpoint)")
      }
      return
    }

    // It is up, so a request for a model that is certainly not pulled must come
    // back as "no such model" rather than as "unreachable" — which is the
    // distinction the person needs and the one most easily got wrong.
    let client = OllamaClient(endpoint: endpoint)
    do {
      _ = try await client.complete(
        ModelRequest(instruction: "i", text: "t", model: "definitely-not-a-model:0.0b"))
      Issue.record("a model that is not pulled should not answer")
    } catch let failure as ModelFailure {
      #expect(failure == .noSuchModel("definitely-not-a-model:0.0b"))
    } catch {
      Issue.record("expected a ModelFailure, got \(error)")
    }
  }
}
