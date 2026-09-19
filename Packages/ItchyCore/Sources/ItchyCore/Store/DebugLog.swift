import Foundation

/// Writes the debug log, when there is one.
///
/// Lives under `Store/` because it touches disk and `CON-4` puts every disk
/// access in one place. It is not part of the pad store and does not go through
/// the atomic write: a log line that is lost because the machine died is a log
/// line nobody needed, and an append that is durable is worth more here than an
/// append that is atomic.
///
/// A shared instance, which is the one place in this codebase that is defensible
/// — a logger threaded through every initialiser is a logger that stops being
/// added to, and the call sites are in an actor, on the main actor, and in
/// neither. It is still constructible directly, which is how the suite tests it
/// without touching the shared one.
///
/// Synchronous rather than an actor, on purpose. `record` on a disabled log is a
/// lock, a boolean and a return, so a call site on the typing path costs nothing
/// and needs no `await` — and an `await` on a logger is how logging changes the
/// ordering of the thing it was meant to observe.
public final class DebugLog: @unchecked Sendable {
  /// `/tmp`, because the person has to be able to find it and send it, and
  /// because it is swept by the system rather than accumulating in their
  /// Library forever.
  public static let defaultPath = "/tmp/itchy.log"

  public static let shared = DebugLog()

  private let lock = NSLock()
  private let now: @Sendable () -> Date
  private var handle: FileHandle?
  private var path: String?
  private var writtenBytes = 0

  public init(now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
  }

  /// Where the log is being written, or nil when logging is off. Shown in
  /// settings so that the person can find the file without being told a path
  /// that might not be the one in use.
  public var destination: String? {
    lock.lock()
    defer { lock.unlock() }
    return path
  }

  public var isEnabled: Bool { destination != nil }

  /// Opens the log, replacing anything already at that path.
  ///
  /// Replacing rather than appending: switching logging on is how somebody
  /// starts reproducing a problem, and the first thing they want is a file
  /// whose first line is the start of the attempt.
  @discardableResult
  public func enable(atPath path: String = DebugLog.defaultPath, version: String = "unknown") -> Bool {
    lock.lock()
    defer { lock.unlock() }
    closeLocked()
    guard let handle = Self.open(atPath: path) else { return false }
    self.handle = handle
    self.path = path
    writtenBytes = 0
    writeLocked(LogLine.header(version: version, at: now()))
    return true
  }

  public func disable() {
    lock.lock()
    defer { lock.unlock() }
    closeLocked()
  }

  /// Records an event, or does nothing at all.
  ///
  /// Never throws and never reports a failure. A logger that interrupts the
  /// thing it is observing is worse than no logger, and there is nowhere
  /// sensible to report "could not write the log" to anyway.
  public func record(_ event: LogEvent) {
    lock.lock()
    defer { lock.unlock() }
    guard handle != nil else { return }
    writeLocked(LogLine.format(event, at: now()))
  }

  // MARK: - Under the lock

  private func writeLocked(_ line: String) {
    guard let handle else { return }
    let data = Data((line + "\n").utf8)
    if LogRotation.decide(currentBytes: writtenBytes, incoming: data.count) == .restart {
      try? handle.truncate(atOffset: 0)
      writtenBytes = 0
    }
    try? handle.write(contentsOf: data)
    writtenBytes += data.count
  }

  private func closeLocked() {
    try? handle?.close()
    handle = nil
    path = nil
    writtenBytes = 0
  }

  private static func open(atPath path: String) -> FileHandle? {
    let manager = FileManager.default
    let url = URL(fileURLWithPath: path)
    try? manager.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard manager.createFile(atPath: path, contents: nil) else { return nil }
    return try? FileHandle(forWritingTo: url)
  }
}
