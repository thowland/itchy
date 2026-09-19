import Foundation
import ItchyCore
import MCP
import Testing

@testable import ItchyServices

/// The server as an agent meets it: a real client, a real socket, a real
/// handshake.
///
/// These are the tests a unit test of the router cannot stand in for — that the
/// SSE stream closes when the response has been routed, that a keep-alive
/// connection does not lose the second request, that the SDK's validators are
/// satisfied by what our socket hands them.
@Suite("MCP server over HTTP")
struct MCPServerHostTests {
  // MARK: - FR-8.1, FR-8.5

  @Test("A client handshakes, lists the five tools, and reads a pad", .timeLimit(.minutes(1)))
  func handshake() async throws {
    let fixture = try await MCPServerFixture.make()
    defer { Task { await tearDown(fixture) } }
    let pad = try await fixture.exposedPad(named: "Notes", text: "hello agent")

    let (client, transport) = fixture.client()
    let initialised = try await client.connect(transport: transport)
    #expect(initialised.serverInfo.name == "Itchy")

    let (tools, _) = try await client.listTools()
    #expect(
      Set(tools.map(\.name))
        == Set([
          "list_pads", "read_pad", "append_pad", "write_pad", "create_pad",
        ]))
    #expect(tools.count == MCPToolSurface.all.count)

    let (content, isError) = try await client.callTool(
      name: "read_pad", arguments: ["pad": .string(pad.name)])
    #expect(isError != true)
    #expect(text(of: content) == "hello agent")

    await client.disconnect()
  }

  @Test("list_pads names what is exposed", .timeLimit(.minutes(1)))
  func listPads() async throws {
    let fixture = try await MCPServerFixture.make()
    defer { Task { await tearDown(fixture) } }
    _ = try await fixture.exposedPad(named: "Notes", text: "12345")

    let (client, transport) = fixture.client()
    _ = try await client.connect(transport: transport)

    let (listing, _) = try await client.callTool(name: "list_pads")
    #expect(text(of: listing).contains("Notes — 5 characters"))

    await client.disconnect()
  }

  @Test("A pad is readable as a resource as well as by a tool", .timeLimit(.minutes(1)))
  func resources() async throws {
    let fixture = try await MCPServerFixture.make()
    defer { Task { await tearDown(fixture) } }
    let pad = try await fixture.exposedPad(named: "Notes", text: "as a resource")

    let (client, transport) = fixture.client()
    _ = try await client.connect(transport: transport)

    let (resources, _) = try await client.listResources()
    #expect(resources.map(\.uri) == [MCPToolSurface.resourceURI(for: pad.id)])

    let contents = try await client.readResource(uri: MCPToolSurface.resourceURI(for: pad.id))
    #expect(contents.first?.text == "as a resource")

    await client.disconnect()
  }

  /// One connection, several requests: the keep-alive path, which is where a
  /// framing mistake shows up as a client that hangs on its second call.
  @Test("Several calls in one session all answer", .timeLimit(.minutes(1)))
  func severalCalls() async throws {
    let fixture = try await MCPServerFixture.make()
    defer { Task { await tearDown(fixture) } }
    _ = try await fixture.exposedPad(named: "Notes", text: "text")

    let (client, transport) = fixture.client()
    _ = try await client.connect(transport: transport)

    for _ in 0..<5 {
      let (content, isError) = try await client.callTool(
        name: "read_pad", arguments: ["pad": .string("Notes")])
      #expect(isError != true)
      #expect(text(of: content) == "text")
    }

    await client.disconnect()
  }

  // MARK: - The write tools

  @Test("Writing and appending reach the store", .timeLimit(.minutes(1)))
  func writes() async throws {
    let fixture = try await MCPServerFixture.make()
    defer { Task { await tearDown(fixture) } }
    let pad = try await fixture.exposedPad(named: "Draft", text: "one")

    let (client, transport) = fixture.client()
    _ = try await client.connect(transport: transport)

    _ = try await client.callTool(
      name: "append_pad", arguments: ["pad": .string("Draft"), "text": .string(" two")])
    #expect(try await fixture.store.content(of: pad.id).plainText == "one two")

    _ = try await client.callTool(
      name: "write_pad", arguments: ["pad": .string("Draft"), "text": .string("replaced")])
    #expect(try await fixture.store.content(of: pad.id).plainText == "replaced")

    await client.disconnect()
  }

  /// `create_pad` exposes the pad it creates: a pad an agent made and then
  /// cannot read reads as a failure of the tool rather than as a safety
  /// property. Existing pads stay opt-in.
  @Test("A created pad is exposed, and nothing else becomes so", .timeLimit(.minutes(1)))
  func createPad() async throws {
    let fixture = try await MCPServerFixture.make()
    defer { Task { await tearDown(fixture) } }
    _ = try await fixture.store.createPad(name: "Mine")

    let (client, transport) = fixture.client()
    _ = try await client.connect(transport: transport)

    let (created, isError) = try await client.callTool(
      name: "create_pad", arguments: ["name": .string("Agent's"), "text": .string("made here")])
    #expect(isError != true)
    #expect(text(of: created).contains("Agent's"))

    let exposed = await fixture.store.pads.filter(\.isExposedToMCP)
    #expect(exposed.map(\.name) == ["Agent's"])

    await client.disconnect()
  }

  // MARK: - FR-8.2, concurrency

  @Test("Two clients are connected at once and see the same pad", .timeLimit(.minutes(1)))
  func twoSessions() async throws {
    let fixture = try await MCPServerFixture.make()
    defer { Task { await tearDown(fixture) } }
    _ = try await fixture.exposedPad(named: "Shared", text: "start")

    let (first, firstTransport) = fixture.client()
    let (second, secondTransport) = fixture.client()
    _ = try await first.connect(transport: firstTransport)
    _ = try await second.connect(transport: secondTransport)
    #expect(await fixture.host.sessionCount == 2)

    _ = try await first.callTool(
      name: "append_pad", arguments: ["pad": .string("Shared"), "text": .string(" and more")])
    let (seen, _) = try await second.callTool(
      name: "read_pad", arguments: ["pad": .string("Shared")])
    #expect(text(of: seen) == "start and more")

    await first.disconnect()
    await second.disconnect()
  }
}
