import Foundation

/// Whether Itchy should register itself to start at login (`FR-1.3`).
///
/// Registering at first launch from wherever the binary happens to sit is
/// presumptuous and, worse, durable: a login item created from a build directory
/// keeps pointing at that directory after the build is deleted, and the user
/// finds it in System Settings with no idea what put it there. It is a real
/// footgun — this was written after doing it to the development machine.
///
/// So automatic registration is limited to an installed copy. A copy run from
/// anywhere else honours the setting when the user changes it by hand, and does
/// nothing on its own.
enum LoginItemPolicy {
  /// Directories an installed copy lives in.
  static let installedPrefixes = ["/Applications/", "/System/Applications/"]

  static func isInstalled(bundlePath: String) -> Bool {
    installedPrefixes.contains { bundlePath.hasPrefix($0) }
  }

  /// Whether launch-time reconciliation may register the login item.
  ///
  /// Unregistering is always permitted: correcting a stale item is never
  /// presumptuous.
  static func mayRegisterAutomatically(bundlePath: String) -> Bool {
    isInstalled(bundlePath: bundlePath)
  }
}
