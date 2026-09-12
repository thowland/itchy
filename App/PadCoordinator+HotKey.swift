import AppKit
import ItchyCore
import SwiftUI

/// The global hotkey and the login item (`FR-1.3`, `FR-1.4`).
///
/// Split from `PadCoordinator` because the type outgrew its body limit, which is
/// the limit doing its job: these are a distinct responsibility from mirroring
/// store state onto the main actor.
extension PadCoordinator {

  var hotKeyBinding: HotKeyBinding {
    HotKeyBinding(keyCode: settings.hotKeyCode, carbonModifiers: settings.hotKeyModifiers)
  }

  var isHotKeyRegistered: Bool { hotKey.isRegistered }

  func setHotKeyBinding(_ binding: HotKeyBinding) {
    guard binding.isValid else { return }
    settings.hotKeyCode = binding.keyCode
    settings.hotKeyModifiers = binding.carbonModifiers
    persistSettings()
    registerHotKey()
  }

  internal func registerHotKey() {
    hotKey.register(hotKeyBinding) { [weak self] in
      self?.handleHotKey()
    }
  }

  /// `FR-1.4`. The decision is `HotKeyAction`'s; this only carries it out.
  func handleHotKey() {
    let action = HotKeyAction.decide(
      pads: pads,
      lastOpened: lastOpenedPad,
      frontmostKeyPad: registry.frontmostKeyPad())
    perform(action)
  }

  func perform(_ action: HotKeyAction) {
    switch action {
    case .close(let padID):
      registry.close(padID)
    case .open(let padID):
      let signpost = signposter.beginHotKey()
      open(padID)
      signposter.endHotKey(signpost)
    case .createAndOpen:
      createPad()
    }
  }

  func setLaunchesAtLogin(_ enabled: Bool) {
    settings.launchesAtLogin = LoginItem.reconcile(storedPreference: enabled)
    persistSettings()
  }

  /// Brings the stored preference and the real login-item state back into
  /// agreement at launch.
  ///
  /// Registration can fail — an application running from a build directory, or
  /// one the user has removed the login item for by hand — and when it does the
  /// setting must follow reality rather than keep claiming otherwise. The
  /// corrected value is persisted, but only when it actually changed, so an
  /// ordinary launch writes nothing.
  internal func reconcileLoginItem() {
    let reconciled = LoginItem.reconcile(storedPreference: settings.launchesAtLogin)
    guard reconciled != settings.launchesAtLogin else { return }
    settings.launchesAtLogin = reconciled
    persistSettings()
  }
}
