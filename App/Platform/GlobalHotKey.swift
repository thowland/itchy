import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey (D-6, verified by spike S-1 in D-17).
///
/// `RegisterEventHotKey` rather than `NSEvent.addGlobalMonitorForEvents`: the
/// monitor requires the Accessibility permission, which means a system prompt, a
/// trip to System Settings, and a support surface, all to read one key
/// combination. This path needs no permission — confirmed with
/// `AXIsProcessTrusted()` false throughout the spike.
///
/// It is a C API with an untidy callback shape, which is a contained cost paid
/// once, in this file.
@MainActor
final class GlobalHotKey {
  /// Runs on the main actor when the combination is pressed.
  private var handler: (() -> Void)?
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?
  private(set) var binding: HotKeyBinding?

  /// Identifies our hot key among any others in the process.
  private static let signature = OSType(0x4954_4348)  // 'ITCH'

  init() {}

  deinit {
    MainActor.assumeIsolated {
      unregisterHotKey()
      removeEventHandler()
    }
  }

  /// Whether the last registration attempt succeeded.
  private(set) var isRegistered = false

  @discardableResult
  func register(_ binding: HotKeyBinding, handler: @escaping () -> Void) -> Bool {
    unregister()
    guard binding.isValid else { return false }
    self.handler = handler
    self.binding = binding

    installEventHandlerIfNeeded()

    var reference: EventHotKeyRef?
    let identifier = EventHotKeyID(signature: Self.signature, id: 1)
    let status = RegisterEventHotKey(
      binding.keyCode, binding.carbonModifiers, identifier,
      GetEventDispatcherTarget(), 0, &reference)

    isRegistered = status == noErr && reference != nil
    hotKeyRef = reference
    return isRegistered
  }

  func unregister() {
    unregisterHotKey()
    isRegistered = false
  }

  /// Called from the Carbon callback.
  fileprivate func fire() {
    handler?()
  }

  private func installEventHandlerIfNeeded() {
    guard eventHandler == nil else { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetEventDispatcherTarget(), hotKeyCallback, 1, &spec,
      Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
  }

  private func unregisterHotKey() {
    guard let hotKeyRef else { return }
    UnregisterEventHotKey(hotKeyRef)
    self.hotKeyRef = nil
  }

  private func removeEventHandler() {
    guard let eventHandler else { return }
    RemoveEventHandler(eventHandler)
    self.eventHandler = nil
  }
}

/// The Carbon callback. Kept at file scope because it must be a C function
/// pointer, which a method cannot be.
private let hotKeyCallback: EventHandlerUPP = { _, _, userData in
  guard let userData else { return noErr }
  let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
  MainActor.assumeIsolated {
    owner.fire()
  }
  return noErr
}
