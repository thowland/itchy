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
    showsRouting: Bool = false
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
    return segments
  }

  static func routingLabel(_ policy: RoutingPolicy) -> String {
    switch policy {
    case .localOnly: "local only"
    case .remotePermitted: "remote ok"
    case .askEachTime: "ask"
    }
  }
}
