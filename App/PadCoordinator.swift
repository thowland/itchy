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

  @ObservationIgnored private let store: PadStore
  @ObservationIgnored private lazy var registry = PadWindowRegistry(store: store)
  @ObservationIgnored private var sizes: [PadID: Int] = [:]
  @ObservationIgnored private var editors: [PadID: PadTextCoordinator] = [:]

  @ObservationIgnored private let launchOptions: LaunchOptions

  init(store: PadStore, launchOptions: LaunchOptions = .current) {
    self.store = store
    self.launchOptions = launchOptions
  }

  /// Reads the index and metadata, then starts observing. Content is not read
  /// (`FR-1.6`).
  func start() async {
    await store.load(padLimit: PadBounds.defaultCount)
    await refreshFaults()
    await refresh()
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
    self.pads = pads
    self.rows = MenuModel.rows(pads: pads, faults: faults, sizes: sizes)
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
      content: PadView(
        coordinator: editor,
        mode: pad.mode,
        initial: initial,
        segments: StatusBarModel.segments(for: pad, fault: fault)),
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

  func createPad() {
    Task { [weak self] in
      guard let self else { return }
      _ = try? await self.store.createPad(name: nil)
      await self.refresh()
    }
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

  var openPanelCount: Int { registry.openCount }

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
