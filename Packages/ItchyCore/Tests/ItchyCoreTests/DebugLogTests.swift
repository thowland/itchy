import Foundation
import Testing

@testable import ItchyCore

/// The diagnostic log: what a line looks like, when the file starts over, and
/// — the one that matters — what it is structurally incapable of containing.
@Suite("Debug log")
struct DebugLogTests {
  private let moment = Date(timeIntervalSince1970: 1_800_000_000)

  private func temporaryPath() -> String {
    NSTemporaryDirectory() + "itchy-log-\(UUID().uuidString).log"
  }

  // MARK: - The format

  @Test("A line carries the time, the subsystem and the fields in the order given")
  func format() {
    let line = LogLine.format(
      .toolCall(tool: "read_pad", pad: "Notes", outcome: "ok", characters: 11), at: moment)
    #expect(line.hasPrefix("2027-01-15T08:00:00.000Z"))
    #expect(line.contains("mcp      tool call · "))
    #expect(line.hasSuffix("tool=read_pad pad=Notes outcome=ok chars=11"))
  }

  @Test("An event with no fields has no separator trailing after it")
  func formatWithoutFields() {
    let line = LogLine.format(.serverStopped(), at: moment)
    #expect(line.hasSuffix("mcp      stopped"))
    #expect(!line.contains("·"))
  }

  /// A log is read by scanning down its left edge, which only works if the
  /// column is a column.
  @Test("Every subsystem occupies the same width")
  func subsystemColumn() {
    let widths = LogEvent.Subsystem.allCases.map { subsystem -> Int in
      let line = LogLine.format(.storeFault(.diskSpaceExhausted), at: moment)
      _ = subsystem
      return line.count
    }
    #expect(Set(widths).count == 1)
    #expect(LogEvent.Subsystem.allCases.allSatisfy { $0.rawValue.count <= LogLine.subsystemWidth })
  }

  /// A value is written on one line, so an embedded newline would forge a
  /// record. A fault's reason carries an underlying error's description and can
  /// contain anything.
  @Test("A newline inside a value cannot forge a second line")
  func escaping() {
    let line = LogLine.format(
      .serverFailed(reason: "line one\nline two"), at: moment)
    #expect(line.contains("line one⏎line two"))
    #expect(line.filter(\.isNewline).isEmpty)
  }

  @Test("The header says what the file does not contain")
  func header() {
    let header = LogLine.header(version: "0.1.2", at: moment)
    #expect(header.contains("0.1.2"))
    #expect(header.contains("does not contain pad contents"))
    #expect(header.contains("bearer token"))
  }

  // MARK: - Rotation

  @Test("The log starts over rather than growing without bound")
  func rotation() {
    #expect(LogRotation.decide(currentBytes: 0, incoming: 100, limit: 1_000) == .append)
    #expect(LogRotation.decide(currentBytes: 950, incoming: 100, limit: 1_000) == .restart)
    #expect(LogRotation.decide(currentBytes: 900, incoming: 100, limit: 1_000) == .append)
  }

  // MARK: - Writing

  @Test("Nothing is written until logging is switched on")
  func offByDefault() {
    let path = temporaryPath()
    let log = DebugLog()
    log.record(.serverStopped())

    #expect(log.isEnabled == false)
    #expect(log.destination == nil)
    #expect(FileManager.default.fileExists(atPath: path) == false)
  }

  @Test("Switching it on creates the file and records what follows")
  func writes() throws {
    let path = temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let log = DebugLog()

    #expect(log.enable(atPath: path, version: "0.1.2"))
    log.record(.serverListening(port: 8_899, configured: 8_899))
    log.disable()

    let contents = try String(contentsOfFile: path, encoding: .utf8)
    #expect(contents.contains("# Itchy debug log"))
    #expect(contents.contains("listening · port=8899"))
    #expect(log.destination == nil)
  }

  /// Switching logging on is how somebody starts reproducing a problem, and the
  /// first thing they want is a file whose first line is the start of the
  /// attempt.
  @Test("Switching it on again starts a fresh file")
  func replacesOnEnable() throws {
    let path = temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let log = DebugLog()

    log.enable(atPath: path)
    log.record(.tokenRegenerated())
    log.enable(atPath: path)
    log.disable()

    let contents = try String(contentsOfFile: path, encoding: .utf8)
    #expect(contents.contains("token regenerated") == false)
  }

  @Test("Recording after it is switched off does nothing")
  func silentWhenDisabled() throws {
    let path = temporaryPath()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let log = DebugLog()
    log.enable(atPath: path)
    log.disable()

    log.record(.tokenRegenerated())

    let contents = try String(contentsOfFile: path, encoding: .utf8)
    #expect(contents.contains("token regenerated") == false)
  }

  /// There is nowhere sensible to report "could not write the log" to, and a
  /// logger that interrupts what it observes is worse than no logger.
  @Test("An unwritable path is refused quietly rather than thrown")
  func unwritablePath() {
    let log = DebugLog()
    #expect(log.enable(atPath: "/itchy-cannot-write-here.log") == false)
    #expect(log.isEnabled == false)
    log.record(.serverStopped())
  }

  @Test("The default destination is the one the settings caption names")
  func defaultPath() {
    #expect(DebugLog.defaultPath == "/tmp/itchy.log")
  }

  // MARK: - What it cannot say

  /// The vocabulary is closed: `LogEvent`'s initialiser is private and the
  /// factories are the only way in. That is what makes it impossible for a call
  /// site to log a pad's text, and this checks the factories keep their side of
  /// it — every one is given content-shaped input and none of it comes out.
  @Test("No event carries pad text, however it is called")
  func carriesNoContent() {
    let secret = "SENSITIVE-PAD-TEXT"
    // Every factory that stands anywhere near pad text. Each is handed content
    // where it would take it, and each reports a length instead.
    let events: [LogEvent] = [
      .toolCall(tool: "write_pad", pad: "Notes", outcome: "ok", characters: secret.count),
      .agentWrite(pad: "Notes", destination: "store", characters: secret.count),
      .resourceRead(uri: "itchy://pad/1", outcome: "ok", characters: secret.count),
      .transformApplied("case.upper", scope: "wholePad", characters: secret.count),
    ]
    let lines = events.map { LogLine.format($0, at: moment) }
    #expect(lines.allSatisfy { !$0.contains(secret) })
    #expect(lines.allSatisfy { $0.contains("=\(secret.count)") })
  }

  @Test("A write origin logs who, not what")
  func originDescriptions() {
    #expect(WriteOrigin.user.logDescription == "user")
    #expect(WriteOrigin.mcp(client: "claude").logDescription == "mcp:claude")
    #expect(WriteOrigin.mcp(client: nil).logDescription == "mcp:unnamed")
    #expect(WriteOrigin.transform("flatten").logDescription == "transform:flatten")
  }

  // MARK: - Backups

  /// Every reason there is no backup, told apart. Before this they were four
  /// identical silent returns.
  @Test("Each reason not to archive is named")
  func archiveOutcomes() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(
      ArchivePolicy.due(trigger: .launch, retention: 0, lastArchive: nil, now: now) == .disabled)
    #expect(ArchivePolicy.due(trigger: .launch, retention: 10, lastArchive: nil, now: now) == nil)
    #expect(
      ArchivePolicy.due(trigger: .daily, retention: 10, lastArchive: now, now: now) == .notDue)
    #expect(
      ArchivePolicy.due(
        trigger: .daily, retention: 10, lastArchive: now.addingTimeInterval(-90_000), now: now)
        == nil)
    #expect(
      Set(
        [ArchiveAttempt.taken, .notDue, .disabled, .unchanged, .failed].map(\.logDescription)
      ).count == 5)
  }

  @Test("The Boolean form still agrees with the reasoned one")
  func booleanFormAgrees() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    for trigger in ArchiveTrigger.allCases {
      for retention in [0, 10] {
        for last in [nil, now, now.addingTimeInterval(-90_000)] as [Date?] {
          let reasoned = ArchivePolicy.due(
            trigger: trigger, retention: retention, lastArchive: last, now: now)
          let boolean = ArchivePolicy.shouldArchive(
            trigger: trigger, retention: retention, lastArchive: last, now: now)
          #expect(boolean == (reasoned == nil))
        }
      }
    }
  }
}
