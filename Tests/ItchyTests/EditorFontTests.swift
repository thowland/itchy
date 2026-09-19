import AppKit
import Foundation
import ItchyCore
import Testing

@testable import Itchy

/// D-19, `FR-4.10`: which runs follow the setting.
@Suite("Editor font policy")
struct EditorFontPolicyTests {
  private let body: Set<String> = [EditorFontPolicy.builtInFamily, "Menlo"]

  @Test(
    "Body text follows the setting and text in its own font keeps it",
    arguments: [
      (family: String?.some(EditorFontPolicy.builtInFamily), mode: PadMode.styled,
       expected: EditorFontPolicy.RunTreatment.followSettingKeepingTraits),
      (family: "Menlo", mode: .styled, expected: .followSettingKeepingTraits),
      (family: nil, mode: .styled, expected: .followSettingKeepingTraits),
      (family: "Helvetica", mode: .styled, expected: .keepOwnFont),
      (family: "Helvetica", mode: .plain, expected: .followSettingUnstyled),
      (family: nil, mode: .plain, expected: .followSettingUnstyled),
    ])
  func treatment(family: String?, mode: PadMode, expected: EditorFontPolicy.RunTreatment) {
    #expect(EditorFontPolicy.treatment(runFamily: family, mode: mode, bodyFamilies: body) == expected)
  }

  @Test("Body families are the built-in one, the current one, and former ones")
  func bodyFamilies() {
    var settings = AppSettings()
    settings.editorFontFamily = "Menlo"
    settings.formerEditorFontFamilies = ["Courier"]
    #expect(
      EditorFontPolicy.bodyFamilies(for: settings)
        == [EditorFontPolicy.builtInFamily, "Menlo", "Courier"])
  }

  /// A pad closed while Menlo was current is restyled only when reopened, by
  /// which point the setting names Courier.
  @Test("Replacing a family remembers it, most recent first")
  func remembersReplaced() {
    var settings = EditorFontPolicy.choosing(family: "Menlo", size: 14, in: AppSettings())
    #expect(settings.formerEditorFontFamilies.isEmpty, "the built-in font needs no remembering")

    settings = EditorFontPolicy.choosing(family: "Courier", size: 14, in: settings)
    settings = EditorFontPolicy.choosing(family: "Monaco", size: 14, in: settings)

    #expect(settings.editorFontFamily == "Monaco")
    #expect(settings.formerEditorFontFamilies == ["Courier", "Menlo"])
  }

  @Test("Choosing a remembered family again takes it off the list")
  func reselecting() {
    var settings = AppSettings()
    settings.editorFontFamily = "Courier"
    settings.formerEditorFontFamilies = ["Menlo"]

    let result = EditorFontPolicy.choosing(family: "Menlo", size: 14, in: settings)

    #expect(result.formerEditorFontFamilies == ["Courier"])
  }

  @Test("Changing only the size leaves the history alone, and the size is clamped")
  func sizeOnly() {
    var settings = AppSettings()
    settings.editorFontFamily = "Menlo"
    settings.formerEditorFontFamilies = ["Courier"]

    let result = EditorFontPolicy.choosing(family: "Menlo", size: 400, in: settings)

    #expect(result.formerEditorFontFamilies == ["Courier"])
    #expect(result.editorFontSize == EditorFontBounds.maximumSize)
  }

  @Test("The history is bounded")
  func bounded() {
    var settings = AppSettings()
    for index in 0..<20 {
      settings = EditorFontPolicy.choosing(family: "Family \(index)", size: 13, in: settings)
    }
    #expect(settings.formerEditorFontFamilies.count == EditorFontBounds.formerFamilyLimit)
    #expect(settings.formerEditorFontFamilies.first == "Family 18")
  }
}

@MainActor
@Suite("Body font")
struct BodyFontTests {
  private let body: Set<String> = [EditorFontPolicy.builtInFamily]

  private func font(at index: Int, in text: NSAttributedString) -> NSFont? {
    text.attribute(.font, at: index, effectiveRange: nil) as? NSFont
  }

  @Test("No family is the built-in monospaced font, which is what the editor used before")
  func builtIn() {
    #expect(BodyFont.font(family: nil, size: EditorFontBounds.defaultSize) == ContentCodec.defaultFont)
  }

  @Test("An installed family resolves at the requested size")
  func installed() {
    let font = BodyFont.font(family: "Menlo", size: 18)
    #expect(font.familyName == "Menlo")
    #expect(font.pointSize == 18)
  }

  @Test("A family that is not installed falls back to the built-in font, at the chosen size")
  func missingFamily() {
    let font = BodyFont.font(family: "No Such Family \(UUID())", size: 20)
    #expect(font.familyName == EditorFontPolicy.builtInFamily)
    #expect(font.pointSize == 20)
  }

  @Test("Body text takes the new size and keeps bold; pasted text keeps its own font")
  func styled() throws {
    let regular = ContentCodec.defaultFont
    let bold = NSFontManager.shared.convert(regular, toHaveTrait: .boldFontMask)
    let pasted = try #require(NSFont(name: "Helvetica", size: 24))
    let text = NSMutableAttributedString(string: "a", attributes: [.font: regular])
    text.append(NSAttributedString(string: "b", attributes: [.font: bold]))
    text.append(NSAttributedString(string: "c", attributes: [.font: pasted]))

    let target = BodyFont.font(family: nil, size: 18)
    BodyFont.restyle(text, to: target, mode: .styled, bodyFamilies: body)

    #expect(font(at: 0, in: text) == target)
    #expect(font(at: 1, in: text)?.pointSize == 18)
    #expect(
      NSFontManager.shared.traits(of: try #require(font(at: 1, in: text))).contains(.boldFontMask))
    #expect(font(at: 2, in: text) == pasted)
  }

  /// The case that matters most in practice: pads saved before the setting
  /// existed, read back through RTFD.
  @Test("Text saved in the old default is recognised after a round trip")
  func afterRoundTrip() throws {
    let original = NSAttributedString(
      string: "saved before", attributes: [.font: ContentCodec.defaultFont])
    let decoded = try ContentCodec.decode(try ContentCodec.encode(original))
    let text = NSMutableAttributedString(attributedString: decoded)

    BodyFont.restyle(text, to: BodyFont.font(family: "Menlo", size: 16), mode: .styled, bodyFamilies: body)

    #expect(font(at: 0, in: text)?.familyName == "Menlo")
    #expect(font(at: 0, in: text)?.pointSize == 16)
  }

  @Test("A plain pad is set entirely in the font, with no traits (FR-4.4)")
  func plain() throws {
    let bold = NSFontManager.shared.convert(ContentCodec.defaultFont, toHaveTrait: .boldFontMask)
    let text = NSMutableAttributedString(string: "a", attributes: [.font: bold])
    text.append(
      NSAttributedString(string: "b", attributes: [.font: try #require(NSFont(name: "Helvetica", size: 30))]))

    let target = BodyFont.font(family: nil, size: 15)
    BodyFont.restyle(text, to: target, mode: .plain, bodyFamilies: body)

    #expect(font(at: 0, in: text) == target)
    #expect(font(at: 1, in: text) == target)
  }

  @Test("Unstyled text with no font attribute is body text")
  func noFont() {
    let text = NSMutableAttributedString(string: "bare")
    let target = BodyFont.font(family: nil, size: 22)
    BodyFont.restyle(text, to: target, mode: .styled, bodyFamilies: body)
    #expect(font(at: 0, in: text) == target)
  }

  @Test("Restyling a text view does not register an undo step")
  func notUndoable() {
    let textView = PadTextView()
    textView.allowsUndo = true
    textView.textStorage?.setAttributedString(
      NSAttributedString(string: "x", attributes: [.font: ContentCodec.defaultFont]))
    let storage = textView.textStorage ?? NSTextStorage()

    BodyFont.restyle(storage, to: BodyFont.font(family: nil, size: 20), mode: .styled, bodyFamilies: body)

    #expect(textView.undoManager?.canUndo != true)
    #expect(font(at: 0, in: storage)?.pointSize == 20)
  }
}

@Suite("Editor font wording")
struct EditorFontModelTests {
  @Test("System-private families are hidden and the rest sorted")
  func choices() {
    let choices = EditorFontModel.familyChoices(
      available: ["Menlo", ".AppleSystemUIFont", "Courier", "andale Mono"], current: nil)
    #expect(choices == ["andale Mono", "Courier", "Menlo"])
  }

  @Test("A stored family that is no longer installed is still listed")
  func uninstalledCurrent() {
    let choices = EditorFontModel.familyChoices(available: ["Menlo"], current: "Gone")
    #expect(choices.contains("Gone"))
  }

  @Test("The size reads in points and the range is the bounds")
  func size() {
    #expect(EditorFontModel.sizeLabel(16) == "Size: 16 pt")
    #expect(EditorFontModel.sizeRange == EditorFontBounds.minimumSize...EditorFontBounds.maximumSize)
  }

  @Test("The caption says existing text changes and pasted fonts do not")
  func caption() {
    #expect(EditorFontModel.caption.contains("already"))
    #expect(EditorFontModel.caption.contains("pasted"))
  }
}

/// The flow through the coordinator: persisted, applied to content on the way
/// into a panel, and applied to a pad that is already open.
@MainActor
@Suite("Editor font through the coordinator")
struct EditorFontIntegrationTests {
  private func makeCoordinator() -> (PadCoordinator, PadStore, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-font-\(UUID().uuidString)")
    let layout = PadStorageLayout(root: root)
    let store = PadStore(layout: layout)
    return (PadCoordinator(store: store, layout: layout, launchOptions: LaunchOptions()), store, root)
  }

  @Test("A chosen font survives relaunch")
  func persists() {
    let (coordinator, _, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.setEditorFont(family: "Menlo", size: 17)

    let reloaded = SettingsStore(layout: PadStorageLayout(root: root)).load()
    #expect(reloaded.editorFontFamily == "Menlo")
    #expect(reloaded.editorFontSize == 17)
  }

  @Test("Content opened into a panel is set in the current font")
  func onOpen() {
    let (coordinator, _, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    coordinator.setEditorFont(family: nil, size: 19)

    let shown = coordinator.restyledForDisplay(
      NSAttributedString(string: "old", attributes: [.font: ContentCodec.defaultFont]), mode: .styled)

    #expect((shown.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 19)
  }

  @Test("A pad already open is restyled in place, and new typing uses the font")
  func openPad() {
    let (coordinator, store, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    let padID = PadID()
    let editor = PadTextCoordinator(padID: padID, store: store)
    let textView = PadTextView()
    textView.configure(for: .styled)
    textView.textStorage?.setAttributedString(
      NSAttributedString(string: "open", attributes: [.font: ContentCodec.defaultFont]))
    editor.attach(textView)
    coordinator.editors[padID] = editor

    coordinator.setEditorFont(family: "Menlo", size: 21)

    let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font?.familyName == "Menlo")
    #expect(font?.pointSize == 21)
    #expect((textView.typingAttributes[.font] as? NSFont)?.pointSize == 21)
    #expect(textView.bodyFont.pointSize == 21)
  }

  /// `FR-4.5` with the setting in play: flattening sets text in the chosen
  /// family, not the built-in one.
  ///
  /// Family and size both. This asserted the family alone while the applier
  /// went through `insertText(_:replacementRange:)`, which merges attributes
  /// into what it replaces and so kept the old point size; it now replaces the
  /// run outright, and flattening 30-point bold gives the editor font entire.
  @Test("Flattening uses the editor font")
  func flatten() {
    let (_, store, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    let editor = PadTextCoordinator(padID: PadID(), store: store)
    let textView = PadTextView()
    textView.bodyFont = BodyFont.font(family: "Menlo", size: 20)
    textView.configure(for: .styled)
    textView.textStorage?.setAttributedString(
      NSAttributedString(string: "styled", attributes: [.font: NSFont.boldSystemFont(ofSize: 30)]))
    editor.attach(textView)

    editor.flatten()

    let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font?.familyName == "Menlo")
    #expect(font?.pointSize == 20)
  }
}
