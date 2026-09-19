import AppKit
import ItchyCore
import Observation

/// Which formatting traits the selection carries, observed by the controls.
@MainActor
@Observable
final class FormattingState {
  var active: Set<FormatTrait> = []
}

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
  /// What the formatting controls show (D-20).
  let formatting = FormattingState()
  private let store: PadStore
  /// Readable by the transform bridge in a neighbouring file, which needs the
  /// selection and the text storage. Still only settable here.
  private(set) weak var textView: PadTextView?
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
    textView.onFormat = { [weak self] trait in
      self?.toggle(trait)
    }
    refreshFormatting()
  }

  func textDidChange(_ notification: Notification) {
    scheduleStaging()
    refreshFormatting()
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    refreshFormatting()
  }

  /// Bold, italic or underline over the selection, as one undoable step. Does
  /// nothing in a plain pad (`FR-4.4`).
  func toggle(_ trait: FormatTrait) {
    guard let textView, FormattingPlan.availability(for: textView.mode) == .available else {
      return
    }
    TextFormatter.toggle(trait, in: textView, fallbackFont: textView.bodyFont)
    refreshFormatting()
  }

  func refreshFormatting() {
    guard let textView else { return }
    formatting.active = FormattingPlan.active(in: TextFormatter.runs(in: textView))
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
  func stageNow(origin: WriteOrigin = .user) async {
    guard let attributed = textView?.attributedString() else { return }
    guard let content = try? ContentCodec.encode(attributed) else { return }
    await store.stage(content, for: padID, origin: origin)
  }

  /// An agent's write into the open panel (`FR-8.8`, §11.6).
  ///
  /// This is what makes the write one undo from reverted, and it is why the
  /// interim refusal in `OpenPadPolicy` stops applying: the panel holds the
  /// authoritative text, so the write goes *into* the panel rather than past it
  /// into the store, where the panel's next save would overwrite it.
  ///
  /// Staged immediately, and with the agent's origin rather than the user's, so
  /// that the external-write marker records who wrote and the debounced
  /// user-origin staging that `apply` scheduled cannot land first and claim the
  /// write as the person's own.
  ///
  /// Answers false when there is no text view to write into, which is the
  /// caller's signal to use the store instead.
  func applyAgentWrite(_ write: AgentWrite, text: String, origin: WriteOrigin) async -> Bool {
    guard let textView, let storage = textView.textStorage else { return false }
    let replacement = NSAttributedString(
      string: text, attributes: [.font: textView.bodyFont])
    apply(
      replacement,
      over: AgentWritePlan.range(for: write, length: storage.length),
      actionName: AgentWritePlan.actionName(for: write, origin: origin))
    serialisationTask?.cancel()
    await stageNow(origin: origin)
    return true
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
    let whole = NSRange(location: 0, length: textView?.textStorage?.length ?? 0)
    apply(replacement, over: whole, actionName: actionName)
  }

  /// The same grouped step over part of the pad, which is what a transform
  /// applied to a selection needs (`FR-6.4`).
  func apply(_ replacement: NSAttributedString, over range: NSRange, actionName: String) {
    guard let textView, let storage = textView.textStorage else { return }
    // `shouldChangeText` registers the undo and `didChangeText` closes it; this
    // is the pair `insertText` calls internally. Going through them directly
    // rather than through `insertText` matters because `insertText` *merges*
    // attributes into what it replaces rather than replacing them — it keeps
    // the point size, and it keeps an underline entirely — which means a
    // flatten performed through it does not flatten (`FR-4.5`, `FR-6.5`).
    guard textView.shouldChangeText(in: range, replacementString: replacement.string) else {
      return
    }
    textView.undoManager?.beginUndoGrouping()
    storage.replaceCharacters(in: range, with: replacement)
    textView.didChangeText()
    // After the change, not before: the text view names its own registration
    // "Typing", which would otherwise be what the Edit menu shows.
    textView.undoManager?.setActionName(actionName)
    textView.undoManager?.endUndoGrouping()
    textView.typingAttributes = [.font: textView.bodyFont]
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
