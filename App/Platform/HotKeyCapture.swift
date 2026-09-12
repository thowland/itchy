import Carbon.HIToolbox
import Foundation

/// Turns an observed keypress into a binding, or refuses it.
///
/// Extracted from the recorder so the rules are testable without a window: a
/// recorder that silently accepts a modifier-less combination would register a
/// system-wide hotkey on a bare letter, and the user would discover it by
/// finding that key no longer works anywhere (D-11).
enum HotKeyCapture {
  /// Modifiers that do not, on their own, make a combination safe to take
  /// system-wide.
  static func binding(
    keyCode: UInt32,
    flags: NSEventModifierFlagsProxy
  ) -> HotKeyBinding? {
    let candidate = HotKeyBinding(
      keyCode: keyCode, carbonModifiers: HotKeyBinding.carbonModifiers(from: flags))
    guard candidate.isValid else { return nil }
    guard !isReserved(candidate) else { return nil }
    return candidate
  }

  /// Combinations the system already owns, which registration would fail on
  /// anyway — refused here so the user gets an explanation rather than a
  /// silently ineffective setting.
  static func isReserved(_ binding: HotKeyBinding) -> Bool {
    // ⌘Q, ⌘W, ⌘Tab and Shift alone as the only modifier.
    let shiftOnly = binding.carbonModifiers == UInt32(shiftKey)
    return shiftOnly
  }
}

/// What the recorder button reads. A seam, because choosing the wording is a
/// decision and the recorder is excluded from coverage (D-11).
enum HotKeyRecorderTitle {
  static func text(isRecording: Bool, binding: HotKeyBinding) -> String {
    isRecording ? "Press a combination…" : binding.displayString
  }
}
