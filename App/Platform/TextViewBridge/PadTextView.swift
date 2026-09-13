import AppKit
import ItchyCore

/// The editor.
///
/// A considerable amount of the feature list arrives free with this decision and
/// must not be reimplemented: image paste and drag-and-drop, spell checking, the
/// system find bar, the standard Edit and Format responder chain, and
/// `pasteAsPlainText:` — which satisfies `FR-4.6` with no implementation of ours
/// at all (specification §9.2).
final class PadTextView: NSTextView {
  /// Called with the provenance entry produced by a paste, if any.
  var onPaste: ((ProvenanceEntry) -> Void)?
  /// The pad's mode, which governs what a paste is allowed to carry.
  var mode: PadMode = .styled
  /// The editor font from settings, which typing uses and plain pads are set in
  /// entirely (D-19).
  var bodyFont: NSFont = ContentCodec.defaultFont
  /// Called with a formatting shortcut's trait (D-20).
  var onFormat: ((FormatTrait) -> Void)?
  /// The mode last applied by `configure(for:)`.
  private(set) var configuredMode: PadMode?

  /// Routes every paste through the interceptor, so that provenance capture and
  /// image downsampling have one entry point (specification §9.4).
  override func paste(_ sender: Any?) {
    handleIncoming(NSPasteboard.general)
  }

  override func readSelection(
    from pboard: NSPasteboard,
    type: NSPasteboard.PasteboardType
  ) -> Bool {
    handleIncoming(pboard)
    return true
  }

  /// ⌘B, ⌘I and ⌘U. An accessory application has no Format menu for these to
  /// arrive through, so the text view answers them itself (D-20).
  ///
  /// Answered in `keyDown` as well. In a non-activating panel of an inactive
  /// application the chord is not always offered as a key equivalent, and then
  /// arrives here as an ordinary key press — which is what the UI suite found.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard window?.firstResponder === self, handleFormattingShortcut(event) else {
      return super.performKeyEquivalent(with: event)
    }
    return true
  }

  override func keyDown(with event: NSEvent) {
    guard handleFormattingShortcut(event) else {
      super.keyDown(with: event)
      return
    }
  }

  private func handleFormattingShortcut(_ event: NSEvent) -> Bool {
    guard
      let trait = FormattingPlan.shortcut(
        characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags, mode: mode)
    else { return false }
    onFormat?(trait)
    return true
  }

  /// Reconfigures only when the mode has changed, so that an unrelated SwiftUI
  /// update does not reset the typing attributes (`ModeConfigurationPlan`).
  func configureIfNeeded(for mode: PadMode) {
    switch ModeConfigurationPlan.decide(configured: configuredMode, requested: mode) {
    case .reconfigure: configure(for: mode)
    case .unchanged: break
    }
  }

  private func handleIncoming(_ pasteboard: NSPasteboard) {
    let descriptor = PasteInterceptor.describe(pasteboard)
    let plan = PastePlan.plan(for: descriptor, mode: mode)
    let entry = PasteInterceptor.apply(plan, descriptor: descriptor, from: pasteboard, to: self)
    guard let entry else { return }
    onPaste?(entry)
  }

  /// Applies the configuration a mode implies (`FR-4.4`, specification §9.2).
  ///
  /// The substitution settings are off in plain mode and not configurable: a
  /// plain pad holds a JSON fragment or a SQL clause, and smart quotes silently
  /// corrupting a string literal is the single most annoying thing a scratchpad
  /// can do.
  func configure(for mode: PadMode) {
    self.mode = mode
    configuredMode = mode
    isRichText = mode == .styled
    importsGraphics = mode == .styled
    allowsImageEditing = mode == .styled
    isAutomaticQuoteSubstitutionEnabled = mode == .styled
    isAutomaticDashSubstitutionEnabled = mode == .styled
    isAutomaticTextReplacementEnabled = mode == .styled
    isContinuousSpellCheckingEnabled = true
    isAutomaticSpellingCorrectionEnabled = false
    typingAttributes = [.font: bodyFont]
    allowsUndo = true
  }
}
