import Foundation
import ItchyCore
import Security

/// Keeps the bearer token in the Keychain as a generic password (`NFR-3.3`).
///
/// Performs only. Which token, whether one matches and what a refusal means are
/// `MCPToken`'s and `MCPAuthorization`'s; this reads and writes.
///
/// The access group is deliberately part of the account rather than of the
/// item's access group attribute for now: the stdio shim of Sprint 9 reads the
/// same item, and giving both binaries a shared Keychain group is a signing
/// question that cannot be settled before there is a certificate to sign with.
public struct MCPTokenKeychain: Sendable {
  public enum KeychainError: Error, Sendable, Equatable {
    case failed(status: Int32)
  }

  public static let service = "com.itchy.mcp"
  public static let account = "bearer-token"

  public init() {}

  public func load() throws -> MCPToken? {
    var query = Self.baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError.failed(status: status) }
    guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
      return nil
    }
    return MCPToken(value: value)
  }

  /// Replaces whatever is there. Regeneration invalidates the old token
  /// immediately (`FR-8.4`), which is why this deletes rather than updating: an
  /// update that silently failed would leave the old token working.
  public func save(_ token: MCPToken) throws {
    try delete()
    var query = Self.baseQuery
    query[kSecValueData as String] = Data(token.value.utf8)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError.failed(status: status) }
  }

  public func delete() throws {
    let status = SecItemDelete(Self.baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.failed(status: status)
    }
  }

  /// Loads the token, generating and storing one the first time.
  public func loadOrCreate() throws -> MCPToken {
    if let existing = try load() { return existing }
    let token = MCPToken.generate()
    try save(token)
    return token
  }

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
