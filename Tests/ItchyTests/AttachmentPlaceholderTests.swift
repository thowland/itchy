import AppKit
import ItchyCore
import Testing

@testable import Itchy

/// `FR-8.6` and §11.4: a pad with an image reads back as text with a stable
/// placeholder, rather than with a bare object replacement character that means
/// nothing to an agent, to `grep`, or to a person reading `content.txt`.
@Suite("Attachment placeholders in the shadow text")
struct AttachmentPlaceholderTests {
  private func swatch(width: CGFloat, height: CGFloat) -> NSImage {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.systemRed.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
  }

  private func attachment(width: CGFloat, height: CGFloat) -> NSAttributedString {
    let attachment = NSTextAttachment()
    attachment.image = swatch(width: width, height: height)
    return NSAttributedString(attachment: attachment)
  }

  // MARK: - The form, §11.4

  @Test("The placeholder is the form the specification fixed")
  func form() {
    #expect(AttachmentPlaceholder.text(width: 1_240, height: 820) == "[image 1240×820]")
  }

  @Test("An attachment with no readable size still says something is there")
  func unsized() {
    #expect(AttachmentPlaceholder.text(width: 0, height: 820) == "[image]")
    #expect(AttachmentPlaceholder.text(width: -1, height: -1) == AttachmentPlaceholder.unsized)
  }

  @Test("It occupies its own line, without inventing blank ones")
  func spacing() {
    #expect(AttachmentPlaceholder.line("[image]", precededBy: "x", followedBy: "y") == "\n[image]\n")
    #expect(AttachmentPlaceholder.line("[image]", precededBy: nil, followedBy: nil) == "[image]")
    #expect(
      AttachmentPlaceholder.line("[image]", precededBy: "\n", followedBy: "\n") == "[image]")
  }

  // MARK: - The substitution

  @Test("An image between two words becomes a placeholder on its own line")
  func inlineImage() {
    let text = NSMutableAttributedString(string: "before ")
    text.append(attachment(width: 120, height: 60))
    text.append(NSAttributedString(string: " after"))

    #expect(ContentCodec.shadowText(of: text) == "before \n[image 120×60]\n after")
  }

  @Test("Text with no image is returned exactly as it was")
  func noImage() {
    let text = NSAttributedString(string: "just words\nand a line")
    #expect(ContentCodec.shadowText(of: text) == "just words\nand a line")
  }

  @Test("Several images each get their own placeholder and their own size")
  func severalImages() {
    let text = NSMutableAttributedString(string: "one")
    text.append(attachment(width: 10, height: 20))
    text.append(NSAttributedString(string: "two"))
    text.append(attachment(width: 30, height: 40))

    #expect(ContentCodec.shadowText(of: text) == "one\n[image 10×20]\ntwo\n[image 30×40]")
  }

  /// The offsets are UTF-16, because that is what `NSAttributedString` indexes
  /// by. Walking `Character`s instead desynchronises at the first astral-plane
  /// scalar, and the symptom is a placeholder carrying the wrong image's size.
  @Test("An emoji before the image does not shift the size that is read")
  func surrogatePairsDoNotShiftOffsets() {
    let text = NSMutableAttributedString(string: "🐈🐈 ")
    text.append(attachment(width: 77, height: 88))

    #expect(ContentCodec.shadowText(of: text) == "🐈🐈 \n[image 77×88]")
  }

  @Test("An image alone in a pad is the whole of its text")
  func imageOnly() {
    #expect(ContentCodec.shadowText(of: attachment(width: 5, height: 5)) == "[image 5×5]")
  }

  @Test("An empty pad has empty text")
  func empty() {
    #expect(ContentCodec.shadowText(of: NSAttributedString()).isEmpty)
  }

  @Test("An image already on its own line is not given a second one")
  func alreadyOnItsOwnLine() {
    let text = NSMutableAttributedString(string: "above\n")
    text.append(attachment(width: 1, height: 2))
    text.append(NSAttributedString(string: "\nbelow"))

    #expect(ContentCodec.shadowText(of: text) == "above\n[image 1×2]\nbelow")
  }

  /// An object replacement character that is not an attachment — a stray one
  /// pasted as text — still reads as something rather than as nothing.
  @Test("A bare object replacement character is named too")
  func bareObjectReplacement() {
    let text = NSAttributedString(string: "a\u{FFFC}b")
    #expect(ContentCodec.shadowText(of: text) == "a\n[image]\nb")
  }

  // MARK: - What reaches the store

  @Test("The placeholder is what a pad's content carries, and so what a read returns")
  func reachesPadContent() throws {
    let text = NSMutableAttributedString(string: "screenshot:\n")
    text.append(attachment(width: 200, height: 100))

    let content = try ContentCodec.encode(text)

    #expect(content.plainText == "screenshot:\n[image 200×100]")
    #expect(content.plainText.contains("\u{FFFC}") == false)
  }
}
