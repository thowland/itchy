import AppKit
import ItchyCore

/// The diagnostic log (`/tmp/itchy.log`), and the setting that controls it.
///
/// Off by default. It exists for the work that is hard to see from the outside
/// — an agent write racing a save, a backup that quietly decided not to happen —
/// and it says nothing at all until somebody asks it to.
extension PadCoordinator {
  /// Opens or closes the log to match the setting. Called at launch and
  /// whenever the toggle moves.
  func applyDebugLogging() {
    guard settings.debugLoggingEnabled else {
      DebugLog.shared.disable()
      return
    }
    DebugLog.shared.enable(version: AppVersion.current.display)
  }

  func setDebugLoggingEnabled(_ enabled: Bool) {
    // Recorded before the switch, so that turning it off has a last line
    // saying so rather than simply stopping mid-session.
    DebugLog.shared.record(.terminating(flush: "logging switched off"))
    settings.debugLoggingEnabled = enabled
    persistSettings()
    applyDebugLogging()
  }

  /// Where the log is, if it is anywhere. Shown rather than assumed: a path in
  /// a caption that is not the path in use is worse than no caption.
  var debugLogPath: String? { DebugLog.shared.destination }

  func revealDebugLog() {
    guard let path = debugLogPath else { return }
    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
  }

  /// Faults are worth a line whatever else is happening: they are the events
  /// somebody enables logging in order to catch.
  func recordFault(in change: PadChange) {
    guard case .storeFault(_, let fault) = change else { return }
    DebugLog.shared.record(.storeFault(fault))
  }
}
