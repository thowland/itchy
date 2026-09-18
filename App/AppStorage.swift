import Foundation
import ItchyCore

/// Builds the store against the storage location the launch options ask for.
///
/// The UI suite runs against a throwaway root, because a test that creates and
/// deletes pads must never be pointed at the user's real ones.
enum AppStorage {
  @MainActor
  static func makeCoordinator(options: LaunchOptions = .current) -> PadCoordinator {
    let resolved = layout(options: options)
    return PadCoordinator(
      store: PadStore(layout: resolved), layout: resolved, launchOptions: options)
  }

  static func makeStore(options: LaunchOptions = .current) -> PadStore {
    PadStore(layout: layout(options: options))
  }

  /// One directory per launch under the UI-test flag, so each case starts from
  /// an empty store. A shared one let text typed by one case turn up in the
  /// next, and whether it did depended on whether a save beat termination.
  /// Chosen once per process, so every store built in a launch agrees.
  static let uiTestRun = UUID().uuidString

  static func layout(options: LaunchOptions) -> PadStorageLayout {
    guard !options.usesTemporaryStorage else {
      return PadStorageLayout.at(
        path: options.storageRoot ?? NSTemporaryDirectory() + "ItchyUITests/" + uiTestRun)
    }
    return (try? PadStorageLayout.standard())
      ?? PadStorageLayout.at(path: NSTemporaryDirectory() + "Itchy")
  }
}
