import Foundation
import ItchyCore
import Testing

@testable import ItchyServices

/// The service against a real store, since what it mostly does is read and
/// mutate one.
@Suite("MCP service")
struct MCPServiceTests {
  private func makeStore() async -> (PadStore, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-mcp-\(UUID().uuidString)")
    let store = PadStore(layout: PadStorageLayout(root: root))
    await store.load()
    return (store, root)
  }

  private func makeService(_ store: PadStore) -> MCPService {
    MCPService(store: store, writer: StorePadWriter(store: store), client: "claude")
  }

  @Test("list_pads shows exposed pads and hides the rest")
  func listPads() async throws {
    let (store, root) = await makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let shared = try await store.createPad(name: "Shared")
    _ = try await store.createPad(name: "Private")
    try await store.setExposedToMCP(shared.id, true)

    let result = try await makeService(store).execute(.listPads)
    guard case .padList(let pads) = result else {
      Issue.record("expected a pad list")
      return
    }
    #expect(pads.map(\.name) == ["Shared"])
    #expect(pads.first?.uri == "itchy://pad/\(shared.id)")
  }

  @Test("read_pad returns the plain text")
  func readPad() async throws {
    let (store, root) = await makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let pad = try await store.createPad(name: "Shared")
    try await store.setExposedToMCP(pad.id, true)
    await store.stage(PadContent.plainText("contents"), for: pad.id, origin: .user)

    #expect(try await makeService(store).execute(.readPad(pad.id)) == .text("contents"))
  }

  @Test("write_pad replaces and append_pad adds, both marked as external")
  func writes() async throws {
    let (store, root) = await makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let pad = try await store.createPad(name: "Shared")
    try await store.setExposedToMCP(pad.id, true)
    let service = makeService(store)

    _ = try await service.execute(.writePad(pad.id, text: "one"))
    #expect(try await store.content(of: pad.id).plainText == "one")

    _ = try await service.execute(.appendPad(pad.id, text: " two"))
    #expect(try await store.content(of: pad.id).plainText == "one two")

    // `FR-8.9`: the marker says an agent did it, and which one.
    let marker = try #require(await store.pads.first { $0.id == pad.id }?.externalWriteMarker)
    #expect(marker.origin == .mcp(client: "claude"))
  }

  /// A pad the agent made that it then cannot read would look like a failure.
  @Test("create_pad exposes what it creates")
  func createPad() async throws {
    let (store, root) = await makeStore()
    defer { try? FileManager.default.removeItem(at: root) }

    let result = try await makeService(store).execute(.createPad(name: "Made", text: "hello"))
    guard case .created(let summary) = result else {
      Issue.record("expected a created pad")
      return
    }
    #expect(summary.name == "Made")
    let pad = try #require(await store.pads.first { $0.name == "Made" })
    #expect(pad.isExposedToMCP)
    #expect(try await store.content(of: pad.id).plainText == "hello")
  }

  /// §11.5 again, by the other route: a resource URI must not reach a pad a
  /// tool call could not.
  @Test("A resource read is subject to the same exposure rule")
  func resourceExposure() async throws {
    let (store, root) = await makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let hidden = try await store.createPad(name: "Private")
    await store.stage(PadContent.plainText("secret"), for: hidden.id, origin: .user)
    let service = makeService(store)

    await #expect(throws: MCPRoutingError.self) {
      try await service.readResource(uri: MCPToolSurface.resourceURI(for: hidden.id))
    }

    try await store.setExposedToMCP(hidden.id, true)
    #expect(try await service.readResource(uri: MCPToolSurface.resourceURI(for: hidden.id)) == "secret")
  }

  @Test("A resource URI that is not ours is refused")
  func foreignResource() async throws {
    let (store, root) = await makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    await #expect(throws: MCPRoutingError.self) {
      try await makeService(store).readResource(uri: "file:///etc/passwd")
    }
  }
}
