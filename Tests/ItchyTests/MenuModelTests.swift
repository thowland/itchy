import ItchyCore
import SwiftUI
import Testing

@testable import Itchy

@Suite("Menu model")
struct MenuModelTests {
  private func pad(_ name: String, mode: PadMode = .styled, pinned: Bool = false) -> PadMetadata {
    PadMetadata(
      name: name, mode: mode, created: .distantPast, modified: .distantPast, isPinned: pinned)
  }

  @Test("Rows carry slot numbers in list order")
  func slotNumbers() {
    let rows = MenuModel.rows(pads: [pad("a"), pad("b"), pad("c")])
    #expect(rows.map(\.slot) == [1, 2, 3])
    #expect(rows.map(\.name) == ["a", "b", "c"])
  }

  @Test("The first nine pads get a key equivalent and the rest do not")
  func keyEquivalents() {
    let rows = MenuModel.rows(pads: (1...12).map { pad("pad \($0)") })
    #expect(rows.prefix(9).map(\.keyEquivalent) == (1...9).map(String.init))
    #expect(rows.dropFirst(9).allSatisfy { $0.keyEquivalent == nil })
  }

  /// `FR-5.9`: a pad that has grown past the threshold is marked, so that a pad
  /// accumulating screenshots cannot do it unnoticed.
  @Test("Only pads past the threshold carry a size marker")
  func sizeMarkers() {
    let small = pad("small")
    let large = pad("large")
    let rows = MenuModel.rows(
      pads: [small, large],
      sizes: [small.id: 1_000, large.id: 40 * 1_048_576],
      threshold: 32 * 1_048_576)
    #expect(rows[0].sizeMarker == nil)
    #expect(rows[1].sizeMarker == "40 MB")
  }

  @Test(
    "Size labels stay coarse",
    arguments: [
      (bytes: 33 * 1_048_576, expected: "33 MB"),
      (bytes: 512 * 1_048_576, expected: "512 MB"),
      (bytes: 2048 * 1_048_576, expected: "2.0 GB"),
    ])
  func sizeLabels(bytes: Int, expected: String) {
    #expect(MenuModel.sizeLabel(bytes) == expected)
  }

  /// Specification §6.7: a faulted pad is listed and selectable, so the menu has
  /// to be able to say so.
  @Test("A pad whose content cannot be read is marked faulted but still listed")
  func faultedPads() {
    let broken = pad("broken")
    let fine = pad("fine")
    let rows = MenuModel.rows(
      pads: [broken, fine],
      faults: [broken.id: .contentMissing(broken.id)])
    #expect(rows.count == 2)
    #expect(rows[0].isFaulted)
    #expect(!rows[1].isFaulted)
  }

  @Test("A fault that does not prohibit editing does not mark the row")
  func nonProhibitingFault() {
    let pad = pad("busy")
    let rows = MenuModel.rows(pads: [pad], faults: [pad.id: .writeFailed(pad.id, underlying: "x")])
    #expect(!rows[0].isFaulted)
  }

  @Test("Pinned pads are flagged so the menu can mark them")
  func pinned() {
    let rows = MenuModel.rows(pads: [pad("plain"), pad("stuck", pinned: true)])
    #expect(!rows[0].isPinned)
    #expect(rows[1].isPinned)
  }

  @Test("An empty store produces no rows")
  func empty() {
    #expect(MenuModel.rows(pads: []).isEmpty)
  }

  @Test("Row titles carry the markers a reader needs")
  func titles() {
    let broken = pad("notes")
    let rows = MenuModel.rows(
      pads: [broken],
      faults: [broken.id: .contentMissing(broken.id)],
      sizes: [broken.id: 40 * 1_048_576],
      threshold: 1)
    let title = MenuRowLabel.text(for: rows[0])
    #expect(title.contains("notes"))
    #expect(title.contains("unreadable"))
    #expect(title.contains("40 MB"))
  }
}

@Suite("Menu row labels")
struct MenuRowLabelTests {
  private func row(
    name: String = "scratch",
    faulted: Bool = false,
    pinned: Bool = false,
    marker: String? = nil,
    key: String? = "1",
    written: Bool = false
  ) -> MenuRow {
    MenuRow(
      id: PadID(), slot: 1, name: name, mode: .styled, isPinned: pinned,
      isFaulted: faulted, sizeMarker: marker, keyEquivalent: key,
      hasUnseenExternalWrite: written)
  }

  @Test("An ordinary row is just its name")
  func plainTitle() {
    #expect(MenuRowLabel.text(for: row()) == "scratch")
  }

  @Test("A faulted row says so, because the pad opens onto the fault")
  func faultedTitle() {
    #expect(MenuRowLabel.text(for: row(faulted: true)).contains("unreadable"))
  }

  @Test("A pinned row is marked")
  func pinnedTitle() {
    #expect(MenuRowLabel.text(for: row(pinned: true)).hasPrefix("📌"))
  }

  @Test("A size marker is appended rather than replacing the name")
  func sizeTitle() {
    let title = MenuRowLabel.text(for: row(marker: "48 MB"))
    #expect(title.contains("scratch"))
    #expect(title.contains("48 MB"))
  }

  @Test("Rows with a key equivalent get that key")
  func shortcut() {
    #expect(MenuRowLabel.shortcut(for: row(key: "3")) == KeyEquivalent("3"))
  }

  @Test("Rows beyond the ninth fall back rather than colliding on a key")
  func noShortcut() {
    #expect(MenuRowLabel.shortcut(for: row(key: nil)) == .space)
  }

  /// `FR-8.9`, §11.7: a write to a closed pad has no undo, so the menu — where
  /// the person will next look at the pad — is where it has to say so.
  @Test("A pad written while it was closed is marked in the menu")
  func writtenTitle() {
    #expect(MenuRowLabel.text(for: row(written: true)).contains("written"))
    #expect(MenuRowLabel.text(for: row()).contains("written") == false)
  }
}
