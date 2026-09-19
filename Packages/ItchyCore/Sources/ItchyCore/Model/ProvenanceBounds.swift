import Foundation

/// How much provenance a pad keeps (`FR-7.3`).
///
/// `FR-7.3` asks for "a short list of what has been pasted into the pad and
/// from where", and its acceptance criterion says the list "reflects the last
/// several arrivals". Several, not all — so there is a bound, and this is it.
///
/// The bound is not cosmetic. Provenance lives in `meta.json`, which is
/// rewritten in full on every save; an unbounded list means a pad pasted into
/// all week carries a file that grows forever and is written forever. `CON-7`
/// says nothing in the storage design may be justified by scale, and this is
/// the other side of that: nothing in it may be allowed to grow without one.
public enum ProvenanceBounds {
  /// Enough to answer "where did this come from" about a working session, and
  /// far short of anything that makes `meta.json` worth worrying about.
  public static let limit = 50

  /// The entries to keep, oldest first, once a new one has been added.
  ///
  /// Keeps the newest, because the question provenance answers is about what
  /// is in the pad now, and the oldest entries are the likeliest to refer to
  /// text that has since been deleted.
  public static func trimmed(_ entries: [ProvenanceEntry], limit: Int = limit) -> [ProvenanceEntry] {
    guard entries.count > limit else { return entries }
    return Array(entries.suffix(limit))
  }
}
