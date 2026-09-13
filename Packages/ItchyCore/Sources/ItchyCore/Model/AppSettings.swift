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

  public var launchesAtLogin: Bool

  /// The global hotkey, stored as a key code and a Carbon modifier mask
  /// (`FR-1.4`, D-6). Held as opaque numbers here so that the core needs no
  /// Carbon dependency.
  public var hotKeyCode: UInt32
  public var hotKeyModifiers: UInt32

  /// Whether the welcome window has been shown and dismissed.
  ///
  /// An accessory application with no Dock icon and no window gives "I launched
  /// it and nothing happened" as its first experience, so it says once where to
  /// look. Once only — `CON-2` prohibits prompts, and this is the narrow
  /// exception of telling someone the application exists.
  public var hasCompletedFirstRun: Bool

  public init(
    schemaVersion: Int = ItchyCore.schemaVersion,
    padLimit: Int = PadBounds.defaultCount,
    defaultMode: PadMode = .styled,
    launchesAtLogin: Bool = true,
    hotKeyCode: UInt32 = 49,
    hotKeyModifiers: UInt32 = 0x1000 | 0x0800,
    hasCompletedFirstRun: Bool = false
  ) {
    self.schemaVersion = schemaVersion
    self.padLimit = padLimit
    self.defaultMode = defaultMode
    self.launchesAtLogin = launchesAtLogin
    self.hotKeyCode = hotKeyCode
    self.hotKeyModifiers = hotKeyModifiers
    self.hasCompletedFirstRun = hasCompletedFirstRun
  }

  /// Returns settings with every value forced into its permitted range.
  ///
  /// `FR-2.1`'s acceptance criterion specifically includes a hand-edited stored
  /// value above the ceiling, so this runs on the read path and the result is
  /// written back.
  /// Decodes tolerantly: any field absent from the file takes its default.
  ///
  /// Synthesised decoding treats a missing key as a hard failure, which means
  /// adding a property silently discards every existing user's settings —
  /// `SettingsStore.load` falls back to defaults and the file is rewritten
  /// without their choices. That happened once, when the hotkey fields were
  /// added in Sprint 5, and this is the fix. Pad metadata has the equivalent
  /// protection through `PreservingCodec` (`FR-5.7`); settings needed its own.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let fallback = AppSettings()
    schemaVersion =
      try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? fallback.schemaVersion
    padLimit = try container.decodeIfPresent(Int.self, forKey: .padLimit) ?? fallback.padLimit
    defaultMode =
      try container.decodeIfPresent(PadMode.self, forKey: .defaultMode) ?? fallback.defaultMode
    launchesAtLogin =
      try container.decodeIfPresent(Bool.self, forKey: .launchesAtLogin)
      ?? fallback.launchesAtLogin
    hotKeyCode =
      try container.decodeIfPresent(UInt32.self, forKey: .hotKeyCode) ?? fallback.hotKeyCode
    hotKeyModifiers =
      try container.decodeIfPresent(UInt32.self, forKey: .hotKeyModifiers)
      ?? fallback.hotKeyModifiers
    hasCompletedFirstRun =
      try container.decodeIfPresent(Bool.self, forKey: .hasCompletedFirstRun)
      ?? fallback.hasCompletedFirstRun
  }

  public func clamped() -> AppSettings {
    var result = self
    result.padLimit = PadBounds.clamp(padLimit)
    return result
  }

  public var needsRewrite: Bool {
    clamped() != self
  }
}
