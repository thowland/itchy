import Foundation

/// What an image becomes in the plain-text shadow (`FR-8.6`, §11.4).
///
/// Reads return the shadow representation, so an agent reading a pad with a
/// screenshot in it must be told that something is there. Without this it gets
/// a bare `U+FFFC` object replacement character, which means nothing to an
/// agent, nothing to `grep`, and nothing to a person looking at `content.txt`.
///
/// A value, because the wording and the spacing are decisions and the traversal
/// that finds the attachments is not (D-11). `ContentCodec` walks the string;
/// this says what to write where it found one.
enum AttachmentPlaceholder {
  /// The object replacement character an `NSTextAttachment` occupies.
  static let objectReplacement: Character = "\u{FFFC}"

  /// §11.4 fixes the form. The multiplication sign is deliberate rather than an
  /// `x`: it is what the dimensions are written with everywhere else a person
  /// sees them, and it cannot be mistaken for part of a filename.
  static func text(width: Int, height: Int) -> String {
    guard width > 0, height > 0 else { return unsized }
    return "[image \(width)×\(height)]"
  }

  /// An attachment whose dimensions cannot be read. Rare — a file wrapper with
  /// no image — but "there is something here" is still worth saying.
  static let unsized = "[image]"

  /// Whether the placeholder needs a newline on either side.
  ///
  /// §11.4 asks for a single line, which means it must not be run together with
  /// the text around it. An attachment at the very start or end of a pad needs
  /// no separator on that side: a shadow file that begins with a blank line is
  /// a shadow file whose first line is wrong.
  static func line(
    _ placeholder: String, precededBy previous: Character?, followedBy next: Character?
  ) -> String {
    var result = ""
    if let previous, !previous.isNewline { result += "\n" }
    result += placeholder
    if let next, !next.isNewline { result += "\n" }
    return result
  }
}
