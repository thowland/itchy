import Foundation
import ItchyCore

// Command-line harness for the store (specification §1, implementation plan
// Sprint 1). Not shipped.
//
// Its existence is part of why the store is testable: a storage layer that can
// only be driven through a window is a storage layer that gets debugged by
// clicking.

@main
struct Main {
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
      print(usage)
      exit(2)
    }

    let root = ProcessInfo.processInfo.environment["ITCHY_ROOT"]
    let layout = root.map { PadStorageLayout.at(path: $0) } ?? standardLayout()
    let store = PadStore(layout: layout)
    await store.load()

    do {
      try await run(command, Array(arguments.dropFirst()), store: store, layout: layout)
    } catch let fault as PadStoreFault {
      FileHandle.standardError.write(Data("error: \(fault.reason)\n".utf8))
      exit(1)
    } catch {
      FileHandle.standardError.write(Data("error: \(error)\n".utf8))
      exit(1)
    }
  }

  private static func standardLayout() -> PadStorageLayout {
    guard let layout = try? PadStorageLayout.standard() else {
      FileHandle.standardError.write(Data("error: cannot locate Application Support\n".utf8))
      exit(1)
    }
    return layout
  }

  private static func run(
    _ command: String,
    _ arguments: [String],
    store: PadStore,
    layout: PadStorageLayout
  ) async throws {
    if try await runQuery(command, arguments, store: store, layout: layout) { return }
    if try await runMutation(command, arguments, store: store) { return }
    if command == "fault" {
      try await inject(arguments.first, store: store, layout: layout)
      return
    }
    print(usage)
    exit(2)
  }

  /// Commands that only read. Returns whether the command was handled.
  private static func runQuery(
    _ command: String,
    _ arguments: [String],
    store: PadStore,
    layout: PadStorageLayout
  ) async throws -> Bool {
    switch command {
    case "list":
      await list(store)
    case "read":
      print(try await store.content(of: identifier(arguments.first)).plainText)
    case "faults":
      await faults(store)
    case "where":
      print(layout.root.path)
    default:
      return false
    }
    return true
  }

  /// Commands that change something. Returns whether the command was handled.
  private static func runMutation(
    _ command: String,
    _ arguments: [String],
    store: PadStore
  ) async throws -> Bool {
    switch command {
    case "create":
      let pad = try await store.createPad(name: arguments.first)
      print("\(pad.id)  \(pad.name)")
    case "write":
      let id = try identifier(arguments.first)
      let text = arguments.dropFirst().joined(separator: " ")
      await store.stage(PadContent.plainText(text), for: id, origin: .user)
      try await store.flush(id)
    case "rename":
      try await store.rename(
        identifier(arguments.first), to: arguments.dropFirst().joined(separator: " "))
    case "delete":
      try await store.deletePad(identifier(arguments.first))
    default:
      return false
    }
    return true
  }

  private static func list(_ store: PadStore) async {
    let pads = await store.pads
    guard !pads.isEmpty else {
      print("(no pads)")
      return
    }
    for (slot, pad) in pads.enumerated() {
      let editable = await store.isEditable(pad.id) ? " " : "!"
      let mode = pad.mode.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)
      print("\(slot + 1)\(editable) \(pad.id)  \(mode)  \(pad.name)")
    }
  }

  private static func faults(_ store: PadStore) async {
    let recorded = await store.faults
    guard !recorded.isEmpty else {
      print("(no faults)")
      return
    }
    for (id, fault) in recorded {
      print("\(id)  editable=\(!fault.prohibitsEditing)  \(fault.reason)")
    }
  }

  /// Injects each fault for manual inspection, which is how the taxonomy gets
  /// looked at rather than only asserted (implementation plan, Sprint 1).
  private static func inject(
    _ kind: String?,
    store: PadStore,
    layout: PadStorageLayout
  ) async throws {
    guard let kind, let pad = await store.pads.first else {
      print("usage: itchyctl fault <metadata|schema|content|index>  (needs at least one pad)")
      exit(2)
    }
    let damage = FaultInjection(layout: layout, pad: pad.id)
    switch kind {
    case "metadata": try damage.corruptMetadata()
    case "schema": try damage.futureSchema()
    case "content": try damage.removeContent()
    case "index": try damage.corruptIndex()
    default:
      print("unknown fault: \(kind)")
      exit(2)
    }
    print("injected \(kind) fault into \(pad.id); run `itchyctl list` and `itchyctl faults`")
  }

  private static func identifier(_ text: String?) throws -> PadID {
    guard let text, let id = PadID(string: text) else {
      throw PadStoreFault.unknownPad(PadID())
    }
    return id
  }

  private static let usage = """
    itchyctl — development harness for the Itchy store

      list                 pads in slot order; ! marks a pad that is not editable
      create [name]        create a pad
      read <id>            print a pad's plain text
      write <id> <text>    replace a pad's contents
      rename <id> <name>   rename a pad
      delete <id>          delete a pad and its directory
      faults               recorded faults and whether the pad is still editable
      fault <kind>         damage the first pad: metadata | schema | content | index
      where                print the storage root

    ITCHY_ROOT overrides the storage root, which is how to drive a scratch
    directory rather than the real one.
    """
}
