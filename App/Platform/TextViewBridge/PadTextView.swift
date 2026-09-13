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
