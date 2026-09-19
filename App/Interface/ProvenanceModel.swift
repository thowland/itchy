import Foundation
import ItchyCore

/// One line in a pad's provenance list.
struct ProvenanceRow: Identifiable, Equatable, Sendable {
  let id: UUID
  /// Where it came from — an application, a site, or neither.
  let source: String
  /// What arrived, and roughly how much.
  let detail: String
  /// When, in the units a person would use.
  let when: String
  /// The URL, when there is one worth offering as a link.
  let url: URL?

  /// The same thing as a list of nought or one.
  ///
  /// So the row can be rendered with a `ForEach` rather than a conditional: the
  /// view may not branch (D-11, §15.3), and the alternative was a `Link` needing
  /// a placeholder destination for the case where there is no link — which
  /// meant inventing a file URL in a view, which `CON-4`'s lint refuses on
  /// sight and was right to.
  var links: [URL] { url.map { [$0] } ?? [] }
}

/// Projects a pad's provenance into what its panel shows (`FR-7.3`, D-11).
///
/// The wording is the whole of this feature's design, so it lives here rather
/// than in the view. Two rules run through it.
///
/// Nothing claims to know *which text* came from where. `FR-7.4` makes the
/// recorded range approximate and forbids presenting it as authoritative, and
/// the cheapest way to honour that is never to mention it — a list of arrivals
/// makes no claim that can drift, where a highlighted range would make one that
/// is wrong within a minute of editing.
///
/// And an entry says what it knows. A paste from an application that supplied
/// no URL says the application; one from a browser says the site as well;
/// one from neither says so plainly rather than showing an empty row.
enum ProvenanceModel {
  static func rows(for pad: PadMetadata, now: Date = Date()) -> [ProvenanceRow] {
    // Newest first: the question is almost always about what just arrived.
    pad.provenance.reversed().map { entry in
      ProvenanceRow(
        id: entry.id,
        source: source(of: entry),
        detail: detail(of: entry),
        when: age(from: entry.arrived, to: now),
        url: entry.sourceURL)
    }
  }

  static func source(of entry: ProvenanceEntry) -> String {
    if let name = entry.sourceAppName, !name.isEmpty { return name }
    if let bundle = entry.sourceBundleID, !bundle.isEmpty { return bundle }
    return "An unidentified application"
  }

  static func detail(of entry: ProvenanceEntry) -> String {
    let what = noun(for: entry.kind)
    guard let host = entry.sourceURL.flatMap(displayLocation) else {
      return "\(what), \(size(entry.byteCount))"
    }
    return "\(what) from \(host), \(size(entry.byteCount))"
  }

  /// A host for a web address and a filename for a file, because those are the
  /// parts a person recognises. A full URL in a narrow list is unreadable and
  /// mostly query string.
  static func displayLocation(_ url: URL) -> String? {
    guard !url.isFileURL else { return url.lastPathComponent }
    guard let host = url.host(), !host.isEmpty else { return nil }
    return host
  }

  static func noun(for kind: ProvenanceEntry.Kind) -> String {
    switch kind {
    case .text: "Plain text"
    case .styledText: "Styled text"
    case .image: "An image"
    case .file: "A file"
    }
  }

  /// Coarse, like everything else this application says about size. The number
  /// exists to distinguish a line from a screenshot.
  static func size(_ bytes: Int) -> String {
    guard bytes >= 1_024 else { return "\(max(bytes, 0)) bytes" }
    let kilobytes = Double(bytes) / 1_024
    guard kilobytes >= 1_024 else { return "\(Int(kilobytes.rounded())) KB" }
    return String(format: "%.1f MB", kilobytes / 1_024)
  }

  static func age(from arrived: Date, to now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(arrived))
    switch seconds {
    case ..<0: return "just now"
    case ..<60: return "just now"
    case ..<3_600: return "\(seconds / 60)m ago"
    case ..<86_400: return "\(seconds / 3_600)h ago"
    default: return "\(seconds / 86_400)d ago"
    }
  }

  // MARK: - What the sheet says about itself

  static let title = "Where this came from"

  /// Shown instead of a list. A pad nothing has been pasted into is the normal
  /// case for a pad somebody typed in, not an error.
  static let emptyMessage =
    "Nothing has been pasted or dropped into this pad. Itchy records where "
    + "content arrived from, not what you typed."

  /// `FR-7.4` in one sentence, where somebody reading the list will see it.
  static let caption =
    "The most recent arrivals, newest first. Itchy does not track which text "
    + "came from which arrival — editing moves it, and a claim that drifts is "
    + "worse than none."

  static let clearLabel = "Clear"

  /// `FR-7.5`: clearing empties the list and leaves the content alone. Said,
  /// because a button called Clear on a pad could reasonably be read as
  /// clearing the pad.
  static let clearNote = "Clearing the list leaves the pad's contents untouched."

  static func summary(count: Int) -> String {
    switch count {
    case 0: "No arrivals recorded"
    case 1: "1 arrival recorded"
    default: "\(count) arrivals recorded"
    }
  }

  /// Said only when the list is full, so that a person who expects to see
  /// something older learns why it is not there rather than assuming a bug.
  static func trimmedNote(count: Int, limit: Int = ProvenanceBounds.limit) -> String? {
    guard count >= limit else { return nil }
    return "Only the most recent \(limit) are kept."
  }
}
