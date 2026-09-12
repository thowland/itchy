import Foundation

/// Whether model-backed work on a pad may reach a remote service (`FR-9.1`).
///
/// Defaults to `localOnly`, and the policy is enforced below the view layer so
/// that a transform invoked over MCP is subject to the same restriction as one
/// invoked from the menu (`FR-9.2`).
public enum RoutingPolicy: String, Sendable, Codable, CaseIterable {
  case localOnly
  case remotePermitted
  case askEachTime

  public static let `default`: RoutingPolicy = .localOnly
}
