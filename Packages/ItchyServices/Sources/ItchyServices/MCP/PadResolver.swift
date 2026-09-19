import Foundation
import ItchyCore

/// Resolves the `pad` argument, which may be an identifier or a display name
/// (§11.3).
///
/// Agents refer to pads the way the person does — "scratch", "the json one" —
/// and requiring a UUID would mean every session begins with a `list_pads`
/// purely to translate. Names are therefore accepted, case-insensitively, and
/// the awkward case is handled rather than guessed: two pads with the same name
/// produce an explicit list of candidates, not a coin toss.
public enum PadResolver {
  public enum Resolution: Sendable, Equatable {
    case resolved(PadID)
    case notFound
    /// Names, not identifiers: the caller is being asked to be more specific in
    /// the vocabulary it used.
    case ambiguous(candidates: [String])
  }

  /// `pads` must already be narrowed to what the caller may see. §11.5 makes an
  /// unexposed pad indistinguishable from a nonexistent one, and the way to
  /// guarantee that is to never hand this function the pads it may not resolve.
  public static func resolve(_ reference: String, in pads: [PadMetadata]) -> Resolution {
    let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .notFound }
    if let id = PadID(string: trimmed), pads.contains(where: { $0.id == id }) {
      return .resolved(id)
    }
    let matches = pads.filter { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    switch matches.count {
    case 0: return .notFound
    case 1: return .resolved(matches[0].id)
    default: return .ambiguous(candidates: matches.map(\.name))
    }
  }
}
