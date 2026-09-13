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
  func archiveIfNeeded(trigger: ArchiveTrigger, now: Date = Date()) {
    guard
      ArchivePolicy.shouldArchive(
        trigger: trigger,
        retention: settings.archiveRetention,
        lastArchive: settings.lastArchiveAt,
        now: now)
    else { return }

    let store = archiveStore
    let fingerprint = store.fingerprint()
    guard ArchivePolicy.hasChanged(since: settings.lastArchiveFingerprint, current: fingerprint)
    else { return }

    guard let taken = try? store.takeArchive(now: now), taken != nil else { return }
    store.prune(retention: settings.archiveRetention)

    settings.lastArchiveAt = now
    settings.lastArchiveFingerprint = fingerprint
    persistSettings()
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
    archiveStore.removeAll()
    settings.lastArchiveFingerprint = nil
    settings.lastArchiveAt = nil
    persistSettings()
  }

  func revealArchives() {
    NSWorkspace.shared.activateFileViewerSelecting([archiveStore.directoryForReveal()])
  }
}
