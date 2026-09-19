import Foundation
import ItchyCore

/// What a pad looks like to an agent in `list_pads`.
public struct PadSummary: Sendable, Equatable, Codable {
  public let id: String
  public let name: String
  public let uri: String
  public let characters: Int
  public let modified: Date
}

/// What executing an operation produced.
public enum MCPResult: Sendable, Equatable {
  case padList([PadSummary])
  case text(String)
  case created(PadSummary)
}

/// Applies an agent's write to a pad.
///
/// A seam, because §11.6 makes the destination depend on something this layer
/// must not know about: a write goes through the open panel's grouped applier
/// when the pad is on screen, and to the store when it is not, so that an agent
/// write to an open pad is one undo from reverted (`FR-8.8`). Sprint 8 ships the
/// store-only implementation below; Sprint 9 supplies the registry-aware one
/// without this file changing.
public protocol PadContentWriter: Sendable {
  func write(_ text: String, to id: PadID, origin: WriteOrigin) async throws
  func append(_ text: String, to id: PadID, origin: WriteOrigin) async throws

  /// Whether this writer can reach a pad whose panel is open.
  ///
  /// False for the store-only writer, which is what makes `OpenPadPolicy`
  /// refuse a write that would otherwise be overwritten by the panel's next
  /// save. Sprint 9's registry-aware writer answers true and the refusal stops
  /// applying, with no other change.
  var reachesOpenPads: Bool { get }
}

/// The store-only writer. Correct whenever the pad's panel is closed, which in
/// Sprint 8 is the only case that can arise, because nothing exposes a pad
/// automatically and the server is off by default.
public struct StorePadWriter: PadContentWriter {
  private let store: PadStore

  public init(store: PadStore) {
    self.store = store
  }

  public var reachesOpenPads: Bool { false }

  public func write(_ text: String, to id: PadID, origin: WriteOrigin) async throws {
    await store.stage(PadContent.plainText(text), for: id, origin: origin)
  }

  public func append(_ text: String, to id: PadID, origin: WriteOrigin) async throws {
    let existing = try await store.content(of: id)
    await store.stage(
      PadContent.plainText(existing.plainText + text), for: id, origin: origin)
  }
}

/// Executes the operations the router produced (§11).
///
/// Holds no policy of its own. Which pads are visible is `ExposurePolicy`'s,
/// what a request means is `ToolRouter`'s, and where a write lands is the
/// writer's. This reads and mutates.
public actor MCPService {
  private let store: PadStore
  private let writer: any PadContentWriter
  private let presence: any PadPresence
  /// Named in the write origin so the external-write marker says who (§11.7).
  private let client: String

  public init(
    store: PadStore,
    writer: any PadContentWriter,
    presence: any PadPresence = NoPadsOpen(),
    client: String = "mcp"
  ) {
    self.store = store
    self.writer = writer
    self.presence = presence
    self.client = client
  }

  public func visiblePads() async -> [PadMetadata] {
    ExposurePolicy.visible(in: await store.pads)
  }

  public func execute(_ operation: MCPOperation) async throws -> MCPResult {
    switch operation {
    case .listPads:
      return .padList(await summaries())
    case .readPad(let id):
      return .text(try await store.content(of: id).plainText)
    case .appendPad(let id, let text):
      try await admit(id)
      try await writer.append(text, to: id, origin: origin)
      return .text("Appended \(text.count) characters.")
    case .writePad(let id, let text):
      try await admit(id)
      try await writer.write(text, to: id, origin: origin)
      return .text("Wrote \(text.count) characters.")
    case .createPad(let name, let text):
      return .created(try await create(name: name, text: text))
    }
  }

  /// A resource read, which reaches the same content by a different route
  /// (`FR-8.1`). It goes through the exposure check as a tool call does.
  public func readResource(uri: String) async throws -> String {
    guard let id = MCPToolSurface.padID(fromResourceURI: uri) else {
      throw MCPRoutingError.padNotFound(reference: uri)
    }
    guard await visiblePads().contains(where: { $0.id == id }) else {
      throw MCPRoutingError.padNotFound(reference: uri)
    }
    return try await store.content(of: id).plainText
  }

  /// Refuses rather than loses, when the writer cannot reach an open panel
  /// (§11.6). An honest refusal is something an agent can report; a success
  /// that did nothing is not.
  private func admit(_ id: PadID) async throws {
    let admission = OpenPadPolicy.admit(
      isOpen: await presence.isOpen(id), writerReachesOpenPads: writer.reachesOpenPads)
    guard admission == .refuseBecauseOpen else { return }
    throw MCPWriteRefusal.padOpenInInterface
  }

  private var origin: WriteOrigin { .mcp(client: client) }

  private func create(name: String?, text: String?) async throws -> PadSummary {
    let pad = try await store.createPad(name: name)
    // A pad an agent made is exposed to it; otherwise create_pad produces
    // something the caller cannot then read, which reads as a failure.
    try await store.setExposedToMCP(pad.id, true)
    if let text, !text.isEmpty {
      try await writer.write(text, to: pad.id, origin: origin)
    }
    return PadSummary(
      id: pad.id.description,
      name: pad.name,
      uri: MCPToolSurface.resourceURI(for: pad.id),
      characters: text?.count ?? 0,
      modified: pad.modified)
  }

  /// `characters` is the length of the text a read would return, not the size
  /// of the pad on disk.
  ///
  /// It was the directory's byte count until it was read back in a test, which
  /// for an RTFD bundle is several hundred bytes for a five-character pad. An
  /// agent deciding whether a pad is worth reading on that number would be
  /// deciding on the wrong one, and the field is called `characters`.
  ///
  /// This reads the content of each exposed pad, which is acceptable here and
  /// would not be at launch (`FR-1.6`): the caller has asked what is in the
  /// pads, the store caches what it reads, and there are at most twenty of them.
  private func summaries() async -> [PadSummary] {
    var result: [PadSummary] = []
    for pad in await visiblePads() {
      let text = try? await store.content(of: pad.id).plainText
      result.append(
        PadSummary(
          id: pad.id.description,
          name: pad.name,
          uri: MCPToolSurface.resourceURI(for: pad.id),
          characters: text?.count ?? 0,
          modified: pad.modified))
    }
    return result
  }
}
