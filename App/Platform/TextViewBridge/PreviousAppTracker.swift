import AppKit

/// Remembers the last application that was frontmost before Itchy.
///
/// The subtlety in `FR-7.1` is that by the time a paste is being handled, Itchy
/// may already be frontmost, at which point `frontmostApplication` is Itchy and
/// the record is useless. So the previous frontmost application is maintained
/// continuously rather than queried on demand (specification §9.5).
///
/// Because pad panels are non-activating, the common case is that Itchy never
/// became frontmost at all and the direct query would have worked — but the case
/// where the user clicks into the panel first is exactly the case where they are
/// about to paste.
@MainActor
final class PreviousAppTracker {
  private(set) var previous: NSRunningApplication?
  private var observer: (any NSObjectProtocol)?

  static let shared = PreviousAppTracker()

  func start(centre: NotificationCenter = NSWorkspace.shared.notificationCenter) {
    guard observer == nil else { return }
    previous = NSWorkspace.shared.frontmostApplication.flatMap(Self.excludingItchy)
    observer = centre.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil, queue: .main
    ) { [weak self] notification in
      // The activated application is extracted here rather than passing the
      // notification across the isolation boundary, which the compiler refuses
      // under strict concurrency (D-1) because Notification is not Sendable.
      let key = NSWorkspace.applicationUserInfoKey
      let activated = notification.userInfo?[key] as? NSRunningApplication
      MainActor.assumeIsolated {
        self?.record(activated)
      }
    }
  }

  /// Itchy activating is not a source; anything else replaces the record.
  func record(_ application: NSRunningApplication?) {
    guard let application = application.flatMap(Self.excludingItchy) else { return }
    previous = application
  }

  private static func excludingItchy(_ application: NSRunningApplication) -> NSRunningApplication? {
    application.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : application
  }
}
