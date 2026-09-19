import AppKit
import ItchyCore
import ItchyServices
import Testing

@testable import Itchy

/// `FR-8.10` end to end: nothing is listening on a fresh store, enabling starts
/// the server and disabling stops it, both without a relaunch — and
/// `endpoint.json` appears and disappears with it (§11.1).
@MainActor
@Suite("The agent server through the coordinator")
struct AgentServerIntegrationTests {
  /// The token store is in memory, always. A test that reached for the real
  /// Keychain would stop and ask the person running it for permission, which is
  /// a hang here and an impossibility on CI.
  private func makeCoordinator()
    -> (PadCoordinator, PadStorageLayout, URL, any MCPTokenStore) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-agents-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let layout = PadStorageLayout(root: root)
    let tokens = InMemoryTokenStore()
    let coordinator = PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions(),
      tokenStore: tokens)
    // An ephemeral port, so the suite neither collides with a running Itchy nor
    // with another test.
    coordinator.settings.mcpPort = 0
    return (coordinator, layout, root, tokens)
  }

  private func endpoint(_ layout: PadStorageLayout) -> MCPEndpoint? {
    EndpointStore(layout: layout).read()
  }

  @Test("A fresh store has nothing listening and no endpoint file")
  func offByDefault() async {
    let (coordinator, layout, root, _) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.startServerIfEnabled()

    #expect(coordinator.serverState == .off)
    #expect(endpoint(layout) == nil)
    #expect(MenuModel.serverRow(coordinator.serverState) == nil)
  }

  @Test("Enabling starts the listener and records the bound port")
  func enabling() async throws {
    let (coordinator, layout, root, _) = makeCoordinator()
    defer {
      coordinator.setMCPEnabled(false)
      try? FileManager.default.removeItem(at: root)
    }

    coordinator.setMCPEnabled(true)
    await expect("the server to be listening") { coordinator.serverState.isListening }

    let port = try #require(coordinator.serverState.port)
    #expect(port > 0)
    let recorded = try #require(endpoint(layout))
    #expect(recorded.port == port)
    #expect(recorded.host == "127.0.0.1")
    #expect(recorded.processIdentifier == ProcessInfo.processInfo.processIdentifier)
    #expect(coordinator.settings.mcpServerEnabled)
  }

  /// A stale port outlives the listener and the shim connects to nothing.
  @Test("Disabling stops the listener and removes the endpoint file")
  func disabling() async throws {
    let (coordinator, layout, root, _) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.setMCPEnabled(true)
    await expect("the server to be listening") { coordinator.serverState.isListening }

    coordinator.setMCPEnabled(false)
    await expect("the server to be off") { coordinator.serverState == .off }

    #expect(endpoint(layout) == nil)
    #expect(coordinator.settings.mcpServerEnabled == false)
  }

  @Test("A token exists once the server has been switched on, and survives a restart")
  func tokenIsGenerated() async throws {
    let (coordinator, _, root, tokens) = makeCoordinator()
    defer {
      coordinator.setMCPEnabled(false)
      try? FileManager.default.removeItem(at: root)
    }

    coordinator.setMCPEnabled(true)
    await expect("the server to be listening") { coordinator.serverState.isListening }

    let first = try #require(coordinator.mcpToken)
    #expect(first.value.isEmpty == false)
    #expect(try tokens.load()?.value == first.value)

    coordinator.setMCPEnabled(false)
    await expect("the server to be off") { coordinator.serverState == .off }
    coordinator.setMCPEnabled(true)
    await expect("the server to be listening again") { coordinator.serverState.isListening }

    #expect(coordinator.mcpToken?.value == first.value)
  }

  /// `FR-8.4`. The Keychain item is replaced, not updated, so that a failed
  /// write cannot leave the old token working.
  @Test("Regenerating replaces the token everywhere at once")
  func regeneration() async throws {
    let (coordinator, _, root, tokens) = makeCoordinator()
    defer {
      coordinator.setMCPEnabled(false)
      try? FileManager.default.removeItem(at: root)
    }

    coordinator.setMCPEnabled(true)
    await expect("the server to be listening") { coordinator.serverState.isListening }
    let previous = try #require(coordinator.mcpToken)

    coordinator.regenerateMCPToken()

    let current = try #require(coordinator.mcpToken)
    #expect(current.value != previous.value)
    #expect(try tokens.load()?.value == current.value)
  }

  @Test("Quitting takes the endpoint file with it")
  func terminationClearsTheEndpoint() async throws {
    let (coordinator, layout, root, _) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.setMCPEnabled(true)
    await expect("the server to be listening") { coordinator.serverState.isListening }
    #expect(endpoint(layout) != nil)

    await coordinator.prepareForTermination(limit: .milliseconds(500))

    #expect(endpoint(layout) == nil)
    #expect(coordinator.serverState == .off)
  }

  /// A run that was killed rather than quit leaves a port behind. Launching
  /// with the server off must not leave it there to be connected to.
  @Test("A stale endpoint file from a killed run is cleared at launch")
  func staleEndpointCleared() async throws {
    let (coordinator, layout, root, _) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    try EndpointStore(layout: layout).write(
      MCPEndpoint(port: 8_899, processIdentifier: 1, startedAt: Date()))

    coordinator.startServerIfEnabled()

    #expect(endpoint(layout) == nil)
  }
}
