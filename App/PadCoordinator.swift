import AppKit
import ItchyCore
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

  @ObservationIgnored private let store: PadStore
  @ObservationIgnored internal lazy var registry = PadWindowRegistry(store: store)
  @ObservationIgnored private var sizes: [PadID: Int] = [:]
  @ObservationIgnored private var editors: [PadID: PadTextCoordinator] = [:]
  @ObservationIgnored private lazy var settingsStore = SettingsStore(layout: layout)
  @ObservationIgnored internal let hotKey = GlobalHotKey()
  @ObservationIgnored internal let signposter = LaunchSignposter()
  @ObservationIgnored private var welcome: WelcomeWindowController?
  @ObservationIgnored internal let layout: PadStorageLayout

  @ObservationIgnored internal let launchOptions: LaunchOptions

  init(
    store: PadStore,
    layout: PadStorageLayout,
    launchOptions: LaunchOptions = .current
  ) {
    self.store = store
    self.layout = layout
    self.launchOptions = launchOptions
  }

  /// Reads the index and metadata, then starts observing. Content is not read
  /// (`FR-1.6`).
  func start() async {
    let launch = signposter.beginLaunch()
    settings = settingsStore.load()
    registerHotKey()
    reconcileLoginItem()
    await store.load(padLimit: settings.padLimit)
    await refreshFaults()
    await refresh()
    signposter.endLaunch(launch)
    // After the launch interval closes: a backup must not count against the
    // budget in NFR-1.1, and nothing depends on it having finished.
    archiveIfNeeded(trigger: .launch)
    archiveIfNeeded(trigger: settings.archivesDaily ? .daily : .launch)
    await reopenPinnedPads()
    showWelcomeIfNeeded()
    if launchOptions.opensPadOnLaunch {
      await openFirstPadForTesting()
    }
    PreviousAppTracker.shared.start()
    Task { [weak self] in
      guard let self else { return }
      for await _ in await store.changes {
        await self.refreshFaults()
        await self.refresh()
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
    self.rows = MenuModel.rows(pads: pads, faults: faults, sizes: sizes)
  }

  /// Says once where to look, because an accessory application with no Dock
  /// icon and no window otherwise starts silently. The decision is
  /// `FirstRunPolicy`'s.
  func showWelcomeIfNeeded() {
    guard FirstRunPolicy.shouldShowWelcome(settings: settings, launchOptions: launchOptions)
    else { return }
    let controller = WelcomeWindowController { [weak self] in
      self?.completeFirstRun()
    }
    welcome = controller
    controller.show()
  }

  private func completeFirstRun() {
    settings.hasCompletedFirstRun = true
    persistSettings()
    welcome = nil
  }

  var isShowingWelcome: Bool { welcome?.isVisible ?? false }

  /// Closes the welcome window. Exactly what its button does, reachable without
  /// a mouse so the flow can be tested.
  func dismissWelcome() {
    welcome?.dismiss()
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
  private func openPad(_ padID: PadID, makingKey: Bool) async {
    guard let pad = pads.first(where: { $0.id == padID }) else { return }
    let fault = await store.fault(for: padID)
    let content = try? await store.content(of: padID)
    let initial = content.flatMap { try? ContentCodec.decode($0) } ?? NSAttributedString()
    let editor = editorCoordinator(for: padID)

    registry.show(
      pad,
      content: PadPanelContent(
        pad: pad,
        editor: editor,
        initial: initial,
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

  /// `FR-2.3`: creation requires no input and the pad is immediately ready to
  /// accept typing — so it opens, focused, rather than only appearing in a list
  /// the user then has to go and click.
  func createPad() {
    Task { [weak self] in
      guard let self else { return }
      guard let created = try? await self.store.createPad(name: nil) else { return }
      try? await self.store.setMode(created.id, to: self.settings.defaultMode)
      await self.refresh()
      await self.openPad(created.id, makingKey: true)
    }
  }

  func rename(_ padID: PadID, to name: String) {
    Task { [weak self] in
      guard let self else { return }
      try? await self.store.rename(padID, to: name)
      await self.refresh()
    }
  }

  func setPinned(_ padID: PadID, _ pinned: Bool) {
    Task { [weak self] in
      guard let self else { return }
      try? await self.store.setPinned(padID, pinned)
      await self.refresh()
    }
  }

  /// `FR-2.6`: deletion is the one destructive action, and the only place a
  /// confirmation is shown. The dialogue is in `PadsWindowView`; this is what it
  /// calls once the user has said yes.
  func deletePad(_ padID: PadID) {
    Task { [weak self] in
      guard let self else { return }
      self.registry.close(padID)
      self.editors[padID] = nil
      try? await self.store.deletePad(padID)
      await self.refresh()
    }
  }

  /// `FR-2.6`: emptying is a single action and, while the panel is open, one
  /// undo restores the content exactly.
  func emptyPad(_ padID: PadID) {
    Task { [weak self] in
      guard let self else { return }
      guard let editor = self.editors[padID] else {
        try? await self.store.empty(padID)
        await self.refresh()
        return
      }
      editor.apply(NSAttributedString(), actionName: "Empty Pad")
    }
  }

  /// `FR-4.9`: copying a pad's entire contents as plain text is a single action.
  func copyAsPlainText(_ padID: PadID) {
    Task { [weak self] in
      guard let self else { return }
      guard let content = try? await self.store.content(of: padID) else { return }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(content.plainText, forType: .string)
    }
  }

  func reorder(from source: IndexSet, to destination: Int) {
    var order = pads.map(\.id)
    order.move(fromOffsets: source, toOffset: destination)
    Task { [weak self] in
      guard let self else { return }
      try? await self.store.reorder(to: order)
      await self.refresh()
    }
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

  func flushOnTermination() {
    archiveOnTermination()
    let store = store
    let editors = Array(editors.values)
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
      for editor in editors {
        await editor.flush()
      }
      try? await store.flushAll()
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 2)
  }

  /// Taken before the flush, so the archive holds what was last written rather
  /// than a half-saved state — and after it the live store is current anyway.
  private func archiveOnTermination() {
    archiveIfNeeded(trigger: .quit)
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
