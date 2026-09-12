import AppKit
import ItchyCore
import Testing

@testable import Itchy

/// End to end: what the editor holds becomes what is on disk, and comes back.
///
/// The unit suites cover the codec and the store separately; this covers the
/// path between them, which is where `FR-4.2` and `FR-5.3` actually live.
@MainActor
@Suite("Editor to disk")
struct PadPersistenceIntegrationTests {
  private func temporaryRoot() -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-integration-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func swatch() -> NSImage {
    let image = NSImage(size: NSSize(width: 80, height: 40))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 80, height: 40).fill()
    image.unlockFocus()
    return image
  }

  private func attributedWithImage() -> NSAttributedString {
    let result = NSMutableAttributedString(string: "screenshot: ")
    let attachment = NSTextAttachment()
    attachment.image = swatch()
    result.append(NSAttributedString(attachment: attachment))
    return result
  }

  /// `FR-4.2` and `FR-5.1`: a pasted screenshot survives save and relaunch.
  @Test("An image typed into a pad survives a store round trip")
  func imageSurvivesToDisk() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = PadStorageLayout(root: root)

    let store = PadStore(layout: layout)
    await store.load()
    let pad = try await store.createPad(name: "with image")
    await store.stage(try ContentCodec.encode(attributedWithImage()), for: pad.id, origin: .user)
    try await store.flushAll()

    let reopened = PadStore(layout: layout)
    await reopened.load()
    let decoded = try ContentCodec.decode(try await reopened.content(of: pad.id))

    var attachments = 0
    decoded.enumerateAttribute(
      .attachment, in: NSRange(location: 0, length: decoded.length)
    ) { value, _, _ in
      if value != nil { attachments += 1 }
    }
    #expect(attachments == 1, "the image must come back")
    #expect(decoded.string.hasPrefix("screenshot: "))
  }

  /// `FR-5.3`: what Itchy writes must be a real RTFD bundle, which is what lets
  /// anything else on the machine open it (D-13).
  @Test("The bundle on disk is a directory containing the image as its own file")
  func bundleShapeOnDisk() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = PadStorageLayout(root: root)

    let store = PadStore(layout: layout)
    await store.load()
    let pad = try await store.createPad(name: "bundle")
    await store.stage(try ContentCodec.encode(attributedWithImage()), for: pad.id, origin: .user)
    try await store.flushAll()

    let directory = layout.contentDirectory(for: pad.id)
    var isDirectory = ObjCBool(false)
    _ = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
    #expect(isDirectory.boolValue)

    let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(files.contains("TXT.rtf"))
    #expect(files.count > 1, "the image is a file alongside the document")
  }

  /// `FR-5.4`: the shadow file is the plain-text extraction, written every save.
  @Test("The shadow file holds the text and not the markup")
  func shadowFile() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = PadStorageLayout(root: root)

    let store = PadStore(layout: layout)
    await store.load()
    let pad = try await store.createPad(name: "shadow")
    let styled = NSMutableAttributedString(string: "bold words")
    styled.addAttribute(
      .font, value: NSFont.boldSystemFont(ofSize: 24), range: NSRange(location: 0, length: 4))
    await store.stage(try ContentCodec.encode(styled), for: pad.id, origin: .user)
    try await store.flushAll()

    let shadow = try Data(contentsOf: layout.shadowFile(for: pad.id))
    #expect(shadow == Data("bold words".utf8))
  }

  /// `FR-4.5`: flattening keeps the text and drops everything else.
  @Test("Flattening a pad with an image keeps the text and loses the attachment")
  func flattenThroughStore() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = PadStorageLayout(root: root)

    let store = PadStore(layout: layout)
    await store.load()
    let pad = try await store.createPad(name: "flattening")
    let original = attributedWithImage()
    await store.stage(try ContentCodec.encode(original), for: pad.id, origin: .user)

    let flattened = ContentCodec.flatten(original)
    await store.stage(try ContentCodec.encode(flattened), for: pad.id, origin: .user)
    try await store.flush(pad.id)

    let decoded = try ContentCodec.decode(try await store.content(of: pad.id))
    var attachments = 0
    decoded.enumerateAttribute(
      .attachment, in: NSRange(location: 0, length: decoded.length)
    ) { value, _, _ in
      if value != nil { attachments += 1 }
    }
    #expect(attachments == 0)
    #expect(decoded.string.contains("screenshot: "))
  }
}
