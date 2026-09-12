import Foundation
import Testing

@testable import ItchyCore

@Suite("Settings")
struct SettingsStoreTests {
  @Test("Defaults are the documented ones")
  func defaults() {
    let settings = AppSettings()
    #expect(settings.padLimit == PadBounds.defaultCount)
    #expect(settings.defaultMode == .styled)
    #expect(settings.launchesAtLogin)
  }

  @Test("An absent settings file yields defaults rather than a failure")
  func absentFile() {
    let root = TemporaryRoot()
    let store = SettingsStore(layout: root.layout)
    #expect(store.load() == AppSettings())
  }

  @Test("Settings round-trip through disk")
  func roundTrip() throws {
    let root = TemporaryRoot()
    let store = SettingsStore(layout: root.layout)
    var settings = AppSettings()
    settings.padLimit = 12
    settings.defaultMode = .plain
    settings.launchesAtLogin = false

    try store.save(settings)

    #expect(store.load() == settings)
  }

  /// `FR-2.1`: the read path is one of the three enforcement points, and its
  /// acceptance criterion specifically includes a hand-edited stored value.
  @Test("A stored limit above the ceiling is clamped and written back")
  func clampsOnRead() throws {
    let root = TemporaryRoot()
    let store = SettingsStore(layout: root.layout)
    let handEdited = """
      {"schemaVersion":1,"padLimit":9999,"defaultMode":"styled","launchesAtLogin":true}
      """
    try Data(handEdited.utf8).write(to: root.layout.settingsFile)

    let loaded = store.load()

    #expect(loaded.padLimit == PadBounds.hardCeiling)

    // And the file no longer claims otherwise.
    let onDisk = try JSONCoding.decoder()
      .decode(AppSettings.self, from: try Data(contentsOf: root.layout.settingsFile))
    #expect(onDisk.padLimit == PadBounds.hardCeiling)
  }

  @Test("A limit below one is clamped up")
  func clampsLow() throws {
    let root = TemporaryRoot()
    let store = SettingsStore(layout: root.layout)
    var settings = AppSettings()
    settings.padLimit = -4
    try store.save(settings)
    #expect(store.load().padLimit == PadBounds.minimumCount)
  }

  /// `NFR-2.2`: losing a preference is recoverable, refusing to start is not.
  @Test("An unreadable settings file falls back to defaults")
  func unreadableFile() throws {
    let root = TemporaryRoot()
    try Data("{ not json".utf8).write(to: root.layout.settingsFile)
    #expect(SettingsStore(layout: root.layout).load() == AppSettings())
  }

  @Test("Saving clamps too, so an out-of-range value cannot be written at all")
  func saveClamps() throws {
    let root = TemporaryRoot()
    let store = SettingsStore(layout: root.layout)
    var settings = AppSettings()
    settings.padLimit = 500
    try store.save(settings)
    #expect(store.load().padLimit == PadBounds.hardCeiling)
  }

  @Test(
    "needsRewrite reports exactly when a value was out of range",
    arguments: [(9, false), (20, false), (21, true), (0, true)])
  func needsRewrite(limit: Int, expected: Bool) {
    var settings = AppSettings()
    settings.padLimit = limit
    #expect(settings.needsRewrite == expected)
  }
}
