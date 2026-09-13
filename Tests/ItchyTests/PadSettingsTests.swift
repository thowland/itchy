import AppKit
import Foundation
import ItchyCore
import Testing

@testable import Itchy

/// D-21: a pad's own settings.
@Suite("Pad settings model")
struct PadSettingsModelTests {
  private func pad(_ name: String) -> PadMetadata {
    PadMetadata(name: name, created: .distantPast, modified: .distantPast)
  }

  @Test("A draft name is trimmed, and an empty or unchanged one renames nothing")
  func nameChange() {
    #expect(PadSettingsModel.nameChange(draft: "  json  ", current: "scratch") == .rename("json"))
    #expect(PadSettingsModel.nameChange(draft: "   ", current: "scratch") == .unchanged)
    #expect(PadSettingsModel.nameChange(draft: "scratch ", current: "scratch") == .unchanged)
  }

  @Test("An empty name is explained rather than saved (FR-2.4)")
  func emptyNotice() {
    let own = pad("scratch")
    let notice = PadSettingsModel.notice(draft: " ", padID: own.id, pads: [own])
    #expect(notice?.contains("always has a name") == true)
  }

  /// An agent resolves names case-insensitively (specification §11.5), so that
  /// is the comparison that matters.
  @Test("A name another pad has, in any case, is pointed out")
  func duplicateNotice() {
    let own = pad("scratch")
    let other = pad("JSON")
    let notice = PadSettingsModel.notice(draft: "json", padID: own.id, pads: [own, other])
    #expect(notice?.contains("also called") == true)
    #expect(notice?.contains("agent") == true)
  }

  @Test("A pad's own name, or a unique one, needs no notice")
  func noNotice() {
    let own = pad("scratch")
    let other = pad("json")
    #expect(PadSettingsModel.notice(draft: "scratch", padID: own.id, pads: [own, other]) == nil)
    #expect(PadSettingsModel.notice(draft: "sql", padID: own.id, pads: [own, other]) == nil)
  }

  @Test("The sheet names the pad it belongs to")
  func title() {
    #expect(PadSettingsModel.title(for: pad("json")) == "Settings for “json”")
  }
}

@MainActor
@Suite("Pad settings through the coordinator")
struct PadSettingsIntegrationTests {
  private func makeCoordinator() async throws -> (PadCoordinator, PadMetadata, URL) {
    let root = URL.temporaryDirectory.appendingPathComponent("itchy-padsettings-\(UUID().uuidString)")
    let layout = PadStorageLayout(root: root)
    let store = PadStore(layout: layout)
    await store.load()
    let pad = try await store.createPad(name: "scratch")
    let coordinator = PadCoordinator(store: store, layout: layout, launchOptions: LaunchOptions())
    await coordinator.refresh()
    return (coordinator, pad, root)
  }

  @Test("A name from the sheet is trimmed and saved")
  func rename() async throws {
    let (coordinator, pad, root) = try await makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.applyName("  json  ", to: pad.id)

    await expect("the rename to land") { coordinator.pads.first?.name == "json" }
  }

  @Test("An empty name keeps the current one")
  func emptyName() async throws {
    let (coordinator, pad, root) = try await makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.applyName("", to: pad.id)
    await coordinator.refresh()

    #expect(coordinator.pads.first?.name == "scratch")
  }

  /// A panel is built with the metadata of the moment it opened.
  @Test("An open panel sees the pad as it is now, not as it was when opened")
  func liveMetadata() async throws {
    let (coordinator, pad, root) = try await makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.setMode(pad.id, to: .plain)

    await expect("the mode change to land") { coordinator.metadata(for: pad).mode == .plain }
    #expect(pad.mode == .styled, "the snapshot the panel was built with")
  }

  @Test("Renaming an open pad retitles its panel")
  func retitles() async throws {
    let (coordinator, pad, root) = try await makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    coordinator.open(pad.id, makingKey: false)
    await expect("the panel to open") { coordinator.registry.controller(for: pad.id) != nil }
    defer { coordinator.close(pad.id) }

    coordinator.applyName("json", to: pad.id)

    await expect("the title to change") {
      coordinator.registry.controller(for: pad.id)?.panel.title == "json"
    }
  }
}
