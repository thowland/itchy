import Foundation

/// The store. Owns all pad state and is the sole owner of disk access (`CON-4`).
///
/// An actor, so every mutation is an `await` from the caller's perspective and
/// two concurrent writers — the user and an agent — cannot interleave without a
/// locking scheme (`FR-8.8`).
public actor PadStore: PadStoring {
  /// Pad size at which the menubar marks the pad (`FR-5.9`, specification §9.4).
  public static let sizeMarkerThreshold = 32 * 1024 * 1024

  /// How long an orphaned temporary must be before a sweep removes it.
  public static let temporarySweepAge: TimeInterval = 3600

  internal let layout: PadStorageLayout
  internal let fileSystem: any FileSystemOperations
  internal let atomic: AtomicWrite
  internal let scheduler: SaveScheduler
  internal let migrator: SchemaMigrator
  internal let now: @Sendable () -> Date

  internal var order: [PadID] = []
  internal var metadata: [PadID: PadMetadata] = [:]
  internal var preserved: [PadID: [String: JSONValue]] = [:]
  internal var cachedContent: [PadID: PadContent] = [:]
  internal var dirty: Set<PadID> = []
  internal var recordedFaults: [PadID: PadStoreFault] = [:]
  internal var markedOversize: Set<PadID> = []
  internal var limit: Int = PadBounds.defaultCount
  internal var lastOpened: PadID?

  internal let continuation: AsyncStream<PadChange>.Continuation
  public let changes: AsyncStream<PadChange>

  public init(
    layout: PadStorageLayout,
    fileSystem: any FileSystemOperations = LocalFileSystem(),
    scheduler: SaveScheduler = SaveScheduler(),
    migrator: SchemaMigrator = SchemaMigrator(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.layout = layout
    self.fileSystem = fileSystem
    self.atomic = AtomicWrite(fileSystem: fileSystem)
    self.scheduler = scheduler
    self.migrator = migrator
    self.now = now
    let (stream, continuation) = AsyncStream<PadChange>.makeStream()
    self.changes = stream
    self.continuation = continuation
  }

  // MARK: - Observation

  public var pads: [PadMetadata] {
    order.compactMap { metadata[$0] }
  }

  public var faults: [PadID: PadStoreFault] {
    recordedFaults
  }

  public var padLimit: Int {
    limit
  }

  public var lastOpenedPad: PadID? {
    lastOpened
  }

  // MARK: - Faults

  internal func record(_ fault: PadStoreFault, for id: PadID?) {
    if let id { recordedFaults[id] = fault }
    continuation.yield(.storeFault(id, fault))
  }

  /// Whether a pad may be opened for editing.
  ///
  /// False means the content could not be read, and the interface must present
  /// the pad as faulted. An empty editable pad over unreadable content would
  /// destroy that content on the next save, which specification §6.7 prohibits.
  public func isEditable(_ id: PadID) -> Bool {
    guard metadata[id] != nil else { return false }
    guard let fault = recordedFaults[id] else { return true }
    return !fault.prohibitsEditing
  }

  public func fault(for id: PadID) -> PadStoreFault? {
    recordedFaults[id]
  }

  public func hasPendingWrite(_ id: PadID) async -> Bool {
    await scheduler.isPending(id)
  }

  public func isDirty(_ id: PadID) -> Bool {
    dirty.contains(id)
  }
}
