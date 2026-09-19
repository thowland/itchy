import Foundation
import ItchyCore

/// The local model, over Ollama's HTTP API (`FR-9.4`).
///
/// Performs only. Which model to ask is `ModelRouter`'s, what to ask is
/// `ModelPrompt`'s, and what to do with a failure is the runner's; this sends
/// one request and reads one answer.
///
/// It is on `Scripts/arch-lint.sh`'s list of files permitted to open an
/// outbound connection, which is a short list somebody maintains. Note what
/// that buys: the rule makes it checkable that nothing *else* dials out, which
/// is what `FR-9.4`'s "no outbound connection is made" rests on.
public struct OllamaClient: ModelClient {
  /// Long enough for a small model to work through a pad, short enough that a
  /// wedged server does not look like a hung application. `NFR-1.2` keeps the
  /// interface responsive meanwhile — the call is off the main actor.
  public static let timeout: TimeInterval = 120

  private let endpoint: String
  private let session: URLSession

  public init(endpoint: String, session: URLSession? = nil) {
    self.endpoint = endpoint
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = Self.timeout
      // Nothing about a local model call should be cached, and a proxy between
      // here and 127.0.0.1 would be a surprise worth not having.
      configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
      configuration.connectionProxyDictionary = [:]
      self.session = URLSession(configuration: configuration)
    }
  }

  public func complete(_ request: ModelRequest) async throws -> String {
    guard let url = URL(string: endpoint + "/api/generate") else {
      throw ModelFailure.unreachable(endpoint: endpoint)
    }
    var post = URLRequest(url: url)
    post.httpMethod = "POST"
    post.setValue("application/json", forHTTPHeaderField: "Content-Type")
    post.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": request.model,
      "prompt": ModelPrompt.body(request),
      "system": request.instruction,
      // One answer, not a stream: the applier replaces the range in one
      // undoable step, so a half-finished answer has nowhere to go.
      "stream": false,
    ])

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: post)
    } catch let error as URLError where error.code == .timedOut {
      throw ModelFailure.timedOut(seconds: Int(Self.timeout))
    } catch {
      throw ModelFailure.unreachable(endpoint: endpoint)
    }

    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      throw OllamaReply.failure(status: status, body: data, model: request.model)
    }
    return try OllamaReply.text(in: data)
  }
}

/// Reading Ollama's answers, as a value (D-11).
///
/// Separated from the request because this is where the surprises are: a 404
/// that means "no such model" rather than "no such endpoint", and a 200 whose
/// body is an error.
public enum OllamaReply {
  public static func text(in data: Data) throws -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ModelFailure.emptyAnswer
    }
    if let error = object["error"] as? String {
      throw ModelFailure.refused(status: 200, detail: error)
    }
    let answer = (object["response"] as? String ?? "").trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard !answer.isEmpty else { throw ModelFailure.emptyAnswer }
    return answer
  }

  /// A 404 from Ollama is almost always a model that has not been pulled, not
  /// an endpoint that does not exist — and telling somebody to check their URL
  /// when they need to run `ollama pull` wastes their afternoon.
  public static func failure(status: Int, body: Data, model: String) -> ModelFailure {
    let detail =
      (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?
      .flatMap { $0["error"] as? String } ?? ""
    guard status == 404 else {
      return .refused(status: status, detail: detail.isEmpty ? "No detail given." : detail)
    }
    return .noSuchModel(model)
  }
}
