import Foundation

/// Everything known about a pad except its content (specification §5.1, §6.2).
///
/// Content lives beside this rather than inside it, so that the menubar and the
/// settings window can be populated at launch without reading any pad's bytes
/// (`FR-1.6`, `NFR-1.1`).
public struct PadMetadata: Sendable, Codable, Equatable, Identifiable {
  public var schemaVersion: Int
  public var id: PadID
  public var name: String
  public var mode: PadMode
  public var created: Date
  public var modified: Date
  public var frame: PadFrame?
  public var isPinned: Bool
  public var provenance: [ProvenanceEntry]

  /// R3. Not exposed by default (`FR-8.7`); an unexposed pad is absent from
  /// `list_pads` and a direct read of it is refused.
  public var isExposedToMCP: Bool

  /// R4. Defaults to local-only (`FR-9.1`).
  public var routingPolicy: RoutingPolicy

  /// Drives the global hotkey's choice of target (`FR-1.4`).
  public var lastOpened: Date?

  /// R3. Set on every non-user write (`FR-8.9`).
  public var externalWriteMarker: ExternalWriteMarker?

  public init(
    schemaVersion: Int = ItchyCore.schemaVersion,
    id: PadID = PadID(),
    name: String,
    mode: PadMode = .styled,
    created: Date,
    modified: Date,
    frame: PadFrame? = nil,
    isPinned: Bool = false,
    provenance: [ProvenanceEntry] = [],
    isExposedToMCP: Bool = false,
    routingPolicy: RoutingPolicy = .default,
    lastOpened: Date? = nil,
    externalWriteMarker: ExternalWriteMarker? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.name = name
    self.mode = mode
    self.created = created
    self.modified = modified
    self.frame = frame
    self.isPinned = isPinned
    self.provenance = provenance
    self.isExposedToMCP = isExposedToMCP
    self.routingPolicy = routingPolicy
    self.lastOpened = lastOpened
    self.externalWriteMarker = externalWriteMarker
  }

  /// A new pad, requiring no input from the user (`FR-2.3`).
  public static func newPad(
    id: PadID = PadID(),
    name: String,
    mode: PadMode = .styled,
    now: Date
  ) -> PadMetadata {
    PadMetadata(id: id, name: name, mode: mode, created: now, modified: now)
  }
}
