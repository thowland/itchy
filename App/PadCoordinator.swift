import AppKit
import ItchyCore
import ItchyServices
import Observation
import SwiftUI

/// Bridges the store to the interface.
///
/// Holds no decisions of its own: rows come from `MenuModel`, frames from
/// `FrameResolver`, status segments from `StatusBarModel`. It exists to own the
/// store, mirror its state onto the main actor for SwiftUI, and turn interface
/// events into store calls.
@MainActor
@Observable
final class PadCoordinator {
  private(set) var rows: [MenuRow] = []
  private(set) var pads: [PadMetadata] = []
  /// Not `private(set)`: the hotkey and login-item extension in
  /// PadCoordinator+HotKey.swift writes to it, and Swift's access control does
  /// not reach across files for a setter.
  internal var settings = AppSettings()

  /// What the agent server is doing (`FR-8.10`). Observed, so the menubar and
  /// the settings section redraw when it starts, stops or fails.
  internal var serverState: MCPServerState = .off
  /// The bearer token, surfaced in settings (`FR-8.4`). Observed for the same
  /// reason: regenerating it must change what the window shows.
  internal var mcpToken: MCPToken?

  /// Internal rather than private: the MCP extension builds a service around it.
  @ObservationIgnored internal let store: PadStore
  @ObservationIgnored internal var mcpHost: MCPServerHost?
  @ObservationIgnored internal lazy var endpointStore = EndpointStore(layout: layout)
  /// Injected, so that no test and no throwaway launch can reach the real
  /// Keychain. Reading an item created by a differently-signed build prompts
  /// the person for permission, and a suite that waits for an answer is a suite
  /// that hangs — on this machine and, with nobody there at all, on CI.
  @ObservationIgnored internal let mcpKeychain: any MCPTokenStore
  /// `FR-9.5`. Injected for the same reason the MCP token store is: no test may
  /// open the real Keychain (D-26).
  @ObservationIgnored internal let modelCredentials: any MCPTokenStore
  /// Which external write the person has already dismissed the banner for,
  /// keyed by pad and identified by when it happened, so that the next write
  /// raises it again (`FR-8.9`).
  internal var dismissedBanners: [PadID: Date?] = [:]
  /// Which external write arrived while the pad's panel was open, and so has an
  /// undo on the text view's stack to offer.
  @ObservationIgnored internal var panelWasOpenFor: [PadID: Date?] = [:]
  @ObservationIgnored internal lazy var registry = PadWindowRegistry(store: store)
  /// Transient per-pad messages, which today means a transform that declined
  /// or failed (`FR-6.6`). Observed, so the status bar redraws when one lands.
  internal var notices: [PadID: String] = [:]
  @ObservationIgnored internal var noticeTasks: [PadID: Task<Void, Never>] = [:]
  @ObservationIgnored private var sizes: [PadID: Int] = [:]
  /// Internal rather than private so the editor-font extension can restyle
  /// open pads; see the note on `settings`.
  @ObservationIgnored internal var editors: [PadID: PadTextCoordinator] = [:]
  @ObservationIgnored private lazy var settingsStore = SettingsStore(layout: layout)
  @ObservationIgnored internal let hotKey = GlobalHotKey()
  @ObservationIgnored internal let signposter = LaunchSignposter()
  @ObservationIgnored internal var welcome: WelcomeWindowController?
  @ObservationIgnored internal var help: HelpWindowController?
  @ObservationIgnored internal lazy var settingsWindow = SettingsWindowController(coordinator: self)
  @ObservationIgnored internal let layout: PadStorageLayout

  @ObservationIgnored internal let launchOptions: LaunchOptions

  init(
    store: PadStore,
    layout: PadStorageLayout,
    launchOptions: LaunchOptions = .current,
    tokenStore: (any MCPTokenStore)? = nil,
    modelCredentials: (any MCPTokenStore)? = nil
  ) {
    self.store = store
    self.layout = layout
    self.launchOptions = launchOptions
    self.mcpKeychain = tokenStore ?? TokenStoreResolver.store(for: launchOptions)
    self.modelCredentials =
      modelCredentials ?? TokenStoreResolver.modelStore(for: launchOptions)
  }

  /// Reads the index and metadata, then starts observing. Content is not read
  /// (`FR-1.6`).
  func start() async {
    let launch = signposter.beginLaunch()
    settings = settingsStore.load()
    applyDebugLogging()
    registerHotKey()
    reconcileLoginItem()
    await store.load(padLimit: settings.padLimit)
    await refreshFaults()
    await refresh()
    signposter.endLaunch(launch)
    DebugLog.shared.record(
      .launched(version: AppVersion.current.marketing ?? "unknown", pads: pads.count))
    // After the store has loaded, and after the launch interval closes: an
    // agent connecting in the moment between binding and loading would be
    // told, truthfully but uselessly, that there are no pads — and binding a
    // socket must not count against the budget in NFR-1.1.
    startServerIfEnabled()
    // After the launch interval closes: a backup must not count against the
    // budget in NFR-1.1, and nothing depends on it having finished.
    archiveIfNeeded(trigger: .launch)
    // Only when it is actually wanted. This used to fall back to `.launch`,
    // which archived twice on every start; the second was always a no-op,
    // because the fingerprint had not changed since the first one a moment
    // earlier, but it said so twice in the log.
    if settings.archivesDaily {
      archiveIfNeeded(trigger: .daily)
    }
    await reopenPinnedPads()
    showWelcomeIfNeeded()
    if launchOptions.showsAboutOnLaunch {
      showAbout()
    }
    if launchOptions.showsSettingsOnLaunch {
      showSettings(tab: SettingsTab.named(launchOptions.settingsTab))
    }
    if launchOptions.showsHelpOnLaunch {
      showHelp()
    }
    if launchOptions.opensPadOnLaunch {
      await openFirstPadForTesting()
    }
    PreviousAppTracker.shared.start()
    Task { [weak self] in
      guard let self else { return }
      for await change in await store.changes {
        // Whether the panel was open is read *before* the refresh, because it
        // is what the banner needs in order to know whether there is an undo
        // to offer, and a panel that closes in between would answer wrongly.
        self.recordFault(in: change)
        let externallyWritten = ExternalWriteRouting.pad(in: change)
        let wasOpen = externallyWritten.map { self.registry.isOpen($0) } ?? false
        await self.refreshFaults()
        await self.refresh()
        if let externallyWritten {
          self.recordExternalWrite(externallyWritten, wasOpen: wasOpen)
        }
      }
    }
  }

  /// Opens a pad at launch under the UI-test flag, creating one if the throwaway
  /// store is empty.
  private func openFirstPadForTesting() async {
    if pads.isEmpty {
      _ = try? await store.createPad(name: "UI Test Pad")
      await refresh()
    }
    guard let first = pads.first else { return }
    // Opened without taking keyboard focus, which is also how a pinned pad is
    // restored: the panel must appear without activating the application.
    open(first.id, makingKey: false)
  }

  func refresh() async {
    let pads = await store.pads
    let faults = await store.faults
    self.sizes = await store.sizes()
    self.lastOpenedPad = await store.lastOpenedPad
    self.pads = pads
    self.rows = MenuModel.rows(
      pads: pads, faults: faults, sizes: sizes, openPads: registry.openPads)
  }

  /// `FR-2.7`: a pinned pad's panel is present after relaunch, at its stored
  /// frame — and without taking keyboard focus (D-14).
  private func reopenPinnedPads() async {
    for pad in pads where pad.isPinned {
      await openPad(pad.id, makingKey: false)
    }
  }

  func open(_ padID: PadID, makingKey: Bool = true) {
    Task { [weak self] in
      await self?.openPad(padID, makingKey: makingKey)
    }
  }

  /// Reads the pad's content — the first time it is read at all (`FR-1.6`) — and
  /// shows its panel.
  ///
  /// A pad whose content cannot be read opens onto its fault rather than onto an
  /// empty editor, which specification §6.7 prohibits because an empty editor
  /// would destroy the content on the next save.
  /// Internal rather than private: the lifecycle extension opens a pad it has
  /// just created, and Swift's access control does not reach across files for
  /// a private member.
  internal func openPad(_ padID: PadID, makingKey: Bool) async {
    guard let pad = pads.first(where: { $0.id == padID }) else { return }
    let fault = await store.fault(for: padID)
    let content = try? await store.content(of: padID)
    let decoded = content.flatMap { try? ContentCodec.decode($0) } ?? NSAttributedString()
    let initial = restyledForDisplay(decoded, mode: pad.mode)
    let editor = editorCoordinator(for: padID)

    registry.show(
      pad,
      content: PadPanelContent(
        pad: pad,
        editor: editor,
        initial: initial,
        font: editorFont,
        fault: fault,
        coordinator: self),
      makingKey: makingKey)
  }

  private func editorCoordinator(for padID: PadID) -> PadTextCoordinator {
    if let existing = editors[padID] { return existing }
    let created = PadTextCoordinator(padID: padID, store: store)
    editors[padID] = created
    return created
  }

  /// `FR-4.5`: flattening is one undoable operation, shared with the future
  /// `flatten` transform.
  func setMode(_ padID: PadID, to mode: PadMode) {
    Task { [weak self] in
      guard let self else { return }
      let current = self.pads.first { $0.id == padID }?.mode
      self.flattenIfDowngrading(padID, from: current, to: mode)
      try? await self.store.setMode(padID, to: mode)
      self.editors[padID]?.setMode(mode)
      await self.refresh()
    }
  }

  private func flattenIfDowngrading(_ padID: PadID, from current: PadMode?, to mode: PadMode) {
    guard current == .styled, mode == .plain else { return }
    editors[padID]?.flatten()
  }

  func setPadLimit(_ requested: Int) {
    settings.padLimit = SettingsModel.clampPadCount(requested)
    persistSettings()
    Task { [weak self] in
      guard let self else { return }
      await self.store.setPadLimit(self.settings.padLimit)
    }
  }

  func setDefaultMode(_ mode: PadMode) {
    settings.defaultMode = mode
    persistSettings()
  }

  /// The pad the hotkey would target, exposed so the store's record and the
  /// interface agree about it.
  /// The pad the hotkey would target. Read by the hotkey extension.
  @ObservationIgnored internal var lastOpenedPad: PadID?

  func refreshLastOpened() async {
    lastOpenedPad = await store.lastOpenedPad
  }

  internal func persistSettings() {
    try? settingsStore.save(settings)
  }

  /// Opens the pad's directory in Finder, which is what a faulted pad offers
  /// instead of an editor (specification §6.7).
  func revealInFinder(_ padID: PadID) {
    NSWorkspace.shared.activateFileViewerSelecting([layout.directory(for: padID)])
  }

  func close(_ padID: PadID) {
    registry.close(padID)
  }

  /// Blocks the main thread on a bounded flush at termination.
  ///
  /// Blocking the main thread is normally indefensible. At termination, with a
  /// timeout, losing a pad is worse (specification §6.6).
  /// Stages any unserialised edit before the store's own flush, so that content
  /// typed within the serialisation debounce is not lost (specification §9.3).
  func flushEditors() async {
    for editor in editors.values {
      await editor.flush()
    }
  }

  /// Every editor's unserialised edit, then the store. What quitting waits on
  /// (`prepareForTermination`).
  func flushEverything() async {
    await flushEditors()
    try? await store.flushAll()
  }

  var openPanelCount: Int { registry.openCount }

  /// The recorded fault for a pad, if any. Used by the panel to decide between
  /// the editor and the fault view (specification §6.7).
  func fault(for padID: PadID) async -> PadStoreFault? {
    await store.fault(for: padID)
  }

  private var cachedFaults: [PadID: PadStoreFault] = [:]

  private func faultForDisplay(_ padID: PadID) -> PadStoreFault? {
    cachedFaults[padID]
  }

  /// Refreshes the fault cache alongside the rows, so `open` does not have to
  /// await the store on the click path.
  func refreshFaults() async {
    cachedFaults = await store.faults
  }
}
