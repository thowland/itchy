import Foundation

/// A pad's content, in the only form the core can hold it.
///
/// The obvious design would be for the store to own an `NSAttributedString`, and
/// it would also mean the store links AppKit and D-2 collapses. So the core
/// handles content as the bytes of an RTFD bundle plus the extracted plain text,
/// and the conversion to and from `NSAttributedString` happens at the platform
/// boundary (D-2, specification §5.1).
///
/// The bundle is represented as a filename-to-bytes map rather than as opaque
/// `Data` or a `FileWrapper` (D-13). An RTFD bundle *is* a directory — `TXT.rtf`
/// plus its attachments — and `FR-5.3`'s acceptance criterion is that content
/// written by Itchy opens in TextEdit with images intact, which a flat packed
/// representation does not satisfy. A map is `Sendable`, `Equatable`, trivially
/// comparable in a test, and writable as a directory without AppKit.
public struct PadContent: Sendable, Equatable {
  /// The filename of the RTF document inside an RTFD bundle.
  public static let documentName = "TXT.rtf"

  /// Bundle contents keyed by filename within the bundle. `TXT.rtf` is expected
  /// to be present; attachments sit alongside it under their own names.
  public var bundle: [String: Data]

  /// Derived plain text.
  ///
  /// Written to the shadow file on every save and never read back by the
  /// application (`FR-5.4`). It is not authoritative: if it disagrees with the
  /// bundle, the bundle is right and the shadow file is stale.
  public var plainText: String

  public init(bundle: [String: Data], plainText: String) {
    self.bundle = bundle
    self.plainText = plainText
  }

  /// An empty styled document.
  public static func empty() -> PadContent {
    PadContent(
      bundle: [documentName: Data(emptyRTF.utf8)],
      plainText: "")
  }

  /// Content holding plain text only, with no attachments.
  public static func plainText(_ text: String) -> PadContent {
    PadContent(bundle: [documentName: Data(rtf(escaping: text).utf8)], plainText: text)
  }

  /// The RTF document bytes, when present.
  public var document: Data? {
    bundle[Self.documentName]
  }

  /// Filenames of everything in the bundle other than the RTF document.
  public var attachmentNames: [String] {
    bundle.keys.filter { $0 != Self.documentName }.sorted()
  }

  /// Total size of the bundle in bytes, which is what `FR-5.9` surfaces once a
  /// pad passes the size threshold.
  public var byteCount: Int {
    bundle.values.reduce(0) { $0 + $1.count }
  }

  private static let emptyRTF = """
    {\\rtf1\\ansi\\ansicpg1252\\cocoartf2820
    {\\fonttbl\\f0\\fnil\\fcharset0 SFMono-Regular;}
    \\f0\\fs24 }
    """

  /// Minimal RTF wrapper for plain text.
  ///
  /// The core writes RTF only for the degenerate plain-text case; everything
  /// styled is produced by the platform layer's `ContentCodec`, where
  /// `NSAttributedString` does the work properly.
  ///
  /// Non-ASCII characters are escaped as `\uN?` rather than written as raw
  /// bytes. An `\ansi` document's bytes are read as cp1252, so an em dash
  /// written literally comes back as `â€"` — which is how this was found, in a
  /// screenshot taken for the README.
  private static func rtf(escaping text: String) -> String {
    var escaped = ""
    for character in text {
      escaped += escapedRTF(character)
    }
    return """
      {\\rtf1\\ansi\\ansicpg1252\\cocoartf2820
      {\\fonttbl\\f0\\fnil\\fcharset0 SFMono-Regular;}
      \\f0\\fs24 \(escaped)}
      """
  }

  private static func escapedRTF(_ character: Character) -> String {
    switch character {
    case "\\": return "\\\\"
    case "{": return "\\{"
    case "}": return "\\}"
    case "\n": return "\\\n"
    default: break
    }
    guard !character.isASCII else { return String(character) }
    // RTF carries a Unicode scalar as \uN with an ASCII fallback after it, and
    // reads N as a signed 16-bit value. Scalars beyond the basic plane are
    // written as their surrogate pair, which is what RTF readers expect.
    var result = ""
    for scalar in String(character).utf16 {
      let signed = scalar > 32_767 ? Int(scalar) - 65_536 : Int(scalar)
      result += "\\u\(signed)?"
    }
    return result
  }
}
