import Foundation
import ItchyCore

/// Builds the store against the storage location the launch options ask for.
///
/// The UI suite runs against a throwaway root, because a test that creates and
/// deletes pads must never be pointed at the user's real ones.
enum AppStorage {
  static func makeStore(options: LaunchOptions = .current) -> PadStore {
    PadStore(layout: layout(options: options))
  }

  static func layout(options: LaunchOptions) -> PadStorageLayout {
    guard !options.usesTemporaryStorage else {
      return PadStorageLayout.at(path: NSTemporaryDirectory() + "ItchyUITests")
    }
    return (try? PadStorageLayout.standard())
      ?? PadStorageLayout.at(path: NSTemporaryDirectory() + "Itchy")
  }
}
