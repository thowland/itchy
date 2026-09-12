import AppKit
import ItchyCore
import Testing

@testable import Itchy

@Suite("Content codec")
struct ContentCodecTests {
  /// D-15: an attachment built with `attachmentCell` rather than `image` is
  /// dropped silently by RTFD serialisation, so fixtures set `image`.
  private func swatch(width: CGFloat = 120, height: CGFloat = 60) -> NSImage {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.systemRed.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
  }

  private func attributedWithImage() -> NSAttributedString {
    let result = NSMutableAttributedString(
      string: "before ", attributes: [.font: NSFont.systemFont(ofSize: 14)])
    let attachment = NSTextAttachment()
    attachment.image = swatch()
    result.append(NSAttributedString(attachment: attachment))
    result.append(
      NSAttributedString(string: " after", attributes: [.font: NSFont.systemFont(ofSize: 14)]))
    return result
  }

  private func attachmentCount(in attributed: NSAttributedString) -> Int {
    var count = 0
    attributed.enumerateAttribute(
      .attachment, in: NSRange(location: 0, length: attributed.length)
    ) { value, _, _ in
      if value != nil { count += 1 }
    }
    return count
  }

  @Test("Styled text round-trips with its attributes intact (FR-4.1)")
  func styledRoundTrip() throws {
    let original = NSMutableAttributedString(string: "bold and plain")
    original.addAttribute(
      .font, value: NSFont.boldSystemFont(ofSize: 18), range: NSRange(location: 0, length: 4))

    let decoded = try ContentCodec.decode(try ContentCodec.encode(original))

    #expect(decoded.string == "bold and plain")
    let font = decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font?.pointSize == 18)
  }

  /// `FR-4.2`: the requirement that settles the whole editor decision.
  @Test("An inline image survives the round trip")
  func imageRoundTrip() throws {
    let original = attributedWithImage()
    #expect(attachmentCount(in: original) == 1)

    let content = try ContentCodec.encode(original)
    let decoded = try ContentCodec.decode(content)

    #expect(attachmentCount(in: decoded) == 1)
    #expect(decoded.string.contains("before"))
    #expect(decoded.string.contains("after"))
  }

  /// `FR-5.3`: the bundle must be a real RTFD bundle, which is what lets TextEdit
  /// open it. A flat representation would satisfy the round trip and fail the
  /// requirement (D-13).
  @Test("An image is carried as a file alongside the document, not inside it")
  func bundleShape() throws {
    let content = try ContentCodec.encode(attributedWithImage())

    #expect(content.bundle[PadContent.documentName] != nil, "TXT.rtf must be present")
    #expect(!content.attachmentNames.isEmpty, "the image must be its own file in the bundle")
  }

  @Test("Plain text is extracted for the shadow file (FR-5.4)")
  func plainTextExtraction() throws {
    let content = try ContentCodec.encode(
      NSAttributedString(string: "a tracking number: 1Z999AA10123456784"))
    #expect(content.plainText == "a tracking number: 1Z999AA10123456784")
  }

  @Test("Empty content decodes to an empty string rather than failing")
  func emptyBundle() throws {
    let decoded = try ContentCodec.decode(PadContent(bundle: [:], plainText: ""))
    #expect(decoded.length == 0)
  }

  @Test("An unreadable bundle is reported rather than silently yielding nothing")
  func corruptBundle() {
    let content = PadContent(bundle: ["TXT.rtf": Data("not rtf at all".utf8)], plainText: "")
    #expect(throws: ContentCodec.CodecError.couldNotDeserialise) {
      _ = try ContentCodec.decode(content)
    }
  }

  /// `FR-4.5`: flattening destroys attributes and attachments, which is the
  /// point, and is why provenance lives in metadata instead (`FR-7.2`).
  @Test("Flattening removes styling and attachments but keeps the text")
  func flatten() throws {
    let original = attributedWithImage()
    let flattened = ContentCodec.flatten(original)

    #expect(attachmentCount(in: flattened) == 0)
    #expect(flattened.string == original.string)
    let font = flattened.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font == ContentCodec.defaultFont)
  }

  @Test("Content written by the codec is what the store would persist")
  func matchesStoreExpectations() throws {
    let content = try ContentCodec.encode(NSAttributedString(string: "hello"))
    #expect(content.document != nil)
    #expect(content.byteCount > 0)
  }
}

@Suite("Downsample policy")
struct DownsamplePolicyTests {
  @Test(
    "Images at or under the threshold are left alone",
    arguments: [
      CGSize(width: 100, height: 100),
      CGSize(width: 1_600, height: 900),
      CGSize(width: 900, height: 1_600),
    ])
  func belowThreshold(size: CGSize) {
    #expect(DownsamplePolicy.target(for: size) == nil)
  }

  /// A full-screen Retina capture is the case this exists for (`NFR-1.4`).
  @Test("A Retina screenshot is reduced, preserving aspect ratio")
  func retinaScreenshot() throws {
    let target = try #require(DownsamplePolicy.target(for: CGSize(width: 3_024, height: 1_964)))
    #expect(target.width == 1_600)
    #expect(abs(target.height - 1_039) <= 1, "aspect ratio is preserved")
  }

  @Test("A tall image is reduced on its longest edge")
  func tallImage() throws {
    let target = try #require(DownsamplePolicy.target(for: CGSize(width: 800, height: 4_000)))
    #expect(target.height == 1_600)
    #expect(target.width == 320)
  }

  @Test("A degenerate size does not crash or divide by zero")
  func zeroSize() {
    #expect(DownsamplePolicy.target(for: .zero) == nil)
  }
}
