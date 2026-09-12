import Carbon.HIToolbox
import Foundation

/// A global key combination, as stored and as displayed.
///
/// Carbon modifier masks rather than `NSEvent.ModifierFlags`, because
/// `RegisterEventHotKey` takes Carbon's (D-6). Converting once here keeps the
/// rest of the application in one vocabulary.
struct HotKeyBinding: Equatable, Sendable, Codable {
  var keyCode: UInt32
  var carbonModifiers: UInt32

  /// ⌃⌥Space, the default in specification §8.6.
  static let `default` = HotKeyBinding(
    keyCode: UInt32(kVK_Space),
    carbonModifiers: UInt32(controlKey | optionKey))

  /// A binding with no modifiers would capture an ordinary key system-wide,
  /// which is never what the user meant.
  var isValid: Bool {
    carbonModifiers != 0
  }

  var displayString: String {
    modifierSymbols + HotKeyBinding.keyName(for: keyCode)
  }

  private var modifierSymbols: String {
    var symbols = ""
    if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
    if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
    if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
    if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
    return symbols
  }

  /// Carbon masks from the modifier flags an `NSEvent` carries.
  static func carbonModifiers(from flags: NSEventModifierFlagsProxy) -> UInt32 {
    var result: UInt32 = 0
    if flags.control { result |= UInt32(controlKey) }
    if flags.option { result |= UInt32(optionKey) }
    if flags.shift { result |= UInt32(shiftKey) }
    if flags.command { result |= UInt32(cmdKey) }
    return result
  }

  /// How a key reads in the settings window.
  static func keyName(for keyCode: UInt32) -> String {
    namedKeys[Int(keyCode)] ?? printableName(for: keyCode)
  }

  /// Keys with no printable character, and punctuation worth spelling out.
  private static let namedKeys: [Int: String] = [
    kVK_Space: "Space",
    kVK_Return: "↩",
    kVK_Tab: "⇥",
    kVK_Escape: "⎋",
    kVK_ANSI_Slash: "/",
    kVK_ANSI_Period: ".",
    kVK_ANSI_Comma: ",",
    kVK_ANSI_Backslash: "\\",
  ]

  private static func printableName(for keyCode: UInt32) -> String {
    let letters: [Int: String] = [
      kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
      kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
      kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
      kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
      kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
      kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
      kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
    ]
    return letters[Int(keyCode)] ?? "Key \(keyCode)"
  }
}

/// The modifier state a recorder observed, without dragging AppKit into the
/// value type.
struct NSEventModifierFlagsProxy: Equatable, Sendable {
  var control = false
  var option = false
  var shift = false
  var command = false
}
