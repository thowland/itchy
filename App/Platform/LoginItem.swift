import Foundation
import ServiceManagement

/// Start at login (`FR-1.3`).
///
/// Defaults to on, because an application reached in the first two seconds of
/// need cannot be one the user has to start first.
@MainActor
enum LoginItem {
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  /// Registers or unregisters, reporting whether it took effect.
  ///
  /// Failure is not fatal and not worth an alert: the user can start Itchy by
  /// hand, and the setting reflecting reality matters more than the setting
  /// being obeyed.
  @discardableResult
  static func setEnabled(_ enabled: Bool) -> Bool {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      return true
    } catch {
      return false
    }
  }

  /// What the settings control should show, which is the real state rather than
  /// the stored preference.
  ///
  /// `mayRegister` gates *registration* only. A development build reconciling on
  /// launch would otherwise create a login item pointing at a build directory,
  /// which outlives the build and is baffling to find later
  /// (`LoginItemPolicy`).
  static func reconcile(
    storedPreference: Bool,
    mayRegister: Bool = LoginItemPolicy.mayRegisterAutomatically(
      bundlePath: Bundle.main.bundlePath)
  ) -> Bool {
    guard storedPreference != isEnabled else { return storedPreference }
    guard storedPreference else {
      setEnabled(false)
      return isEnabled
    }
    guard mayRegister else { return isEnabled }
    setEnabled(true)
    return isEnabled
  }
}
