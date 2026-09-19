import Foundation

/// Something worth recording in the debug log.
///
/// A closed vocabulary, and deliberately so. The initialiser is private and the
/// only way to make an event is one of the factories below, which means no call
/// site can log arbitrary text — and therefore no call site can log a pad's
/// contents by accident. Adding something the log can say is a change to this
/// file, which is a change somebody reviews.
///
/// That restriction is the whole design. Pads are kept out of Spotlight
/// (`NFR-3.4`) and exposed to nothing until the person says so (`NFR-3.2`), and
/// a diagnostic file in `/tmp` that quietly contained the text of every agent
/// write would undo both. So the log carries what happened, to which pad, and
/// how much of it — never what was written.
///
/// Pad *names* are recorded, because half of what there is to debug at the MCP
/// boundary is name resolution, and an identifier alone makes the log useless
/// for it. The settings toggle says so in as many words.
public struct LogEvent: Sendable, Equatable {
  /// Which part of the application spoke. Fixed width in the output, so that a
  /// log can be scanned down its left edge.
  public enum Subsystem: String, Sendable, Equatable, CaseIterable {
    case app
    case store
    case archive
    case mcp
    case transform
  }

  /// One `key=value` pair. An array rather than a dictionary so the order is
  /// the one the factory chose: a dictionary would sort `chars` before `tool`,
  /// and the useful thing is always meant to be first.
  public struct Field: Sendable, Equatable {
    public let key: String
    public let value: String

    public init(_ key: String, _ value: String) {
      self.key = key
      self.value = value
    }
  }

  public let subsystem: Subsystem
  public let message: String
  public let fields: [Field]

  private init(_ subsystem: Subsystem, _ message: String, _ fields: [Field] = []) {
    self.subsystem = subsystem
    self.message = message
    self.fields = fields
  }

  // MARK: - Application lifecycle

  public static func launched(version: String, pads: Int) -> LogEvent {
    LogEvent(.app, "launched", [Field("version", version), Field("pads", String(pads))])
  }

  public static func terminating(flush: String) -> LogEvent {
    LogEvent(.app, "terminating", [Field("flush", flush)])
  }

  // MARK: - The store

  public static func storeFault(_ fault: PadStoreFault) -> LogEvent {
    LogEvent(
      .store, "fault",
      [
        Field("pad", fault.padID?.description ?? "—"),
        Field("editable", fault.prohibitsEditing ? "no" : "yes"),
        Field("reason", fault.reason),
      ])
  }

  public static func padCreated(_ id: PadID, name: String, by origin: WriteOrigin) -> LogEvent {
    LogEvent(
      .store, "pad created",
      [Field("pad", name), Field("id", id.description), Field("by", origin.logDescription)])
  }

  public static func padDeleted(_ id: PadID, name: String) -> LogEvent {
    LogEvent(.store, "pad deleted", [Field("pad", name), Field("id", id.description)])
  }

  public static func exposureChanged(_ name: String, exposed: Bool) -> LogEvent {
    LogEvent(.store, "exposure changed", [Field("pad", name), Field("exposed", yesNo(exposed))])
  }

  // MARK: - Archives (D-18)

  /// The attempt and its outcome together, because every one of `archiveIfNeeded`'s
  /// early returns is a different answer to "why is there no backup" and the log
  /// exists to tell them apart.
  public static func archiveAttempt(trigger: String, outcome: ArchiveAttempt) -> LogEvent {
    LogEvent(
      .archive, "attempt",
      [Field("trigger", trigger), Field("outcome", outcome.logDescription)])
  }

  public static func archiveTaken(name: String, pads: Int, retained: Int) -> LogEvent {
    LogEvent(
      .archive, "taken",
      [Field("archive", name), Field("pads", String(pads)), Field("retained", String(retained))])
  }

  public static func archivesPruned(removed: Int, retention: Int) -> LogEvent {
    LogEvent(
      .archive, "pruned",
      [Field("removed", String(removed)), Field("retention", String(retention))])
  }

  public static func archivesRemoved(count: Int) -> LogEvent {
    LogEvent(.archive, "all removed", [Field("count", String(count))])
  }

  // MARK: - The agent server (§11)

  public static func serverStarting(port: Int) -> LogEvent {
    LogEvent(.mcp, "starting", [Field("configuredPort", String(port))])
  }

  public static func serverListening(port: Int, configured: Int) -> LogEvent {
    LogEvent(
      .mcp, "listening",
      [Field("port", String(port)), Field("configuredPort", String(configured))])
  }

  public static func serverFailed(reason: String) -> LogEvent {
    LogEvent(.mcp, "could not start", [Field("reason", reason)])
  }

  public static func serverStopped() -> LogEvent {
    LogEvent(.mcp, "stopped")
  }

  public static func tokenRegenerated() -> LogEvent {
    LogEvent(.mcp, "token regenerated")
  }

  /// Authorisation, before the SDK sees anything. The token itself is never a
  /// field here, in either direction.
  public static func request(method: String, path: String, decision: String) -> LogEvent {
    LogEvent(
      .mcp, "request",
      [Field("method", method), Field("path", path), Field("auth", decision)])
  }

  public static func sessionRouted(_ route: String, sessions: Int) -> LogEvent {
    LogEvent(.mcp, "session", [Field("route", route), Field("open", String(sessions))])
  }

  /// A tool call and what became of it. `chars` is a length, never the text.
  public static func toolCall(tool: String, pad: String?, outcome: String, characters: Int?) -> LogEvent {
    var fields = [Field("tool", tool)]
    if let pad { fields.append(Field("pad", pad)) }
    fields.append(Field("outcome", outcome))
    if let characters { fields.append(Field("chars", String(characters))) }
    return LogEvent(.mcp, "tool call", fields)
  }

  public static func resourceRead(uri: String, outcome: String, characters: Int?) -> LogEvent {
    var fields = [Field("uri", uri), Field("outcome", outcome)]
    if let characters { fields.append(Field("chars", String(characters))) }
    return LogEvent(.mcp, "resource read", fields)
  }

  /// Where an agent's write landed, which is the question §11.6 exists about.
  public static func agentWrite(pad: String, destination: String, characters: Int) -> LogEvent {
    LogEvent(
      .mcp, "write routed",
      [Field("pad", pad), Field("to", destination), Field("chars", String(characters))])
  }

  // MARK: - Transforms (D-24)

  /// `characters` is the size of what the transform was given, not of what it
  /// produced: the input is the thing that explains a slow or refused run, and
  /// a styled output has no character count to report anyway.
  public static func transformApplied(_ id: String, scope: String, characters: Int) -> LogEvent {
    LogEvent(
      .transform, "applied",
      [Field("transform", id), Field("scope", scope), Field("chars", String(characters))])
  }

  public static func transformDeclined(_ id: String, reason: String) -> LogEvent {
    LogEvent(.transform, "declined", [Field("transform", id), Field("reason", reason)])
  }

  private static func yesNo(_ flag: Bool) -> String { flag ? "yes" : "no" }
}

/// Why an archive was or was not taken.
///
/// `archiveIfNeeded` had four silent early returns, each meaning something
/// different to somebody asking why their backups stopped. Naming them makes
/// the difference visible in the log and testable in the suite (D-11).
public enum ArchiveAttempt: Sendable, Equatable {
  case taken
  case notDue
  case disabled
  case unchanged
  /// There are no pads yet. A fresh install, and not a fault.
  case nothingToArchive
  case failed

  public var logDescription: String {
    switch self {
    case .taken: "taken"
    case .notDue: "not due"
    case .disabled: "disabled"
    case .unchanged: "unchanged since last"
    case .nothingToArchive: "nothing to archive"
    case .failed: "failed"
    }
  }
}

extension WriteOrigin {
  /// Short, stable, and free of anything the person typed.
  public var logDescription: String {
    switch self {
    case .user: "user"
    case .transform(let name): "transform:\(name)"
    case .mcp(let client): "mcp:\(client ?? "unnamed")"
    }
  }
}
