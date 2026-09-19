import Foundation

/// How an event becomes a line of text, and when the file starts over.
///
/// Both are decisions, so both are values and neither is inside the thing that
/// holds a file handle (D-11). The format is fixed here so that "a log line
/// looks like this" is a test rather than something you find out by enabling
/// logging and looking.
public enum LogLine {
  /// Wide enough for the longest subsystem, so a log can be read down its left
  /// edge rather than by parsing each line.
  internal static let subsystemWidth = 9

  public static func format(_ event: LogEvent, at moment: Date) -> String {
    let stamp = moment.formatted(timestamp)
    let subsystem = event.subsystem.rawValue.padding(
      toLength: Self.subsystemWidth, withPad: " ", startingAt: 0)
    guard !event.fields.isEmpty else { return "\(stamp)  \(subsystem)\(event.message)" }
    let fields = event.fields.map { "\($0.key)=\(escape($0.value))" }.joined(separator: " ")
    return "\(stamp)  \(subsystem)\(event.message) · \(fields)"
  }

  /// What the file says about itself when logging is switched on.
  ///
  /// It states what the log does not contain, because the file sits in `/tmp`
  /// where anyone on the machine can read it, and somebody finding it there is
  /// entitled to know whether their pads are in it.
  public static func header(version: String, at moment: Date) -> String {
    """
    # Itchy debug log — \(version) — opened \(moment.formatted(timestamp))
    # Diagnostics only. This file records what happened, to which pad by name, \
    and how many characters were involved.
    # It does not contain pad contents, agent text, or the server's bearer token.
    # Delete it when you are done; Itchy starts a new one each time logging is \
    switched on.
    """
  }

  /// A value is written on one line, so an embedded newline would forge a
  /// record. Nothing in the vocabulary should contain one — a fault's reason
  /// could, since it carries an underlying error's description.
  internal static func escape(_ value: String) -> String {
    guard value.contains(where: \.isNewline) else { return value }
    return value.split(whereSeparator: \.isNewline).joined(separator: "⏎")
  }

  /// `ISO8601FormatStyle` rather than `ISO8601DateFormatter`, for the reason
  /// `JSONCoding` gives: the formatter is not `Sendable` and a shared one is a
  /// data race waiting for a second thread. Milliseconds are included because
  /// the things this log exists to untangle — a debounce, a save racing a
  /// write — happen inside a second.
  private static let timestamp = Date.ISO8601FormatStyle(
    includingFractionalSeconds: true, timeZone: .gmt)
}

/// Whether the log keeps growing or starts again.
///
/// A debug session left on overnight should not be able to fill `/tmp`. The
/// file starts over rather than rotating into numbered siblings: this is a
/// diagnostic for something happening now, and a second file of yesterday's
/// events is clutter nobody reads.
public enum LogRotation: Sendable, Equatable {
  case append
  case restart

  /// Generous enough to hold a long session at the MCP boundary; small enough
  /// that it cannot become a problem on a full disk.
  public static let sizeLimit = 8 * 1024 * 1024

  public static func decide(currentBytes: Int, incoming: Int, limit: Int = sizeLimit) -> LogRotation {
    currentBytes + incoming > limit ? .restart : .append
  }
}
