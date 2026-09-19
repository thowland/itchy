import Foundation
import ItchyCore
import MCP
import Testing

@testable import ItchyServices

@Suite("MCP session routing and conversion")
struct MCPSessionRouteTests {
  // MARK: - Session routing

  @Test("An initialize with no session starts one")
  func createsOnInitialize() {
    #expect(
      MCPSessionRouter.route(sessionID: nil, isInitialize: true, known: []) == .create)
  }

  @Test("A known session identifier routes to it")
  func routesToExisting() {
    #expect(
      MCPSessionRouter.route(sessionID: "a", isInitialize: false, known: ["a", "b"])
        == .existing("a"))
  }

  /// A session from a previous run of Itchy. `404` is the answer that tells a
  /// client to initialise again rather than to retry.
  @Test("A session this server does not have is not quietly created")
  func unknownSession() {
    #expect(
      MCPSessionRouter.route(sessionID: "gone", isInitialize: false, known: ["a"])
        == .unknown("gone"))
  }

  @Test("An empty header is treated as no header at all")
  func emptyHeader() {
    #expect(MCPSessionRouter.route(sessionID: "", isInitialize: true, known: []) == .create)
    #expect(MCPSessionRouter.route(sessionID: "", isInitialize: false, known: []) == .missing)
  }

  /// Re-initialising an existing session is the transport's error to report.
  /// Starting a second session behind the client's back would hide a client bug
  /// and leak a session per attempt.
  @Test("Re-initialising a named session goes to that session, not to a new one")
  func reinitialisation() {
    #expect(
      MCPSessionRouter.route(sessionID: "a", isInitialize: true, known: ["a"]) == .existing("a"))
  }

  @Test("Anything else without a session is refused")
  func missingSession() {
    #expect(MCPSessionRouter.route(sessionID: nil, isInitialize: false, known: []) == .missing)
  }

  // MARK: - Recognising an initialisation

  @Test("An initialize request is recognised, and other methods are not")
  func recognisesInitialize() {
    #expect(MCPBodyInspector.isInitialize(Data(#"{"method":"initialize","id":1}"#.utf8)))
    #expect(MCPBodyInspector.isInitialize(Data(#"{"method":"tools/list","id":1}"#.utf8)) == false)
  }

  @Test("A batch containing an initialize counts as one")
  func recognisesBatch() {
    #expect(MCPBodyInspector.isInitialize(Data(#"[{"method":"initialize","id":1}]"#.utf8)))
    #expect(MCPBodyInspector.isInitialize(Data(#"[{"method":"ping","id":1}]"#.utf8)) == false)
  }

  @Test("An empty or unreadable body is not an initialisation")
  func toleratesRubbish() {
    #expect(MCPBodyInspector.isInitialize(Data()) == false)
    #expect(MCPBodyInspector.isInitialize(Data("not json".utf8)) == false)
    #expect(MCPBodyInspector.isInitialize(Data("[1,2,3]".utf8)) == false)
  }

  // MARK: - Arguments

  /// The router is free of SDK types so that the tool surface is testable
  /// without one. This is the only place the boundary is crossed.
  @Test("Scalar arguments become the strings the router takes")
  func argumentsBecomeStrings() {
    let arguments: [String: Value] = [
      "pad": .string("Notes"),
      "slot": .int(3),
      "ratio": .double(1.5),
      "flag": .bool(true),
    ]
    let strings = MCPArgumentCodec.strings(from: arguments)
    #expect(strings["pad"] == "Notes")
    #expect(strings["slot"] == "3")
    #expect(strings["ratio"] == "1.5")
    #expect(strings["flag"] == "true")
  }

  @Test("No arguments at all is an empty set, not a failure")
  func noArguments() {
    #expect(MCPArgumentCodec.strings(from: nil).isEmpty)
  }

  /// There is no reading of an object or an array that is likely to be what the
  /// caller meant, so it is dropped and the tool reports the argument missing.
  @Test("Structured arguments are dropped rather than guessed at")
  func structuredArgumentsDropped() {
    let strings = MCPArgumentCodec.strings(from: [
      "pad": .string("Notes"),
      "extra": .object(["nested": .string("x")]),
      "list": .array([.string("x")]),
      "nothing": .null,
    ])
    #expect(strings == ["pad": "Notes"])
  }

  // MARK: - Results

  @Test("A listing names each pad, its size and its resource URI")
  func listing() {
    let summary = PadSummary(
      id: "abc", name: "Notes", uri: "itchy://pad/abc", characters: 12, modified: Date())
    #expect(
      MCPResultCodec.text(for: .padList([summary])) == "Notes — 12 characters — itchy://pad/abc")
  }

  /// An empty list from a running server is indistinguishable from a broken one
  /// unless it explains itself, and the explanation is also the instruction.
  @Test("An empty listing explains why it is empty")
  func emptyListing() {
    let text = MCPResultCodec.text(for: .padList([]))
    #expect(text == MCPResultCodec.emptyListing)
    #expect(text.contains("none is by default"))
  }

  @Test("A created pad answers with somewhere to read it")
  func created() {
    let summary = PadSummary(
      id: "abc", name: "Agent's", uri: "itchy://pad/abc", characters: 0, modified: Date())
    let text = MCPResultCodec.text(for: .created(summary))
    #expect(text.contains("Agent's"))
    #expect(text.contains("itchy://pad/abc"))
  }

  @Test("Text comes back as text")
  func plainResult() {
    #expect(MCPResultCodec.text(for: .text("hello")) == "hello")
    #expect(MCPResultCodec.content(for: .text("hello")).count == 1)
  }

  // MARK: - Tool schemas

  @Test("The schema is derived from the surface, so the two cannot drift")
  func schemaFollowsSurface() {
    #expect(MCPToolCodec.tools.map(\.name) == MCPToolSurface.all.map(\.name))
  }

  @Test("Required arguments are marked required, and optional ones are not")
  func requiredArguments() throws {
    let write = try #require(MCPToolCodec.tools.first { $0.name == MCPToolSurface.writePad })
    guard case .object(let schema) = write.inputSchema,
      case .array(let required) = schema["required"] ?? .null
    else {
      Issue.record("expected an object schema with a required list")
      return
    }
    #expect(Set(required.compactMap(\.stringValue)) == ["pad", "text"])

    let create = try #require(MCPToolCodec.tools.first { $0.name == MCPToolSurface.createPad })
    guard case .object(let createSchema) = create.inputSchema,
      case .array(let createRequired) = createSchema["required"] ?? .null
    else {
      Issue.record("expected an object schema with a required list")
      return
    }
    #expect(createRequired.isEmpty)
  }

  @Test("Every argument is described, so an agent need not guess its shape")
  func propertiesDescribed() {
    for tool in MCPToolCodec.tools {
      guard case .object(let schema) = tool.inputSchema,
        case .object(let properties) = schema["properties"] ?? .null
      else {
        Issue.record("\(tool.name) has no properties object")
        continue
      }
      for (name, property) in properties {
        guard case .object(let fields) = property,
          let description = fields["description"]?.stringValue, !description.isEmpty
        else {
          Issue.record("\(tool.name).\(name) is undescribed")
          continue
        }
      }
    }
  }

  /// Hints, and marked as such by the SDK — but a client that shows the user
  /// what a tool will do gets it right only if the server says.
  @Test("Reading is marked read-only and replacing is marked destructive")
  func annotations() {
    #expect(MCPToolCodec.annotations(for: MCPToolSurface.readPad).readOnlyHint == true)
    #expect(MCPToolCodec.annotations(for: MCPToolSurface.listPads).readOnlyHint == true)
    #expect(MCPToolCodec.annotations(for: MCPToolSurface.writePad).destructiveHint == true)
    #expect(MCPToolCodec.annotations(for: MCPToolSurface.appendPad).destructiveHint == false)
    // Nothing here reaches outside this machine.
    #expect(MCPToolCodec.tools.allSatisfy { $0.annotations.openWorldHint == false })
  }

  // MARK: - Refusals and policy

  @Test("A write to an open pad is refused only while the writer cannot reach it")
  func openPadPolicy() {
    #expect(OpenPadPolicy.admit(isOpen: false, writerReachesOpenPads: false) == .proceed)
    #expect(OpenPadPolicy.admit(isOpen: true, writerReachesOpenPads: false) == .refuseBecauseOpen)
    // Sprint 9's registry-aware writer: the refusal stops applying with no
    // other change.
    #expect(OpenPadPolicy.admit(isOpen: true, writerReachesOpenPads: true) == .proceed)
  }

  @Test("A refusal tells the agent what to do about it")
  func refusalWording() {
    #expect(MCPWriteRefusal.padOpenInInterface.message.contains("open in Itchy"))
    #expect(MCPWriteRefusal.padOpenInInterface.message.contains("closed"))
  }

  @Test("A missing credential and a wrong one say different things")
  func authorizationWording() {
    #expect(AuthorizationText.of(.missingCredential).contains("needs a bearer token"))
    #expect(AuthorizationText.of(.rejected).contains("regenerated"))
    #expect(AuthorizationText.of(.allowed).isEmpty == false)
  }

  @Test("Errors an agent can act on are reported in their own words")
  func errorMessages() {
    #expect(MCPSession.message(for: MCPRoutingError.unknownTool("nope")).contains("nope"))
    #expect(MCPSession.message(for: MCPWriteRefusal.padOpenInInterface).contains("open in Itchy"))
    #expect(MCPSession.message(for: HTTPParseFailure.bodyTooLarge) == "That could not be done.")
  }

  @Test("The store-only writer does not claim to reach open pads")
  func storeWriterHonesty() async {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-writer-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PadStore(layout: PadStorageLayout(root: root))
    #expect(StorePadWriter(store: store).reachesOpenPads == false)
  }
}
