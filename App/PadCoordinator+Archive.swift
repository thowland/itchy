import AppKit
import ItchyCore

/// Archiving (D-18).
///
/// Pads are held in a format this application is still changing, and a defect in
/// the storage layer would otherwise be unrecoverable. An archive is taken on
/// launch, on quit, and optionally once a day — but only when the pads have
/// actually changed, because a day of restarts would otherwise fill the
/// retention limit with identical copies and push out the one snapshot that
/// mattered.
extension PadCoordinator {
  var archiveStore: ArchiveStore { ArchiveStore(layout: layout) }

  /// Archives if the policy says to, then prunes. Never throws: failing to take
  /// a backup must not stop the application from starting or quitting.
  ///
  /// Every outcome is recorded, including every reason not to. "My backups
  /// stopped" has three innocent causes and one that is not, and before the log
  /// existed they were four identical silent returns.
  @discardableResult
  func archiveIfNeeded(trigger: ArchiveTrigger, now: Date = Date()) -> ArchiveAttempt {
    let outcome = takeArchive(trigger: trigger, now: now)
    DebugLog.shared.record(
      .archiveAttempt(trigger: String(describing: trigger), outcome: outcome))
    return outcome
  }

  private func takeArchive(trigger: ArchiveTrigger, now: Date) -> ArchiveAttempt {
    let refusal = ArchivePolicy.due(
      trigger: trigger,
      retention: settings.archiveRetention,
      lastArchive: settings.lastArchiveAt,
      now: now)
    if let refusal { return refusal }

    let store = archiveStore
    let fingerprint = store.fingerprint()
    guard ArchivePolicy.hasChanged(since: settings.lastArchiveFingerprint, current: fingerprint)
    else { return .unchanged }

    // `takeArchive` answers nil when there are no pads and throws when the copy
    // failed, and those are different things. Flattening them with `try?` made a
    // fresh install report a failed backup, which the log said out loud on the
    // first run it was switched on for.
    let attempt = Result { try store.takeArchive(now: now) }
    guard case .success(let archive) = attempt else { return .failed }
    guard let taken = archive else { return .nothingToArchive }
    let before = store.archives().count
    store.prune(retention: settings.archiveRetention)
    let after = store.archives().count
    DebugLog.shared.record(
      .archiveTaken(name: taken.id, pads: taken.padCount, retained: after))
    if before > after {
      DebugLog.shared.record(
        .archivesPruned(removed: before - after, retention: settings.archiveRetention))
    }

    settings.lastArchiveAt = now
    settings.lastArchiveFingerprint = fingerprint
    persistSettings()
    return .taken
  }

  var archives: [PadArchive] { archiveStore.archives() }

  var archiveTotalBytes: Int { archiveStore.totalBytes() }

  func setArchiveRetention(_ requested: Int) {
    settings.archiveRetention = ArchiveBounds.clamp(requested)
    persistSettings()
    archiveStore.prune(retention: settings.archiveRetention)
  }

  func setArchivesDaily(_ enabled: Bool) {
    settings.archivesDaily = enabled
    persistSettings()
  }

  /// Removes every archive, for a user who would rather no copies of deleted
  /// pads existed anywhere.
  func removeAllArchives() {
    DebugLog.shared.record(.archivesRemoved(count: archiveStore.archives().count))
    archiveStore.removeAll()
    settings.lastArchiveFingerprint = nil
    settings.lastArchiveAt = nil
    persistSettings()
  }

  func revealArchives() {
    NSWorkspace.shared.activateFileViewerSelecting([archiveStore.directoryForReveal()])
  }
}
