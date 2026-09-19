import Foundation
import ItchyCore
import Security

/// The remote model's API key (`FR-9.5`, `NFR-3.3`).
///
/// In the Keychain, never in the support directory and never in a log. The
/// second half is not a promise to be careful: `LogEvent`'s vocabulary is
/// closed and has no factory that takes a credential (D-26), so there is no
/// call site that could write one even by accident, and `settings.json` has no
/// field to put one in.
///
/// Reached through `MCPTokenStore`'s shape rather than a new one, so that the
/// suite gets an in-memory store here too and no test opens the real Keychain
/// (D-26, and `Scripts/arch-lint.sh`'s fifth check).
public struct ModelCredentialKeychain: MCPTokenStore {
  public static let service = "com.itchy.model"
  public static let account = "remote-api-key"

  public init() {}

  public func load() throws -> MCPToken? {
    var query = Self.baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data,
      let value = String(bytes: data, encoding: .utf8)
    else { return nil }
    return MCPToken(value: value)
  }

  public func save(_ token: MCPToken) throws {
    try delete()
    var query = Self.baseQuery
    query[kSecValueData as String] = Data(token.value.utf8)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw MCPTokenKeychain.KeychainError.failed(status: status)
    }
  }

  public func delete() throws {
    let status = SecItemDelete(Self.baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw MCPTokenKeychain.KeychainError.failed(status: status)
    }
  }

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

/// A remote model behind an OpenAI-compatible endpoint (`FR-9.5`).
///
/// One shape rather than a provider per service: `/v1/chat/completions` with a
/// bearer key is what almost everything speaks, including the local servers
/// somebody might run instead of Ollama. D-4 permits the application one
/// dependency and D-5 spent it on the MCP SDK, so this is `URLSession` and
/// `JSONSerialization` rather than a second one.
public struct RemoteModelClient: ModelClient {
  private let endpoint: String
  private let apiKey: String
  private let session: URLSession

  public init(endpoint: String, apiKey: String, session: URLSession? = nil) {
    self.endpoint = endpoint
    self.apiKey = apiKey
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = OllamaClient.timeout
      self.session = URLSession(configuration: configuration)
    }
  }

  public func complete(_ request: ModelRequest) async throws -> String {
    guard let url = URL(string: endpoint + "/v1/chat/completions") else {
      throw ModelFailure.unreachable(endpoint: endpoint)
    }
    var post = URLRequest(url: url)
    post.httpMethod = "POST"
    post.setValue("application/json", forHTTPHeaderField: "Content-Type")
    post.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    post.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": request.model,
      "messages": [
        ["role": "system", "content": request.instruction],
        ["role": "user", "content": ModelPrompt.body(request)],
      ],
      "stream": false,
    ])

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: post)
    } catch let error as URLError where error.code == .timedOut {
      throw ModelFailure.timedOut(seconds: Int(OllamaClient.timeout))
    } catch {
      throw ModelFailure.unreachable(endpoint: endpoint)
    }

    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      throw ModelFailure.refused(status: status, detail: ChatCompletion.error(in: data))
    }
    return try ChatCompletion.text(in: data)
  }
}

/// Reading an OpenAI-compatible answer, as a value (D-11).
public enum ChatCompletion {
  public static func text(in data: Data) throws -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let choices = object["choices"] as? [[String: Any]],
      let message = choices.first?["message"] as? [String: Any],
      let content = message["content"] as? String
    else {
      throw ModelFailure.emptyAnswer
    }
    let answer = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !answer.isEmpty else { throw ModelFailure.emptyAnswer }
    return answer
  }

  /// The message a service gives with a refusal, which is usually the useful
  /// part — an expired key says so.
  public static func error(in data: Data) -> String {
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    let error = object?["error"] as? [String: Any]
    let message = error?["message"] as? String
    return message ?? "No detail given."
  }
}
