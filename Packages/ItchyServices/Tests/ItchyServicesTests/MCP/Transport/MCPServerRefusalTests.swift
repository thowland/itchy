import Foundation
import ItchyCore
import MCP
import Testing

@testable import ItchyServices

/// Everything the server says no to, and the shape of the socket underneath it
/// (`FR-8.3`, `FR-8.4`, `FR-8.7`, `FR-8.10`, §11.2, §11.5, §11.6).
@Suite("MCP server refusals and reachability")
struct MCPServerRefusalTests {
  // MARK: - FR-8.7, NFR-3.2

  @Test("An unexposed pad is absent, and unnameable", .timeLimit(.minutes(1)))
  func exposure() async throws {
    let fixture = try await MCPServerFixture.make()
    let teardown = fixture.teardown
    defer { Task { await teardown.run() } }
    _ = try await fixture.store.createPad(name: "Salary review")

    let (client, transport) = fixture.client()
    _ = try await client.connect(transport: transport)

    let (listing, _) = try await client.callTool(name: "list_pads")
    #expect(text(of: listing) == MCPResultCodec.emptyListing)

    let (refusal, isError) = try await client.callTool(
      name: "read_pad", arguments: ["pad": .string("Salary review")])
    #expect(isError == true)
    // The same answer a pad that does not exist would give (§11.5): anything
    // else confirms that a pad by that name is there.
    #expect(text(of: refusal).contains("No pad called"))

    await client.disconnect()
  }

  @Test("An unexposed pad is not readable as a resource either", .timeLimit(.minutes(1)))
  func resourceExposure() async throws {
    let fixture = try await MCPServerFixture.make()
    let teardown = fixture.teardown
    defer { Task { await teardown.run() } }
    let pad = try await fixture.store.createPad(name: "Private")

    let (client, transport) = fixture.client()
    _ = try await client.connect(transport: transport)

    await #expect(throws: (any Error).self) {
      _ = try await client.readResource(uri: MCPToolSurface.resourceURI(for: pad.id))
    }

    await client.disconnect()
  }

  // MARK: - FR-8.4, §11.2

  @Test("An unauthenticated request is refused", .timeLimit(.minutes(1)))
  func missingCredential() async throws {
    let fixture = try await MCPServerFixture.make()
    let teardown = fixture.teardown
    defer { Task { await teardown.run() } }

    let (status, _) = try await post(to: fixture.endpoint, bearer: nil)
    #expect(status == 401)
  }

  @Test(
    "A request bearing the previous token is refused after regeneration",
    .timeLimit(.minutes(1)))
  func regenerationInvalidates() async throws {
    let fixture = try await MCPServerFixture.make()
    let teardown = fixture.teardown
    defer { Task { await teardown.run() } }
    let previous = fixture.token

    let (before, _) = try await post(to: fixture.endpoint, bearer: previous.value)
    #expect(before != 401)

    await fixture.host.replaceToken(with: MCPToken.generate())

    let (after, _) = try await post(to: fixture.endpoint, bearer: previous.value)
    #expect(after == 401)
  }

  @Test("A refusal says which kind of refusal it is", .timeLimit(.minutes(1)))
  func refusalsExplainThemselves() async throws {
    let fixture = try await MCPServerFixture.make()
    let teardown = fixture.teardown
    defer { Task { await teardown.run() } }

    let (_, absent) = try await post(to: fixture.endpoint, bearer: nil)
    #expect((String(bytes: absent, encoding: .utf8) ?? "").contains("needs a bearer token"))

    let (_, wrong) = try await post(to: fixture.endpoint, bearer: "not-the-token")
    #expect((String(bytes: wrong, encoding: .utf8) ?? "").contains("regenerated"))
  }

  // MARK: - §11.6

  /// Refuse rather than lose. The panel's next save would otherwise write over
  /// the agent's text and the agent would be told it succeeded.
  @Test("A write to a pad open in the interface is refused, not lost", .timeLimit(.minutes(1)))
  func refusesOpenPad() async throws {
    let fixture = try await MCPServerFixture.make(presence: EverythingOpen())
    let teardown = fixture.teardown
    defer { Task { await teardown.run() } }
    let pad = try await fixture.exposedPad(named: "Open", text: "typed by hand")

    let (client, transport) = fixture.client()
    _ = try await client.connect(transport: transport)

    let (refusal, isError) = try await client.callTool(
      name: "write_pad", arguments: ["pad": .string("Open"), "text": .string("from the agent")])
    #expect(isError == true)
    #expect(text(of: refusal).contains("open in Itchy"))
    #expect(try await fixture.store.content(of: pad.id).plainText == "typed by hand")

    // Reading is untouched: only the write is at risk.
    let (read, readFailed) = try await client.callTool(
      name: "read_pad", arguments: ["pad": .string("Open")])
    #expect(readFailed != true)
    #expect(text(of: read) == "typed by hand")

    await client.disconnect()
  }

  // MARK: - Sessions

  @Test("A session identifier from a previous run is refused", .timeLimit(.minutes(1)))
  func staleSession() async throws {
    let fixture = try await MCPServerFixture.make()
    let teardown = fixture.teardown
    defer { Task { await teardown.run() } }

    let (status, _) = try await post(
      to: fixture.endpoint, bearer: fixture.token.value,
      headers: ["Mcp-Session-Id": UUID().uuidString])
    #expect(status == 404)
  }

  @Test(
    "A request that names no session and does not initialise is refused",
    .timeLimit(.minutes(1)))
  func sessionRequired() async throws {
    let fixture = try await MCPServerFixture.make()
    let teardown = fixture.teardown
    defer { Task { await teardown.run() } }

    let body = #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#
    let (status, _) = try await post(
      to: fixture.endpoint, bearer: fixture.token.value, body: Data(body.utf8))
    #expect(status == 400)
  }

  // MARK: - FR-8.3, FR-8.10

  @Test("Starting binds a port and stopping frees it")
  func startAndStop() async throws {
    let fixture = try await MCPServerFixture.make()
    let port = fixture.port
    #expect(await canConnect(host: "127.0.0.1", port: port))

    await fixture.host.stop()
    #expect(await canConnect(host: "127.0.0.1", port: port) == false)

    try? FileManager.default.removeItem(at: fixture.root)
  }

  /// `FR-8.3`'s own acceptance criterion needs a second machine and is on the
  /// manual checklist in §14.6. What can be shown here is the mechanism behind
  /// it: the socket is bound to loopback, so the same port on another local
  /// address is not answering.
  @Test("The port answers on loopback and on no other local address")
  func loopbackOnly() async throws {
    let fixture = try await MCPServerFixture.make()
    let teardown = fixture.teardown
    defer { Task { await teardown.run() } }

    #expect(await canConnect(host: "127.0.0.1", port: fixture.port))
    for address in nonLoopbackAddresses() {
      #expect(
        await canConnect(host: address, port: fixture.port) == false,
        "the listener answered on \(address)")
    }
  }
}
