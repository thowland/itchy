import AppKit
import ItchyCore

/// Converts between `NSAttributedString` and `PadContent`.
///
/// The boundary D-2 turns on: the core holds content as an RTFD bundle map plus
/// extracted plain text so that it never links AppKit, and the conversion
/// happens here (specification §5.1, §15.2). It costs one conversion per load
/// and per save, both of which are already off the keystroke path.
enum ContentCodec {
  enum CodecError: Error, Equatable {
    case couldNotSerialise
    case couldNotDeserialise
  }

  /// `NSAttributedString` to the bundle map the store writes as a directory.
  static func encode(_ attributed: NSAttributedString) throws -> PadContent {
    let range = NSRange(location: 0, length: attributed.length)
    let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [
      .documentType: NSAttributedString.DocumentType.rtfd
    ]
    guard let wrapper = try? attributed.fileWrapper(from: range, documentAttributes: attributes)
    else {
      throw CodecError.couldNotSerialise
    }
    return PadContent(bundle: files(in: wrapper), plainText: shadowText(of: attributed))
  }

  /// The plain text as the shadow file and the MCP surface see it (`FR-8.6`).
  ///
  /// `attributed.string` leaves a bare `U+FFFC` where each image was. The
  /// substitution has to happen here rather than downstream, because by the time
  /// the core has the plain text the attachment and its dimensions are gone —
  /// and `PadContent.plainText` is what a read returns.
  ///
  /// This changes the shadow file on disk for any pad containing an image.
  /// `FR-5.4` calls the shadow derived and never read back, so nothing should
  /// depend on it, and no migration is needed for that reason: a pad written by
  /// an older build is rewritten on its next save. If a migration ever turns out
  /// to be needed, the derivation is wrong.
  static func shadowText(of attributed: NSAttributedString) -> String {
    let text = attributed.string as NSString
    guard text.length > 0 else { return "" }

    var result = ""
    var runStart = 0
    // UTF-16 offsets throughout, because that is what NSAttributedString
    // indexes by. Walking Characters instead desynchronises the moment a pad
    // contains an emoji, and the symptom is a placeholder reading the size of
    // the wrong image.
    for offset in 0..<text.length where text.character(at: offset) == Self.objectReplacementUnit {
      result += text.substring(with: NSRange(location: runStart, length: offset - runStart))
      result += AttachmentPlaceholder.line(
        placeholder(at: offset, in: attributed),
        precededBy: result.last,
        followedBy: character(after: offset, in: text))
      runStart = offset + 1
    }
    guard runStart > 0 else { return attributed.string }
    return result + text.substring(from: runStart)
  }

  private static let objectReplacementUnit = unichar(0xFFFC)

  private static func character(after offset: Int, in text: NSString) -> Character? {
    let next = offset + 1
    guard next < text.length else { return nil }
    return Character(UnicodeScalar(text.character(at: next)) ?? " ")
  }

  /// The attachment's size, from its image if it has one and from the bounds the
  /// layout gave it otherwise.
  private static func placeholder(at offset: Int, in attributed: NSAttributedString) -> String {
    guard
      let attachment = attributed.attribute(.attachment, at: offset, effectiveRange: nil)
        as? NSTextAttachment
    else {
      return AttachmentPlaceholder.unsized
    }
    let size = attachment.image?.size ?? attachment.bounds.size
    return AttachmentPlaceholder.text(
      width: Int(size.width.rounded()), height: Int(size.height.rounded()))
  }

  /// The bundle map back to an `NSAttributedString`.
  ///
  /// Reconstructs the file wrapper in memory rather than reading the directory
  /// from disk, because only the store touches disk (`CON-4`).
  static func decode(_ content: PadContent) throws -> NSAttributedString {
    guard !content.bundle.isEmpty else { return NSAttributedString() }
    let wrapper = FileWrapper(
      directoryWithFileWrappers: content.bundle.mapValues { FileWrapper(regularFileWithContents: $0) })
    guard let data = wrapper.serializedRepresentation,
      let attributed = NSAttributedString(rtfd: data, documentAttributes: nil)
    else {
      throw CodecError.couldNotDeserialise
    }
    return attributed
  }

  /// Flattens to unstyled text (`FR-4.5`).
  ///
  /// Shares its implementation with the `flatten` transform arriving in Sprint 6:
  /// one code path, invoked from two places.
  static func flatten(_ attributed: NSAttributedString) -> NSAttributedString {
    flatten(attributed, font: defaultFont)
  }

  static func flatten(_ attributed: NSAttributedString, font: NSFont) -> NSAttributedString {
    NSAttributedString(string: attributed.string, attributes: [.font: font])
  }

  static var defaultFont: NSFont {
    NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
  }

  /// Regular files directly inside a bundle wrapper, keyed by name.
  private static func files(in wrapper: FileWrapper) -> [String: Data] {
    guard let children = wrapper.fileWrappers else { return [:] }
    return children.reduce(into: [String: Data]()) { result, entry in
      guard let contents = entry.value.regularFileContents else { return }
      result[entry.key] = contents
    }
  }
}
