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
    return PadContent(bundle: files(in: wrapper), plainText: attributed.string)
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
