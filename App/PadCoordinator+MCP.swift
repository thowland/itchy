import AppKit
import ItchyCore
import ItchyServices

/// Starting, stopping and configuring the agent server (`FR-8.4`, `FR-8.10`,
/// §11.1).
///
/// The coordinator owns the host because the host's lifetime is the
/// application's and its settings are the application's. It holds no policy of
/// its own: what the interface shows about the server is `MCPSettingsModel`'s
/// and `MenuModel`'s, and what the server does is the host's.
extension PadCoordinator {
  /// At launch. The server is off unless the person has said otherwise, and
  /// `FR-8.10`'s "off by default" is this line reading the setting rather than
  /// anything more elaborate.
  func startServerIfEnabled() {
    guard settings.mcpServerEnabled else {
      serverState = .off
      // A previous run that was killed rather than quit leaves a port behind.
      endpointStore.clear()
      return
    }
    Task { [weak self] in await self?.startServer() }
  }

  /// `FR-8.10`: enabling and disabling take effect without a relaunch.
  func setMCPEnabled(_ enabled: Bool) {
    settings.mcpServerEnabled = enabled
    persistSettings()
    Task { [weak self] in
      guard let self else { return }
      if enabled {
        await self.startServer()
      } else {
        await self.stopServer()
      }
    }
  }

  /// A port change restarts the listener, because a bound socket cannot be
  /// moved. Doing it silently is right: the person changed the port in order to
  /// be listening on it.
  func setMCPPort(_ requested: Int) {
    let port = MCPSettingsModel.clampPort(requested)
    guard port != settings.mcpPort else { return }
    settings.mcpPort = port
    persistSettings()
    guard settings.mcpServerEnabled else { return }
    Task { [weak self] in
      guard let self else { return }
      await self.stopServer()
      await self.startServer()
    }
  }

  /// `FR-8.4`: regeneration invalidates the previous token immediately.
  ///
  /// One step, in this order: the Keychain item is replaced — `save` deletes
  /// before adding, so a failed update cannot leave the old token working — and
  /// the listener's in-memory copy is replaced with it.
  func regenerateMCPToken() {
    let token = MCPToken.generate()
    try? mcpKeychain.save(token)
    mcpToken = token
    Task { [weak self] in
      guard let self, let host = self.mcpHost else { return }
      await host.replaceToken(with: token)
    }
  }

  func copyMCPTokenToPasteboard() {
    guard let value = mcpToken?.value else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }

  /// At quit, alongside the flush. The endpoint file must not outlive the
  /// process that wrote it.
  func shutDownServer() async {
    await stopServer()
  }

  // MARK: - The listener itself

  private func startServer() async {
    guard mcpHost == nil else { return }
    serverState = .starting
    let token = (try? mcpKeychain.loadOrCreate()) ?? MCPToken.generate()
    mcpToken = token

    let host = MCPServerHost(
      service: MCPService(
        store: store,
        writer: StorePadWriter(store: store),
        presence: PanelPresence(coordinator: self),
        client: "mcp"),
      token: token,
      port: settings.mcpPort,
      serverVersion: AppVersion.current.marketing ?? "0")
    do {
      let port = try await host.start()
      mcpHost = host
      serverState = .listening(port: port)
      // The bound port, not the configured one: asking for 8899 and getting it
      // is the common case, not a guarantee.
      try? endpointStore.write(
        MCPEndpoint(
          port: port,
          processIdentifier: ProcessInfo.processInfo.processIdentifier,
          startedAt: Date()))
    } catch {
      serverState = .failed(reason: ServerFailureText.of(error))
      endpointStore.clear()
    }
  }

  private func stopServer() async {
    let host = mcpHost
    mcpHost = nil
    await host?.stop()
    // Before the state changes, so that nothing reads "off" while a port file
    // still says otherwise.
    endpointStore.clear()
    serverState = .off
  }
}

/// What a failure to start says to the person (D-11).
///
/// A port that is taken is the failure that will actually happen, and "address
/// already in use" is not what it should say.
enum ServerFailureText {
  static func of(_ error: any Error) -> String {
    guard let listener = error as? LoopbackListener.ListenerError else {
      return "something unexpected went wrong."
    }
    switch listener {
    case .couldNotBind:
      return "that port is already in use by something else on this machine."
    case .invalidPort(let port):
      return "\(port) is not a port this can bind."
    case .notRunning:
      return "the listener stopped before it started."
    }
  }
}

/// Whether a pad's panel is on screen, answered from the window registry.
///
/// The seam §11.6 needs: `MCPService` must be able to refuse a write to an open
/// pad, and the answer lives on the main actor in a registry the services layer
/// must not know about.
struct PanelPresence: PadPresence {
  private let coordinator: @Sendable () -> PadCoordinator?

  @MainActor
  init(coordinator: PadCoordinator) {
    self.coordinator = { [weak coordinator] in MainActor.assumeIsolated { coordinator } }
  }

  func isOpen(_ id: PadID) async -> Bool {
    await MainActor.run { coordinator()?.registry.isOpen(id) ?? false }
  }
}
