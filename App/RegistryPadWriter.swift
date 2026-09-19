import AppKit
import ItchyCore
import ItchyServices

/// Where an agent's write lands (`FR-8.8`, §11.6).
///
/// The seam `MCPService` has had since Sprint 8, now filled in. Which
/// destination a write takes depends on something the services layer must not
/// know about — whether the pad's panel is on screen — so the decision is made
/// here, where the window registry is, and the services layer only asks for the
/// write.
///
/// When the panel is open the write goes through `PadTextCoordinator`'s grouped
/// applier, so it is one undo from reverted and the panel's next save carries it
/// rather than overwriting it. When the panel is closed it goes to the store,
/// which is what `StorePadWriter` already did.
///
/// This is what removes the failure mode the write tools introduced in Sprint 8,
/// and `OpenPadPolicy`'s refusal stops applying because `reachesOpenPads` is now
/// true. The refusal remains in place for any writer that cannot say the same —
/// `itchyctl`'s, for one.
struct RegistryPadWriter: PadContentWriter {
  private let coordinator: @Sendable () -> PadCoordinator?
  private let fallback: StorePadWriter

  @MainActor
  init(coordinator: PadCoordinator, store: PadStore) {
    self.coordinator = { [weak coordinator] in MainActor.assumeIsolated { coordinator } }
    self.fallback = StorePadWriter(store: store)
  }

  var reachesOpenPads: Bool { true }

  func write(_ text: String, to id: PadID, origin: WriteOrigin) async throws {
    guard await applyToPanel(.replaceAll, text: text, to: id, origin: origin) else {
      try await fallback.write(text, to: id, origin: origin)
      return
    }
  }

  func append(_ text: String, to id: PadID, origin: WriteOrigin) async throws {
    guard await applyToPanel(.append, text: text, to: id, origin: origin) else {
      try await fallback.append(text, to: id, origin: origin)
      return
    }
  }

  private func applyToPanel(
    _ write: AgentWrite, text: String, to id: PadID, origin: WriteOrigin
  ) async -> Bool {
    guard let coordinator = await MainActor.run(resultType: PadCoordinator?.self, body: coordinator)
    else { return false }
    return await coordinator.applyAgentWrite(write, text: text, to: id, origin: origin)
  }
}
