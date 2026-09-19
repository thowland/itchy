import Foundation
import ItchyCore
import Testing

@testable import ItchyServices

private func pad(_ name: String, exposed: Bool = true) -> PadMetadata {
  PadMetadata(name: name, created: .now, modified: .now, isExposedToMCP: exposed)
}

@Suite("MCP tool surface")
struct MCPToolSurfaceTests {
  /// `FR-8.5`: exactly five. The count is asserted because the narrowness is
  /// the requirement, not a consequence of one.
  @Test("There are five tools, named as the specification names them")
  func fiveTools() {
    #expect(MCPToolSurface.all.count == 5)
    #expect(
      MCPToolSurface.all.map(\.name) == [
        "list_pads", "read_pad", "append_pad", "write_pad", "create_pad",
      ])
  }

  @Test("Required arguments match §11.3's schemas")
  func schemas() {
    let required = Dictionary(
      uniqueKeysWithValues: MCPToolSurface.all.map {
        ($0.name, $0.properties.filter(\.required).map(\.name))
      })
    #expect(required["list_pads"] == [])
    #expect(required["read_pad"] == ["pad"])
    #expect(required["append_pad"] == ["pad", "text"])
    #expect(required["write_pad"] == ["pad", "text"])
    #expect(required["create_pad"] == [])
  }

  @Test("A pad resource URI round-trips")
  func resourceURI() {
    let id = PadID()
    #expect(MCPToolSurface.resourceURI(for: id) == "itchy://pad/\(id)")
    #expect(MCPToolSurface.padID(fromResourceURI: MCPToolSurface.resourceURI(for: id)) == id)
  }

  @Test(
    "A URI that is not ours resolves to nothing rather than to a guess",
    arguments: ["itchy://pad/not-a-uuid", "file:///etc/passwd", "itchy://other/\(PadID())", ""])
  func foreignURI(uri: String) {
    #expect(MCPToolSurface.padID(fromResourceURI: uri) == nil)
  }
}

@Suite("Pad resolution")
struct PadResolverTests {
  @Test("A pad resolves by identifier and by name, case-insensitively")
  func resolves() {
    let scratch = pad("Scratch")
    let pads = [scratch, pad("Notes")]
    #expect(PadResolver.resolve(scratch.id.description, in: pads) == .resolved(scratch.id))
    #expect(PadResolver.resolve("scratch", in: pads) == .resolved(scratch.id))
    #expect(PadResolver.resolve("  SCRATCH  ", in: pads) == .resolved(scratch.id))
  }

  @Test("A duplicated name asks for the identifier rather than guessing")
  func ambiguous() {
    let pads = [pad("Same"), pad("same")]
    #expect(PadResolver.resolve("same", in: pads) == .ambiguous(candidates: ["Same", "same"]))
  }

  @Test(
    "Nothing else resolves",
    arguments: ["", "   ", "missing", "00000000-0000-0000-0000-000000000000"])
  func notFound(reference: String) {
    #expect(PadResolver.resolve(reference, in: [pad("Scratch")]) == .notFound)
  }

  /// §11.5: an unexposed pad is not merely hidden from `list_pads`; naming it
  /// directly gives the same answer as naming one that does not exist.
  @Test("An unexposed pad is indistinguishable from a nonexistent one")
  func exposure() {
    let hidden = pad("Private", exposed: false)
    let visible = ExposurePolicy.visible(in: [hidden, pad("Shared")])
    #expect(visible.map(\.name) == ["Shared"])
    #expect(PadResolver.resolve("Private", in: visible) == .notFound)
    #expect(PadResolver.resolve(hidden.id.description, in: visible) == .notFound)
  }

  @Test("Nothing is exposed by default")
  func defaultExposure() {
    #expect(!ExposurePolicy.isVisible(PadMetadata(name: "New", created: .now, modified: .now)))
  }
}

@Suite("Tool routing")
struct ToolRouterTests {
  private let scratch = pad("Scratch")
  private var pads: [PadMetadata] { [scratch] }

  @Test("Each tool routes to its operation")
  func routes() throws {
    #expect(try ToolRouter.route(tool: "list_pads", arguments: [:], visiblePads: pads) == .listPads)
    #expect(
      try ToolRouter.route(tool: "read_pad", arguments: ["pad": "Scratch"], visiblePads: pads)
        == .readPad(scratch.id))
    #expect(
      try ToolRouter.route(
        tool: "append_pad", arguments: ["pad": "Scratch", "text": "more"], visiblePads: pads)
        == .appendPad(scratch.id, text: "more"))
    #expect(
      try ToolRouter.route(
        tool: "write_pad", arguments: ["pad": "Scratch", "text": "all"], visiblePads: pads)
        == .writePad(scratch.id, text: "all"))
  }

  @Test("create_pad requires neither argument")
  func createPad() throws {
    #expect(
      try ToolRouter.route(tool: "create_pad", arguments: [:], visiblePads: pads)
        == .createPad(name: nil, text: nil))
    #expect(
      try ToolRouter.route(tool: "create_pad", arguments: ["name": "New"], visiblePads: pads)
        == .createPad(name: "New", text: nil))
  }

  @Test("An unknown tool is refused by name")
  func unknownTool() {
    #expect(throws: MCPRoutingError.unknownTool("delete_everything")) {
      try ToolRouter.route(tool: "delete_everything", arguments: [:], visiblePads: pads)
    }
  }

  @Test(
    "A missing argument names the argument and the tool",
    arguments: [("read_pad", "pad"), ("append_pad", "pad"), ("write_pad", "pad")])
  func missingPad(tool: String, argument: String) {
    #expect(throws: MCPRoutingError.missingArgument(name: argument, tool: tool)) {
      try ToolRouter.route(tool: tool, arguments: [:], visiblePads: pads)
    }
  }

  @Test("A missing text argument is caught too")
  func missingText() {
    #expect(throws: MCPRoutingError.missingArgument(name: "text", tool: "append_pad")) {
      try ToolRouter.route(tool: "append_pad", arguments: ["pad": "Scratch"], visiblePads: pads)
    }
  }

  @Test("An unresolvable pad is refused without saying whether it exists")
  func unresolvable() {
    #expect(throws: MCPRoutingError.padNotFound(reference: "Ghost")) {
      try ToolRouter.route(tool: "read_pad", arguments: ["pad": "Ghost"], visiblePads: pads)
    }
  }

  @Test("Every refusal carries a message an agent can act on")
  func messages() {
    let errors: [MCPRoutingError] = [
      .unknownTool("x"), .missingArgument(name: "pad", tool: "read_pad"),
      .padNotFound(reference: "Ghost"),
      .ambiguousPad(reference: "same", candidates: ["Same", "same"]),
    ]
    for error in errors {
      #expect(!error.message.isEmpty)
    }
    #expect(MCPRoutingError.ambiguousPad(reference: "s", candidates: ["A", "B"]).message.contains("A, B"))
  }
}
