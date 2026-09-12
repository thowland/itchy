import Foundation

/// Non-secret preferences, stored beside the pads (specification §6.1).
///
/// Secrets never appear here: the MCP token and model credentials live in the
/// Keychain (`NFR-3.3`), and this file is world-readable like everything else in
/// the support directory.
public struct AppSettings: Sendable, Codable, Equatable {
  public var schemaVersion: Int

  /// How many pads may exist. Configurable, and clamped to the ceiling on every
  /// read (`FR-2.1`).
  public var padLimit: Int

  /// The mode a newly created pad starts in (`FR-2.8`).
  public var defaultMode: PadMode

  /// R1, Sprint 5. Present from here so the settings file does not need a
  /// migration the moment the login item arrives.
  public var launchesAtLogin: Bool

  public init(
    schemaVersion: Int = ItchyCore.schemaVersion,
    padLimit: Int = PadBounds.defaultCount,
    defaultMode: PadMode = .styled,
    launchesAtLogin: Bool = true
  ) {
    self.schemaVersion = schemaVersion
    self.padLimit = padLimit
    self.defaultMode = defaultMode
    self.launchesAtLogin = launchesAtLogin
  }

  /// Returns settings with every value forced into its permitted range.
  ///
  /// `FR-2.1`'s acceptance criterion specifically includes a hand-edited stored
  /// value above the ceiling, so this runs on the read path and the result is
  /// written back.
  public func clamped() -> AppSettings {
    var result = self
    result.padLimit = PadBounds.clamp(padLimit)
    return result
  }

  public var needsRewrite: Bool {
    clamped() != self
  }
}
