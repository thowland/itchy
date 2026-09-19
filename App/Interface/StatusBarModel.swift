import Foundation
import ItchyCore

/// One element of the pad's status line.
struct StatusSegment: Equatable, Identifiable, Sendable {
  enum Kind: String, Sendable {
    case name
    case mode
    case provenance
    case exposure
    case routing
    case notice
    case fault
  }

  var id: String { kind.rawValue }
  let kind: Kind
  let text: String
}

/// Projects a pad's metadata into the status line shown on its panel
/// (`FR-3.6`, specification §10).
///
/// The status bar grows by release rather than being restructured, so this is
/// written to add segments as the properties behind them start to mean
/// something — exposure in R3, routing in R4.
enum StatusBarModel {
  static func segments(
    for pad: PadMetadata,
    fault: PadStoreFault? = nil,
    showsExposure: Bool = false,
    showsRouting: Bool = false,
    notice: String? = nil
  ) -> [StatusSegment] {
    var segments = [
      StatusSegment(kind: .name, text: pad.name),
      StatusSegment(kind: .mode, text: pad.mode.rawValue),
    ]
    if !pad.provenance.isEmpty {
      let count = pad.provenance.count
      segments.append(
        StatusSegment(kind: .provenance, text: "\(count) paste\(count == 1 ? "" : "s")"))
    }
    if showsExposure {
      segments.append(
        StatusSegment(kind: .exposure, text: pad.isExposedToMCP ? "exposed" : "private"))
    }
    if showsRouting {
      segments.append(StatusSegment(kind: .routing, text: routingLabel(pad.routingPolicy)))
    }
    if let fault {
      segments.append(StatusSegment(kind: .fault, text: fault.reason))
    }
    // Last, and after the fault, because a notice is the most recent thing to
    // have happened and the eye reaches the end of the line for it.
    if let notice {
      segments.append(StatusSegment(kind: .notice, text: notice))
    }
    return segments
  }

  /// Whether the exposure segment is worth the space (`NFR-3.2`, §11.5).
  ///
  /// An exposed pad must say so, always — that is the requirement, and it holds
  /// even when the server is switched off, because "exposed but unreachable"
  /// and "not exposed" are different states and the person is entitled to know
  /// which this pad is in. A pad that is not exposed says "private" only while
  /// the server is running, when the distinction is live; before that it would
  /// be a word on every pad answering a question nobody has asked.
  static func showsExposure(serverEnabled: Bool, isExposed: Bool) -> Bool {
    serverEnabled || isExposed
  }

  static func routingLabel(_ policy: RoutingPolicy) -> String {
    switch policy {
    case .localOnly: "local only"
    case .remotePermitted: "remote ok"
    case .askEachTime: "ask"
    }
  }
}
