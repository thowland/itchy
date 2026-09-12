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
    guard let pad = pads.first(where: { $0.id == padID }) else { return }
    let fault = faultForDisplay(padID)
    registry.show(
      pad,
      content: PadView(segments: StatusBarModel.segments(for: pad, fault: fault)),
      makingKey: makingKey)
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
  func flushOnTermination() {
    let store = store
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
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
