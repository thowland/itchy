import Foundation
import Testing

@testable import ItchyCore

@Suite("MCP endpoint and port bounds")
struct EndpointStoreTests {
  @Test("The default port is the one §11.1's decision settled on")
  func defaultPort() {
    #expect(MCPBounds.defaultPort == 8899)
    #expect(AppSettings().mcpPort == 8899)
  }

  @Test("The server is off in a fresh install")
  func offByDefault() {
    #expect(AppSettings().mcpServerEnabled == false)
  }

  @Test("Zero stays zero, because it means any free port")
  func ephemeralRequestSurvives() {
    #expect(MCPBounds.clamp(0) == 0)
  }

  @Test("A privileged port an accessory application cannot bind takes the default")
  func privilegedPortRefused() {
    #expect(MCPBounds.clamp(80) == MCPBounds.defaultPort)
    #expect(MCPBounds.clamp(1_023) == MCPBounds.defaultPort)
    #expect(MCPBounds.clamp(1_024) == 1_024)
  }

  @Test("A port beyond the sixteen-bit range is clamped to it")
  func aboveRange() {
    #expect(MCPBounds.clamp(99_999) == MCPBounds.maximumPort)
  }

  @Test("A hand-edited port out of range is corrected on the read path")
  func clampedOnLoad() throws {
    let root = TemporaryRoot()
    let store = SettingsStore(layout: root.layout)
    var settings = AppSettings()
    settings.mcpPort = 42
    try store.save(settings)

    #expect(store.load().mcpPort == MCPBounds.defaultPort)
  }

  @Test("Enabling and the port survive a round trip through disk")
  func settingsRoundTrip() throws {
    let root = TemporaryRoot()
    let store = SettingsStore(layout: root.layout)
    var settings = AppSettings()
    settings.mcpServerEnabled = true
    settings.mcpPort = 9_001
    try store.save(settings)

    #expect(store.load().mcpServerEnabled)
    #expect(store.load().mcpPort == 9_001)
  }

  /// The fields were added after R1, and a settings file written by an earlier
  /// build has neither. `AppSettings` decodes tolerantly for exactly this
  /// reason, and the consequence of getting it wrong is that every existing
  /// user's preferences are silently discarded.
  @Test("A settings file from before the server existed still loads")
  func toleratesOlderFile() throws {
    let root = TemporaryRoot()
    let store = SettingsStore(layout: root.layout)
    let older = #"{"schemaVersion":1,"padLimit":7,"defaultMode":"plain","launchesAtLogin":false}"#
    try FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: true)
    try Data(older.utf8).write(to: root.layout.settingsFile)

    let loaded = store.load()
    #expect(loaded.padLimit == 7)
    #expect(loaded.mcpServerEnabled == false)
    #expect(loaded.mcpPort == MCPBounds.defaultPort)
  }

  @Test("There is no endpoint file until the listener has bound")
  func absentEndpoint() {
    let root = TemporaryRoot()
    #expect(EndpointStore(layout: root.layout).read() == nil)
  }

  @Test("The endpoint round-trips, carrying the bound port")
  func endpointRoundTrip() throws {
    let root = TemporaryRoot()
    let store = EndpointStore(layout: root.layout)
    let endpoint = MCPEndpoint(
      port: 51_234, processIdentifier: 4_242, startedAt: FixedClock().instant)

    try store.write(endpoint)

    #expect(store.read() == endpoint)
    #expect(endpoint.url == "http://127.0.0.1:51234/mcp")
  }

  /// A stale port outlives the listener and the shim connects to nothing.
  @Test("Clearing removes the file, and clearing twice is not a failure")
  func clearing() throws {
    let root = TemporaryRoot()
    let store = EndpointStore(layout: root.layout)
    try store.write(MCPEndpoint(port: 1, processIdentifier: 2, startedAt: Date()))

    store.clear()
    store.clear()

    #expect(store.read() == nil)
    #expect(FileManager.default.fileExists(atPath: root.layout.endpointFile.path) == false)
  }

  @Test("An endpoint file full of nonsense reads as no endpoint at all")
  func unreadableEndpoint() throws {
    let root = TemporaryRoot()
    try Data("not json".utf8).write(to: root.layout.endpointFile)
    #expect(EndpointStore(layout: root.layout).read() == nil)
  }
}
