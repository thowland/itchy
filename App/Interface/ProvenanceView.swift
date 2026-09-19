import ItchyCore
import SwiftUI

/// A pad's provenance list (`FR-7.3`, `FR-7.5`).
///
/// On the coverage exclusion list and so may not branch: every string, every
/// row and the decision about what a row says are `ProvenanceModel`'s.
struct ProvenanceView: View {
  let pad: PadMetadata
  let coordinator: PadCoordinator
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let current = coordinator.metadata(for: pad)
    let rows = ProvenanceModel.rows(for: current)
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        Text(ProvenanceModel.title)
          .font(.headline)
        Text(ProvenanceModel.summary(count: rows.count))
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("pad.provenance.summary")
      }
      .padding([.top, .horizontal])

      ProvenanceList(rows: rows)

      VStack(alignment: .leading, spacing: 4) {
        Text(ProvenanceModel.caption)
        TrimmedNote(note: ProvenanceModel.trimmedNote(count: rows.count))
        Text(ProvenanceModel.clearNote)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal)

      HStack {
        Button(ProvenanceModel.clearLabel) {
          coordinator.clearProvenance(pad.id)
        }
        .disabled(rows.isEmpty)
        .accessibilityIdentifier("pad.provenance.clear")
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding()
    }
    .frame(width: 420, height: 380)
  }
}

/// The rows, or the sentence that stands in for them.
struct ProvenanceList: View {
  let rows: [ProvenanceRow]

  var body: some View {
    List {
      EmptyProvenanceText(isEmpty: rows.isEmpty)
      ForEach(rows) { row in
        ProvenanceRowView(row: row)
      }
    }
    .listStyle(.inset)
    .accessibilityIdentifier("pad.provenance.list")
  }
}

struct ProvenanceRowView: View {
  let row: ProvenanceRow

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(row.source)
          .font(.body)
        Spacer()
        Text(row.when)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
      Text(row.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(row.links, id: \.self) { url in
        ProvenanceLink(url: url)
      }
    }
    .padding(.vertical, 2)
  }
}

/// One link, rendered only because the row had one to give — see
/// `ProvenanceRow.links` for why this takes a URL rather than an optional.
struct ProvenanceLink: View {
  let url: URL

  var body: some View {
    Link(destination: url) {
      Text(url.absoluteString)
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .accessibilityIdentifier("pad.provenance.link")
  }
}

struct EmptyProvenanceText: View {
  let isEmpty: Bool

  var body: some View {
    Text(ProvenanceModel.emptyMessage)
      .font(.callout)
      .foregroundStyle(.secondary)
      .opacity(isEmpty ? 1 : 0)
      .frame(height: isEmpty ? nil : 0)
  }
}

struct TrimmedNote: View {
  let note: String?

  var body: some View {
    Text(note ?? "")
      .opacity(note == nil ? 0 : 1)
      .frame(height: note == nil ? 0 : nil)
  }
}
