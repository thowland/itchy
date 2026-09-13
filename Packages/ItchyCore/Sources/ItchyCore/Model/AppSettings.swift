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

  /// How many archives to keep. Zero disables archiving entirely (D-18).
  ///
  /// Archives hold copies of pad content, including pads the user has since
  /// deleted, so the number of them is the user's decision and turning it off
  /// has to be one of the available answers.
  public var archiveRetention: Int

  /// Take an archive once a day in addition to on launch and quit.
  public var archivesDaily: Bool

  /// When the last archive was taken, so the daily one knows whether it is due.
  public var lastArchiveAt: Date?

  /// The pads' state when the last archive was taken. An archive is skipped
  /// when this has not changed, so a day of restarts does not push the one
  /// useful snapshot off the end of the retention limit.
  public var lastArchiveFingerprint: String?

  /// Whether the welcome window has been shown and dismissed.
  ///
  /// An accessory application with no Dock icon and no window gives "I launched
  /// it and nothing happened" as its first experience, so it says once where to
  /// look. Once only — `CON-2` prohibits prompts, and this is the narrow
  /// exception of telling someone the application exists.
  public var hasCompletedFirstRun: Bool

  /// The editor font family, or `nil` for the built-in monospaced font (D-19).
  ///
  /// Held as a family name rather than a font, because the core links no UI
  /// framework (D-2) and a family name is what survives an OS update.
  public var editorFontFamily: String?

  /// The editor text size in points, clamped on every read (D-19).
  public var editorFontSize: Double

  /// Families previously chosen, most recent first, so that body text set in
  /// them is still recognised when a pad closed at the time is reopened (D-19).
  public var formerEditorFontFamilies: [String]

  public init(
    schemaVersion: Int = ItchyCore.schemaVersion,
    padLimit: Int = PadBounds.defaultCount,
    defaultMode: PadMode = .styled,
    launchesAtLogin: Bool = true,
    hotKeyCode: UInt32 = 49,
    hotKeyModifiers: UInt32 = 0x1000 | 0x0800,
    hasCompletedFirstRun: Bool = false,
    archiveRetention: Int = ArchiveBounds.defaultRetention,
    archivesDaily: Bool = true,
    lastArchiveAt: Date? = nil,
    lastArchiveFingerprint: String? = nil,
    editorFontFamily: String? = nil,
    editorFontSize: Double = EditorFontBounds.defaultSize,
    formerEditorFontFamilies: [String] = []
  ) {
    self.schemaVersion = schemaVersion
    self.padLimit = padLimit
    self.defaultMode = defaultMode
    self.launchesAtLogin = launchesAtLogin
    self.hotKeyCode = hotKeyCode
    self.hotKeyModifiers = hotKeyModifiers
    self.hasCompletedFirstRun = hasCompletedFirstRun
    self.archiveRetention = archiveRetention
    self.archivesDaily = archivesDaily
    self.lastArchiveAt = lastArchiveAt
    self.lastArchiveFingerprint = lastArchiveFingerprint
    self.editorFontFamily = editorFontFamily
    self.editorFontSize = editorFontSize
    self.formerEditorFontFamilies = formerEditorFontFamilies
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
    archiveRetention =
      try container.decodeIfPresent(Int.self, forKey: .archiveRetention)
      ?? fallback.archiveRetention
    archivesDaily =
      try container.decodeIfPresent(Bool.self, forKey: .archivesDaily) ?? fallback.archivesDaily
    lastArchiveAt = try container.decodeIfPresent(Date.self, forKey: .lastArchiveAt)
    lastArchiveFingerprint =
      try container.decodeIfPresent(String.self, forKey: .lastArchiveFingerprint)
    editorFontFamily = try container.decodeIfPresent(String.self, forKey: .editorFontFamily)
    editorFontSize =
      try container.decodeIfPresent(Double.self, forKey: .editorFontSize)
      ?? fallback.editorFontSize
    formerEditorFontFamilies =
      try container.decodeIfPresent([String].self, forKey: .formerEditorFontFamilies)
      ?? fallback.formerEditorFontFamilies
  }

  public func clamped() -> AppSettings {
    var result = self
    result.padLimit = PadBounds.clamp(padLimit)
    result.archiveRetention = ArchiveBounds.clamp(archiveRetention)
    result.editorFontSize = EditorFontBounds.clamp(editorFontSize)
    result.formerEditorFontFamilies = Array(
      formerEditorFontFamilies.prefix(EditorFontBounds.formerFamilyLimit))
    return result
  }

  public var needsRewrite: Bool {
    clamped() != self
  }
}
