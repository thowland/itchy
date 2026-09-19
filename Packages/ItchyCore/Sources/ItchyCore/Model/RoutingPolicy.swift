import Foundation

/// Whether model-backed work on a pad may reach a remote service (`FR-9.1`).
///
/// Defaults to `localOnly`, and the policy is enforced below the view layer at
/// the single call site of `Transform.apply` (`FR-9.2`), so that every path
/// which can run a transform is subject to it rather than each path being made
/// to agree. Agents are not one of those paths and are not going to be: D-30
/// declines a transform tool, so the five of `FR-8.5` stand.
public enum RoutingPolicy: String, Sendable, Codable, CaseIterable {
  case localOnly
  case remotePermitted
  case askEachTime

  public static let `default`: RoutingPolicy = .localOnly
}
