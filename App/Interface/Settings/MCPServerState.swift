import Foundation
import ItchyCore

/// What the agent server is doing, as the interface needs to know it
/// (`FR-8.10`, §11.8).
///
/// An enumeration rather than a `Bool` and a port, because "on" has three
/// shapes that mean different things to the person reading them: asked for and
/// not yet bound, bound and on which port, and asked for and refused. A
/// settings toggle that says "on" while the port is taken by something else is
/// a settings toggle that lies.
enum MCPServerState: Equatable, Sendable {
  case off
  case starting
  case listening(port: Int)
  case failed(reason: String)

  var isListening: Bool {
    if case .listening = self { return true }
    return false
  }

  var port: Int? {
    if case .listening(let port) = self { return port }
    return nil
  }
}

/// The wording and the validation for the Agents settings section (D-11,
/// `FR-8.4`, `FR-8.10`).
///
/// Every string the section shows is decided here, so that the view translates
/// and applies rather than decides, and so that "what does it say when the port
/// is taken" is a test rather than a screenshot.
enum MCPSettingsModel {
  static let sectionTitle = "Agents"
  static let enableLabel = "Let agents read and write exposed pads"
  static let portLabel = "Port"
  static let tokenLabel = "Token"
  static let regenerateLabel = "Regenerate"
  static let copyLabel = "Copy"

  /// The range the port field offers. Zero is excluded: it is meaningful to the
  /// listener and meaningless to a person, who would read it as "no port".
  static var portRange: ClosedRange<Int> {
    MCPBounds.lowestUnprivilegedPort...MCPBounds.maximumPort
  }

  static func clampPort(_ requested: Int) -> Int {
    min(max(requested, MCPBounds.lowestUnprivilegedPort), MCPBounds.maximumPort)
  }

  /// What the section says about itself, under the toggle.
  static func status(_ state: MCPServerState) -> String {
    switch state {
    case .off:
      "Off. Nothing outside Itchy can reach your pads."
    case .starting:
      "Starting…"
    case .listening(let port):
      "Listening on 127.0.0.1:\(port). Only this machine can connect, and only "
        + "with the token below."
    case .failed(let reason):
      "Could not start: \(reason)"
    }
  }

  /// Whether the status reads as a problem, which is the one thing the view
  /// needs in order to colour it. A colour is a presentation of a decision, so
  /// the decision is made here.
  static func isWarning(_ state: MCPServerState) -> Bool {
    if case .failed = state { return true }
    return false
  }

  /// What the port field says beneath it. The bound port is named when it is not
  /// the configured one, because otherwise a person reads the field, reads the
  /// shim's error, and has no way to connect the two.
  static func portNote(configured: Int, state: MCPServerState) -> String? {
    guard let bound = state.port, bound != configured else { return nil }
    return "Bound to \(bound) instead; \(configured) was not available."
  }

  /// `FR-8.4`: the token is surfaced, and regenerating it invalidates the
  /// previous one immediately. The second half of that is said, because an
  /// agent that stops working after a click the person did not connect to it is
  /// a support question rather than a security property.
  static let regenerateNote =
    "Regenerating stops the previous token working straight away. Any agent "
    + "using it will need the new one."

  /// Tokens are not passwords and nobody memorises them, but a settings window
  /// is a thing people screen-share. It is shown in full only when asked for.
  static func tokenDisplay(_ token: String?, revealed: Bool) -> String {
    guard let token, !token.isEmpty else { return "Not generated yet." }
    guard !revealed else { return token }
    return String(repeating: "•", count: min(token.count, 32))
  }

  static func revealLabel(revealed: Bool) -> String {
    revealed ? "Hide" : "Show"
  }

  /// What the diagnostic-log section says.
  ///
  /// Here rather than in a `LogSettingsModel` of its own because it is three
  /// strings, and a file per section is how a settings window stops being
  /// readable.
  static let loggingLabel = "Write a diagnostic log"

  /// Says what the log holds and, more importantly, what it does not. The file
  /// sits in `/tmp`, where anyone with an account on this Mac can read it, and
  /// somebody switching this on is entitled to know whether their pads are
  /// about to be in it.
  static func loggingCaption(path: String?) -> String {
    guard let path else {
      return "Off. When on, Itchy records what it does — backups, agent "
        + "requests, transforms — to a file in /tmp. Pad contents and the agent "
        + "token are never written to it."
    }
    return "Writing to \(path). It records what happened and to which pad by "
      + "name, never the pad's text or the agent token. Delete the file when "
      + "you are done."
  }

  static let revealLogLabel = "Show in Finder"

  /// What a pad's own settings say about exposing it (`NFR-3.2`).
  static let exposureLabel = "Let agents read and write this pad"

  static func exposureNote(isExposed: Bool, serverEnabled: Bool) -> String? {
    switch (isExposed, serverEnabled) {
    case (false, _):
      return nil
    case (true, false):
      return "Nothing can reach it until the agent server is switched on, in Settings."
    case (true, true):
      return "Agents can read this pad's text and replace it. The pad says “exposed” "
        + "while they can."
    }
  }
}
