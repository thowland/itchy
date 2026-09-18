import AppKit
import Foundation
import ItchyCore
import ItchyServices
import Testing

@testable import Itchy

/// The decisions the transform path makes on the application side (D-11).
/// The transforms themselves are tested in `ItchyServicesTests`.
@Suite("Transform seams")
struct TransformSeamTests {
  @Test("A non-empty selection is the scope; otherwise the whole pad (FR-6.4)")
  func scope() {
    #expect(TransformScope.scope(forSelectionLength: 0, at: 4) == .wholePad)
    #expect(TransformScope.scope(forSelectionLength: 3, at: 4) == .selection(4..<7))
  }

  @Test("A scope resolves to the range it will be written back over")
  func ranges() {
    #expect(TransformScope.range(of: .wholePad, wholeLength: 9) == NSRange(location: 0, length: 9))
    #expect(
      TransformScope.range(of: .selection(2..<5), wholeLength: 9) == NSRange(location: 2, length: 3))
  }

  /// Flatten exists to discard styling, so it may not inherit any; a plain pad
  /// has none to inherit in the first place.
  @Test(
    "Styling of the replacement",
    arguments: [
      ("flatten", PadMode.styled, TransformStylePlan.Style.bodyFontOnly),
      ("case.upper", .styled, .inheritFromRangeStart),
      ("case.upper", .plain, .bodyFontOnly),
      ("flatten", .plain, .bodyFontOnly),
    ])
  func stylePlan(id: String, mode: PadMode, expected: TransformStylePlan.Style) {
    #expect(TransformStylePlan.style(forTransform: id, mode: mode) == expected)
  }

  @Test("Rows carry the refusal, so the menu can say why (FR-6.3)")
  func rows() {
    let groups = TransformMenuModel.rows(for: TransformInput(plainText: "plain text"))
    let flat = groups.flatMap { $0 }
    #expect(flat.count == TransformRegistry.all.count)
    let decode = flat.first { $0.id == "base64.decode" }
    #expect(decode?.isEnabled == false)
    #expect(decode?.reason?.isEmpty == false)
    let upper = flat.first { $0.id == "case.upper" }
    #expect(upper?.isEnabled == true)
    #expect(upper?.reason == nil)
  }

  @Test("The menu is disabled only when nothing at all applies")
  func menuEnablement() {
    #expect(TransformMenuModel.isEnabled(for: TransformMenuModel.rows(for: TransformInput(plainText: "text"))))
    #expect(!TransformMenuModel.isEnabled(for: TransformMenuModel.rows(for: TransformInput(plainText: ""))))
  }

  @Test("A notice names the transform that produced it")
  func noticeMessage() {
    let message = TransformNotice.message(for: JSONPrettyTransform(), reason: "This text is not JSON.")
    #expect(message == "Pretty-print JSON: This text is not JSON.")
  }

  @Test("A notice takes its own segment, last, and reads in red")
  func noticeSegment() {
    let pad = PadMetadata(name: "Pad", created: .now, modified: .now)
    let segments = StatusBarModel.segments(for: pad, notice: "Sort Lines: Sorting needs at least two lines.")
    #expect(segments.last?.kind == .notice)
    #expect(StatusBarModel.segments(for: pad).contains { $0.kind == .notice } == false)
  }
}

/// The path a transform actually takes through a pad (§7.3), exercised against
/// a real `PadTextView` so that the undo and selection criteria are
/// demonstrated rather than asserted about a model.
@MainActor
@Suite("Transform application")
final class TransformApplicationTests {
  /// Held for the lifetime of the test so the text views keep their undo
  /// managers; never ordered on screen.
  private var windows: [NSWindow] = []

  private func makePad(_ text: String, mode: PadMode = .plain, selecting range: NSRange? = nil)
    -> (PadCoordinator, PadTextCoordinator, PadTextView, PadID, URL)
  {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-transform-\(UUID().uuidString)")
    let layout = PadStorageLayout(root: root)
    let store = PadStore(layout: layout)
    let coordinator = PadCoordinator(store: store, layout: layout, launchOptions: LaunchOptions())
    let padID = PadID()
    let editor = PadTextCoordinator(padID: padID, store: store)
    let textView = PadTextView()
    // `NSTextView.undoManager` is the window's, so a view with no window has
    // none and every undo call quietly does nothing. The window is never shown.
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
      styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = textView
    textView.allowsUndo = true
    textView.configure(for: mode)
    textView.textStorage?.setAttributedString(
      NSAttributedString(string: text, attributes: [.font: ContentCodec.defaultFont]))
    editor.attach(textView)
    textView.setSelectedRange(range ?? NSRange(location: 0, length: 0))
    coordinator.editors[padID] = editor
    windows.append(window)
    return (coordinator, editor, textView, padID, root)
  }

  @Test("With no selection, the whole pad is the input")
  func wholePadInput() {
    let (_, editor, _, _, root) = makePad("hello")
    defer { try? FileManager.default.removeItem(at: root) }
    let input = editor.transformInput()
    #expect(input?.plainText == "hello")
    #expect(input?.scope == .wholePad)
  }

  @Test("With a selection, only the selected text is the input")
  func selectionInput() {
    let (_, editor, _, _, root) = makePad("hello world", selecting: NSRange(location: 6, length: 5))
    defer { try? FileManager.default.removeItem(at: root) }
    let input = editor.transformInput()
    #expect(input?.plainText == "world")
    #expect(input?.scope == .selection(6..<11))
  }

  /// `FR-6.4`'s acceptance criterion, in the words it is written in.
  @Test("Pretty-printing a selected fragment leaves the surrounding text untouched")
  func selectionScopedApply() async {
    let text = #"before {"b":2,"a":1} after"#
    let (coordinator, _, textView, padID, root) = makePad(
      text, selecting: NSRange(location: 7, length: 13))
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.applyTransform(id: "json.pretty", to: padID)
    await expect("the selected fragment to be pretty-printed") { textView.string.contains("\"b\": 2") }

    #expect(textView.string.hasPrefix("before {\n"))
    #expect(textView.string.hasSuffix(" after"))
    #expect(textView.string.contains("\"b\": 2"))
  }

  /// `FR-6.5`'s acceptance criterion: one undo, content restored exactly.
  @Test("One undo after a transform restores the prior content exactly")
  func singleStepUndo() async {
    let (coordinator, _, textView, padID, root) = makePad("banana\nApple\ncherry")
    defer { try? FileManager.default.removeItem(at: root) }
    let before = textView.string

    coordinator.applyTransform(id: "lines.sort", to: padID)
    await expect("the lines to be sorted") { textView.string == "Apple\nbanana\ncherry" }

    textView.undoManager?.undo()
    #expect(textView.string == before)
  }

  @Test("The undo step is named after the transform, so the Edit menu reads well")
  func undoActionName() async {
    let (coordinator, _, textView, padID, root) = makePad("hello")
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.applyTransform(id: "case.upper", to: padID)
    await expect("the text to be upper-cased") { textView.string == "HELLO" }

    #expect(textView.undoManager?.undoActionName == "Upper Case")
  }

  /// `FR-6.6`'s acceptance criterion: content byte-identical, and a message.
  @Test("A refused transform leaves the pad byte-identical and says why")
  func refusalLeavesPadAlone() async {
    let (coordinator, _, textView, padID, root) = makePad("not json at all")
    defer { try? FileManager.default.removeItem(at: root) }
    let before = textView.string

    // Large enough that the predicate stops parsing and lets it through to
    // apply, which is the only way to reach a failure from the menu path.
    let large = String(repeating: "x", count: JSONPredicate.parseCap + 1)
    textView.textStorage?.setAttributedString(
      NSAttributedString(string: large, attributes: [.font: ContentCodec.defaultFont]))
    coordinator.applyTransform(id: "json.pretty", to: padID)
    await expect("the failure to be reported") { coordinator.notices[padID] != nil }

    #expect(textView.string == large)
    #expect(coordinator.notices[padID]?.contains("Pretty-print JSON") == true)

    // And a transform that is simply not applicable never runs at all.
    textView.textStorage?.setAttributedString(
      NSAttributedString(string: before, attributes: [.font: ContentCodec.defaultFont]))
    coordinator.applyTransform(id: "base64.decode", to: padID)
    await expect("the refusal to be reported") {
      coordinator.notices[padID]?.contains("Decode Base64") == true
    }
    #expect(textView.string == before)
  }

  @Test("A transform that succeeds clears a notice left by an earlier failure")
  func successClearsNotice() async {
    let (coordinator, _, _, padID, root) = makePad("hello")
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.showNotice("stale", for: padID)
    coordinator.applyTransform(id: "case.upper", to: padID)
    await expect("the stale notice to be cleared") { coordinator.notices[padID] == nil }
  }

  @Test("Flatten drops styling but keeps the characters")
  func flatten() async {
    let (coordinator, _, textView, padID, root) = makePad("styled", mode: .styled)
    defer { try? FileManager.default.removeItem(at: root) }
    textView.textStorage?.setAttributedString(
      NSAttributedString(
        string: "styled",
        attributes: [.font: ContentCodec.defaultFont, .underlineStyle: 1]))

    coordinator.applyTransform(id: "flatten", to: padID)
    await expect("the styling to be dropped") {
      textView.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil
    }

    #expect(textView.string == "styled")

    #expect(textView.string == "styled")
  }

}
