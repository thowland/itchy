import AppKit
import ItchyCore
import Testing

@testable import Itchy

/// Runs against real `NSPasteboard` instances rather than a reimplementation of
/// one: the pasteboard's type negotiation is most of what the interceptor is
/// reasoning about, and a fake would only assert that the fake agrees with
/// itself.
@MainActor
@Suite("Paste interceptor")
struct PasteInterceptorTests {
  private func scratchPasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("itchy.test.\(UUID().uuidString)"))
    pasteboard.clearContents()
    return pasteboard
  }

  private func swatch(width: CGFloat = 2_400, height: CGFloat = 1_200) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.systemOrange.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.unlockFocus()
    return image
  }

  /// A text view in a window.
  ///
  /// The window is not decoration: `NSTextView.undoManager` comes from the
  /// window, so a detached text view has none and every undo assertion would
  /// pass vacuously. In the application there is always a window.
  private func hosted(mode: PadMode = .styled) -> (window: NSWindow, textView: PadTextView) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
      styleMask: [.titled], backing: .buffered, defer: false)
    let view = PadTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    view.configure(for: mode)
    window.contentView = view
    return (window, view)
  }

  @Test("Plain text on the pasteboard is described as plain text")
  func describesPlainText() {
    let pasteboard = scratchPasteboard()
    pasteboard.setString("1Z999AA10123456784", forType: .string)

    let descriptor = PasteInterceptor.describe(pasteboard, source: nil)

    #expect(descriptor.plainText == "1Z999AA10123456784")
    #expect(descriptor.imageSizes.isEmpty)
    #expect(!descriptor.hasRTFD)
  }

  @Test("Styled content is described as styled")
  func describesStyled() throws {
    let pasteboard = scratchPasteboard()
    let styled = NSMutableAttributedString(string: "styled")
    styled.addAttribute(
      .font, value: NSFont.boldSystemFont(ofSize: 20), range: NSRange(location: 0, length: 6))
    pasteboard.writeObjects([styled])

    let descriptor = PasteInterceptor.describe(pasteboard, source: nil)

    #expect(descriptor.hasRTF || descriptor.hasRTFD)
  }

  @Test("An image on the pasteboard is described with its size")
  func describesImage() throws {
    let pasteboard = scratchPasteboard()
    pasteboard.writeObjects([swatch()])

    let descriptor = PasteInterceptor.describe(pasteboard, source: nil)

    let size = try #require(descriptor.imageSizes.first)
    #expect(size.width == 2_400)
  }

  /// `FR-7.1`: the source application is recorded, and §9.5 explains why it
  /// comes from the tracker rather than from a query made now.
  @Test("The source application is taken from what is passed in, not queried")
  func sourceApplication() {
    let pasteboard = scratchPasteboard()
    pasteboard.setString("text", forType: .string)

    let descriptor = PasteInterceptor.describe(pasteboard, source: nil)

    #expect(descriptor.sourceBundleID == nil, "no source means no claim about one")
  }

  @Test("A web URL is recognised and a plain string is not mistaken for one")
  func webURL() {
    let withURL = scratchPasteboard()
    withURL.setString("https://example.invalid/orders/88121", forType: .string)
    #expect(PasteInterceptor.readWebURL(from: withURL)?.host() == "example.invalid")

    let withoutURL = scratchPasteboard()
    withoutURL.setString("just some words", forType: .string)
    #expect(PasteInterceptor.readWebURL(from: withoutURL) == nil)

    let fileish = scratchPasteboard()
    fileish.setString("/tmp/notes.txt", forType: .string)
    #expect(PasteInterceptor.readWebURL(from: fileish) == nil, "a path is not a web URL")
  }

  @Test("Pasting plain text inserts it and reports provenance")
  func pastesPlainText() throws {
    let pasteboard = scratchPasteboard()
    pasteboard.setString("inserted text", forType: .string)
    let host = hosted()
    let view = host.textView
    let descriptor = PasteInterceptor.describe(pasteboard, source: nil)
    let plan = PastePlan.plan(for: descriptor, mode: .styled)

    let entry = PasteInterceptor.apply(
      plan, descriptor: descriptor, from: pasteboard, to: view)

    withExtendedLifetime(host) { #expect(view.string == "inserted text") }
    #expect(entry?.kind == .text)
  }

  /// `FR-4.4`: pasting styled content with an image into a plain pad yields
  /// unstyled text and no attachment.
  @Test("Pasting into a plain pad discards styling")
  func pastesIntoPlainPad() throws {
    let pasteboard = scratchPasteboard()
    let styled = NSMutableAttributedString(string: "styled words")
    styled.addAttribute(
      .font, value: NSFont.boldSystemFont(ofSize: 30), range: NSRange(location: 0, length: 6))
    pasteboard.writeObjects([styled])
    pasteboard.setString("styled words", forType: .string)

    let host = hosted(mode: .plain)
    let view = host.textView
    let descriptor = PasteInterceptor.describe(pasteboard, source: nil)
    let plan = PastePlan.plan(for: descriptor, mode: .plain)
    PasteInterceptor.apply(plan, descriptor: descriptor, from: pasteboard, to: view)

    #expect(view.string == "styled words")
    let font = view.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font?.pointSize != 30, "the pasted styling must not survive into a plain pad")
  }

  /// `FR-4.3`: an image above the threshold is downsampled on arrival.
  @Test("A large pasted image is downsampled before it is inserted")
  func downsamplesOnPaste() throws {
    let pasteboard = scratchPasteboard()
    pasteboard.writeObjects([swatch(width: 3_200, height: 1_600)])
    let host = hosted()
    let view = host.textView
    let descriptor = PasteInterceptor.describe(pasteboard, source: nil)
    let plan = PastePlan.plan(for: descriptor, mode: .styled)

    let entry = PasteInterceptor.apply(
      plan, descriptor: descriptor, from: pasteboard, to: view)

    let attributed = view.attributedString()
    var inserted: NSTextAttachment?
    attributed.enumerateAttribute(
      .attachment, in: NSRange(location: 0, length: attributed.length)
    ) { value, _, _ in
      inserted = inserted ?? (value as? NSTextAttachment)
    }
    let attachment = try #require(inserted)
    let size = try #require(attachment.image?.size)
    #expect(max(size.width, size.height) == DownsamplePolicy.maximumEdge)
    #expect(entry?.kind == .image)
  }

  @Test("An empty pasteboard inserts nothing and records nothing")
  func emptyPasteboard() {
    let pasteboard = scratchPasteboard()
    let host = hosted()
    let view = host.textView
    let descriptor = PasteInterceptor.describe(pasteboard, source: nil)
    let plan = PastePlan.plan(for: descriptor, mode: .styled)

    let entry = PasteInterceptor.apply(
      plan, descriptor: descriptor, from: pasteboard, to: view)

    #expect(view.string.isEmpty)
    #expect(entry == nil)
  }

  /// One paste is one undo, which is the same grouped path a transform and an
  /// agent write take (D-9).
  @Test("A paste is a single undoable operation")
  func pasteIsOneUndo() throws {
    let pasteboard = scratchPasteboard()
    pasteboard.setString("undo me", forType: .string)
    let host = hosted()
    let view = host.textView
    let descriptor = PasteInterceptor.describe(pasteboard, source: nil)
    let plan = PastePlan.plan(for: descriptor, mode: .styled)
    PasteInterceptor.apply(plan, descriptor: descriptor, from: pasteboard, to: view)
    #expect(view.string == "undo me")

    let undoManager = try #require(view.undoManager, "a hosted text view has an undo manager")
    undoManager.undo()

    #expect(view.string.isEmpty)
  }
}

@MainActor
@Suite("Pad text view configuration")
struct PadTextViewTests {
  private func view(mode: PadMode) -> PadTextView {
    let created = PadTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    created.configure(for: mode)
    return created
  }

  /// `FR-4.1`, `FR-4.2`: a styled pad retains attributes and accepts images.
  @Test("A styled pad is rich and imports graphics")
  func styled() {
    let textView = view(mode: .styled)
    #expect(textView.isRichText)
    #expect(textView.importsGraphics)
    #expect(textView.mode == .styled)
  }

  /// `FR-4.4`: a plain pad holds no attributes and no attachments.
  @Test("A plain pad is not rich and imports nothing")
  func plain() {
    let textView = view(mode: .plain)
    #expect(!textView.isRichText)
    #expect(!textView.importsGraphics)
    #expect(!textView.allowsImageEditing)
  }

  /// Not configurable, and deliberately so: a plain pad holds a JSON fragment or
  /// a SQL clause, and smart quotes silently corrupting a string literal is the
  /// single most annoying thing a scratchpad can do.
  @Test("Substitutions are off in plain mode")
  func substitutions() {
    let plain = view(mode: .plain)
    #expect(!plain.isAutomaticQuoteSubstitutionEnabled)
    #expect(!plain.isAutomaticDashSubstitutionEnabled)
    #expect(!plain.isAutomaticTextReplacementEnabled)
  }

  /// Arrives free with the AppKit text view and must not be reimplemented
  /// (specification §9.2).
  @Test("Undo and spell checking come from the text view itself")
  func inheritedBehaviour() {
    let textView = view(mode: .styled)
    #expect(textView.allowsUndo)
    #expect(textView.isContinuousSpellCheckingEnabled)
    #expect(!textView.isAutomaticSpellingCorrectionEnabled)
  }

  @Test("Switching mode reconfigures in place")
  func modeSwitch() {
    let textView = view(mode: .styled)
    textView.configure(for: .plain)
    #expect(!textView.isRichText)
    #expect(textView.mode == .plain)
  }
}
