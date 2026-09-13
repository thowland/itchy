import AppKit
import ItchyCore

/// Bridges the text view's edits to the store.
///
/// Two debounces, which sounds like one too many. The first protects `NFR-1.2`
/// (typing latency in a large pad) by not serialising to RTFD on every
/// keystroke; the second is the store's own write debounce. Collapsing them
/// would mean either serialising on every keystroke or leaving the store up to
/// 750 ms stale, the latter of which weakens the crash guarantee in `NFR-2.1`
/// (specification §9.3).
@MainActor
final class PadTextCoordinator: NSObject, NSTextViewDelegate {
  /// How long typing must pause before the text is serialised to RTFD.
  static let serialisationDebounce: Duration = .milliseconds(120)

  let padID: PadID
  private let store: PadStore
  private weak var textView: PadTextView?
  private var serialisationTask: Task<Void, Never>?

  init(padID: PadID, store: PadStore) {
    self.padID = padID
    self.store = store
  }

  func attach(_ textView: PadTextView) {
    self.textView = textView
    textView.delegate = self
    textView.onPaste = { [weak self] entry in
      self?.recordProvenance(entry)
    }
  }

  func textDidChange(_ notification: Notification) {
    scheduleStaging()
  }

  /// Serialises and stages, debounced.
  func scheduleStaging() {
    serialisationTask?.cancel()
    serialisationTask = Task { [weak self] in
      try? await Task.sleep(for: Self.serialisationDebounce)
      guard !Task.isCancelled else { return }
      await self?.stageNow()
    }
  }

  /// Serialises immediately. Used on close and on mode changes, where waiting
  /// for a debounce would mean losing the edit.
  func stageNow() async {
    guard let attributed = textView?.attributedString() else { return }
    guard let content = try? ContentCodec.encode(attributed) else { return }
    await store.stage(content, for: padID, origin: .user)
  }

  func flush() async {
    serialisationTask?.cancel()
    await stageNow()
    try? await store.flush(padID)
  }

  private func recordProvenance(_ entry: ProvenanceEntry) {
    let store = store
    let padID = padID
    Task { await store.appendProvenance(entry, to: padID) }
  }

  /// Applies an operation to the text view as one undoable step.
  ///
  /// The path a transform takes in Sprint 6 and an agent write takes in Sprint 9
  /// (D-9, specification §7.3 step 4). Registered with the window registry so
  /// that a service can reach it without knowing the view exists.
  func apply(_ replacement: NSAttributedString, actionName: String) {
    guard let textView else { return }
    let whole = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
    textView.undoManager?.beginUndoGrouping()
    textView.undoManager?.setActionName(actionName)
    textView.insertText(replacement, replacementRange: whole)
    textView.undoManager?.endUndoGrouping()
    scheduleStaging()
  }

  /// `FR-4.5`: switching from styled to plain flattens in place, as one
  /// undoable operation.
  func flatten() {
    guard let textView else { return }
    let flattened = ContentCodec.flatten(textView.attributedString(), font: textView.bodyFont)
    apply(flattened, actionName: "Flatten Styling")
  }

  func setMode(_ mode: PadMode) {
    textView?.configure(for: mode)
  }

  /// Sets the pad's text in a new editor font, in place (D-19). The runs it
  /// touches are `EditorFontPolicy`'s decision.
  func applyBodyFont(_ font: NSFont, bodyFamilies: Set<String>) {
    guard let textView, let storage = textView.textStorage else { return }
    BodyFont.restyle(storage, to: font, mode: textView.mode, bodyFamilies: bodyFamilies)
    textView.bodyFont = font
    textView.configure(for: textView.mode)
  }
}
