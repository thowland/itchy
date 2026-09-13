import AppKit
import Foundation
import ItchyCore
import Testing

@testable import Itchy

/// D-20, `FR-4.11`: the decisions behind bold, italic and underline.
@Suite("Formatting plan")
struct FormattingPlanTests {
  @Test("A trait reads as on only when every run has it")
  func active() {
    let bold = RunFormat(isBold: true)
    let boldItalic = RunFormat(isBold: true, isItalic: true)
    #expect(FormattingPlan.active(in: []).isEmpty)
    #expect(FormattingPlan.active(in: [bold, boldItalic]) == [.bold])
    #expect(FormattingPlan.active(in: [boldItalic, boldItalic]) == [.bold, .italic])
    #expect(FormattingPlan.active(in: [RunFormat(), bold]).isEmpty)
  }

  @Test("Toggling removes what every run has, and applies what any run lacks")
  func change() {
    let underlined = RunFormat(isUnderlined: true)
    #expect(FormattingPlan.change(toggling: .underline, runs: [underlined]) == .remove)
    #expect(FormattingPlan.change(toggling: .underline, runs: [underlined, RunFormat()]) == .apply)
    #expect(FormattingPlan.change(toggling: .bold, runs: [underlined]) == .apply)
  }

  @Test("Plain pads offer no formatting (FR-4.4)")
  func availability() {
    #expect(FormattingPlan.availability(for: .styled) == .available)
    #expect(FormattingPlan.availability(for: .plain) == .unavailable)
  }

  @Test("⌘B, ⌘I and ⌘U map to their traits, whatever the case of the character")
  func shortcuts() {
    #expect(FormattingPlan.shortcut(characters: "b", modifiers: .command, mode: .styled) == .bold)
    #expect(FormattingPlan.shortcut(characters: "I", modifiers: .command, mode: .styled) == .italic)
    #expect(
      FormattingPlan.shortcut(characters: "u", modifiers: .command, mode: .styled) == .underline)
  }

  @Test("Caps Lock does not stop a shortcut; a further modifier does")
  func modifiers() {
    #expect(
      FormattingPlan.shortcut(characters: "b", modifiers: [.command, .capsLock], mode: .styled)
        == .bold)
    #expect(
      FormattingPlan.shortcut(characters: "u", modifiers: [.command, .shift], mode: .styled) == nil)
    #expect(FormattingPlan.shortcut(characters: "b", modifiers: .option, mode: .styled) == nil)
  }

  @Test("Shortcuts do nothing in a plain pad, or for other keys")
  func notShortcuts() {
    #expect(FormattingPlan.shortcut(characters: "b", modifiers: .command, mode: .plain) == nil)
    #expect(FormattingPlan.shortcut(characters: "x", modifiers: .command, mode: .styled) == nil)
    #expect(FormattingPlan.shortcut(characters: nil, modifiers: .command, mode: .styled) == nil)
  }

  /// SwiftUI updates the editor on every pad-list refresh, and reconfiguring each
  /// time reset the typing attributes.
  @Test("The text view is reconfigured only when the mode changes")
  func modeConfiguration() {
    #expect(ModeConfigurationPlan.decide(configured: nil, requested: .styled) == .reconfigure)
    #expect(ModeConfigurationPlan.decide(configured: .styled, requested: .plain) == .reconfigure)
    #expect(ModeConfigurationPlan.decide(configured: .styled, requested: .styled) == .unchanged)
  }

  @Test("The controls collapse in a plain pad")
  func visibility() {
    #expect(FormattingBarModel.visibility(for: .styled) == .shown)
    #expect(FormattingBarModel.visibility(for: .plain) == .collapsed)
    #expect(FormattingBarModel.Visibility.collapsed.width == 0)
    #expect(FormattingBarModel.Visibility.shown.width == nil)
    #expect(FormattingBarModel.help(for: .bold).contains("⌘B"))
  }
}

@MainActor
@Suite("Text formatter")
struct TextFormatterTests {
  private func textView(_ string: String, selecting range: NSRange) -> PadTextView {
    let view = PadTextView()
    view.configure(for: .styled)
    view.textStorage?.setAttributedString(
      NSAttributedString(string: string, attributes: [.font: ContentCodec.defaultFont]))
    view.setSelectedRange(range)
    return view
  }

  private func format(_ view: NSTextView, at index: Int) -> RunFormat {
    TextFormatter.format(
      of: view.textStorage?.attributes(at: index, effectiveRange: nil) ?? [:])
  }

  @Test("Bold applies to the selection, and a second toggle takes it off")
  func bold() {
    let view = textView("hello", selecting: NSRange(location: 0, length: 5))

    TextFormatter.toggle(.bold, in: view, fallbackFont: view.bodyFont)
    #expect(format(view, at: 0).isBold)
    #expect(format(view, at: 4).isBold)

    TextFormatter.toggle(.bold, in: view, fallbackFont: view.bodyFont)
    #expect(!format(view, at: 0).isBold)
  }

  /// The built-in font is what most pads are set in, so italic has to work in
  /// it rather than only in a font chosen for the test.
  @Test("Italic works in the built-in font")
  func italic() {
    let view = textView("hello", selecting: NSRange(location: 0, length: 5))
    TextFormatter.toggle(.italic, in: view, fallbackFont: view.bodyFont)
    #expect(format(view, at: 0).isItalic)
  }

  @Test("Underline touches only the selection")
  func underline() {
    let view = textView("hello world", selecting: NSRange(location: 0, length: 5))
    TextFormatter.toggle(.underline, in: view, fallbackFont: view.bodyFont)
    #expect(format(view, at: 0).isUnderlined)
    #expect(!format(view, at: 6).isUnderlined)
  }

  @Test("A partly bold selection is made wholly bold")
  func mixed() {
    let view = textView("hello", selecting: NSRange(location: 0, length: 2))
    TextFormatter.toggle(.bold, in: view, fallbackFont: view.bodyFont)
    view.setSelectedRange(NSRange(location: 0, length: 5))

    TextFormatter.toggle(.bold, in: view, fallbackFont: view.bodyFont)

    #expect((0..<5).allSatisfy { format(view, at: $0).isBold })
  }

  @Test("With nothing selected, the toggle applies to what is typed next")
  func typingAttributes() {
    let view = textView("hello", selecting: NSRange(location: 5, length: 0))

    TextFormatter.toggle(.bold, in: view, fallbackFont: view.bodyFont)

    #expect(TextFormatter.format(of: view.typingAttributes).isBold)
    #expect(!format(view, at: 0).isBold, "existing text is untouched")
  }

  @Test("A toggle over a selection is one undo step, named for the trait")
  func undo() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
      backing: .buffered, defer: true)
    let view = textView("hello", selecting: NSRange(location: 0, length: 5))
    view.allowsUndo = true
    window.contentView = view
    let undoManager = try #require(view.undoManager)
    undoManager.groupsByEvent = false

    undoManager.beginUndoGrouping()
    TextFormatter.toggle(.bold, in: view, fallbackFont: view.bodyFont)
    undoManager.endUndoGrouping()

    #expect(undoManager.canUndo)
    #expect(undoManager.undoActionName == "Bold")
    undoManager.undo()
    #expect(!format(view, at: 0).isBold)
  }
}

@MainActor
@Suite("Formatting through the pad")
struct FormattingIntegrationTests {
  private func attached(_ string: String, mode: PadMode = .styled) -> (
    PadTextCoordinator, PadTextView
  ) {
    let store = PadStore(
      layout: PadStorageLayout(
        root: URL.temporaryDirectory.appendingPathComponent("itchy-format-\(UUID().uuidString)")))
    let editor = PadTextCoordinator(padID: PadID(), store: store)
    let view = PadTextView()
    view.configure(for: mode)
    view.textStorage?.setAttributedString(
      NSAttributedString(string: string, attributes: [.font: ContentCodec.defaultFont]))
    editor.attach(view)
    return (editor, view)
  }

  @Test("The controls follow the selection")
  func followsSelection() {
    let (editor, view) = attached("hello")
    view.setSelectedRange(NSRange(location: 0, length: 2))
    editor.toggle(.bold)
    #expect(editor.formatting.active == [.bold])

    view.setSelectedRange(NSRange(location: 2, length: 3))
    editor.refreshFormatting()

    #expect(editor.formatting.active.isEmpty)
  }

  @Test("Toggling in a plain pad does nothing (FR-4.4)")
  func plain() {
    let (editor, view) = attached("hello", mode: .plain)
    view.setSelectedRange(NSRange(location: 0, length: 5))

    editor.toggle(.bold)

    let font = view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font == ContentCodec.defaultFont)
  }

  @Test("⌘B in the focused pad toggles bold")
  func shortcut() throws {
    let (_, view) = attached("hello")
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled],
      backing: .buffered, defer: true)
    window.contentView = view
    window.makeFirstResponder(view)
    view.setSelectedRange(NSRange(location: 0, length: 5))
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "b",
        charactersIgnoringModifiers: "b", isARepeat: false, keyCode: 11))

    #expect(view.performKeyEquivalent(with: event))

    let font = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
  }

  /// The UI suite found that in a live non-activating panel the chord can
  /// arrive as an ordinary key press rather than as a key equivalent.
  @Test("⌘B arriving as a key press still toggles bold")
  func shortcutAsKeyDown() throws {
    let (_, view) = attached("hello")
    view.setSelectedRange(NSRange(location: 0, length: 5))
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: 0, context: nil, characters: "b", charactersIgnoringModifiers: "b",
        isARepeat: false, keyCode: 11))

    view.keyDown(with: event)

    let font = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
  }

  @Test("A shortcut is not claimed by a pad that does not have focus")
  func unfocused() throws {
    let (_, view) = attached("hello")
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: 0, context: nil, characters: "b", charactersIgnoringModifiers: "b",
        isARepeat: false, keyCode: 11))
    #expect(!view.performKeyEquivalent(with: event))
  }

  /// The bug `ModeConfigurationPlan` exists for: ⌘B with nothing selected lasted
  /// only until the next refresh of the pad list.
  @Test("An update in the same mode keeps the typing attributes")
  func keepsTypingAttributes() {
    let (editor, view) = attached("hello")
    view.setSelectedRange(NSRange(location: 5, length: 0))
    editor.toggle(.bold)

    view.configureIfNeeded(for: .styled)
    #expect(TextFormatter.format(of: view.typingAttributes).isBold)

    view.configureIfNeeded(for: .plain)
    #expect(!TextFormatter.format(of: view.typingAttributes).isBold)
  }
}
