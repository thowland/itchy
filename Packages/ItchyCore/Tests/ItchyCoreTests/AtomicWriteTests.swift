import Foundation
import Testing

@testable import ItchyCore

@Suite("Atomic write")
struct AtomicWriteTests {
  @Test("A file write lands")
  func writesAFile() throws {
    let root = TemporaryRoot()
    let atomic = AtomicWrite(fileSystem: LocalFileSystem())
    let target = root.url.appendingPathComponent("thing.json")

    try atomic.write(Data("first".utf8), to: target)
    #expect(try Data(contentsOf: target) == Data("first".utf8))

    try atomic.write(Data("second".utf8), to: target)
    #expect(try Data(contentsOf: target) == Data("second".utf8))
  }

  /// `FR-5.6`: a failure during a save must not be able to leave the target
  /// truncated. The previous content is intact by construction, because the
  /// target is never opened for writing.
  @Test("A failure at the replace step leaves the previous content intact")
  func replaceFailureIsHarmless() throws {
    let root = TemporaryRoot()
    let fileSystem = FaultInjectingFileSystem()
    let atomic = AtomicWrite(fileSystem: fileSystem)
    let target = root.url.appendingPathComponent("meta.json")

    try atomic.write(Data("good".utf8), to: target)
    fileSystem.arm(.replace, on: "meta.json")

    #expect(throws: (any Error).self) {
      try atomic.write(Data("doomed".utf8), to: target)
    }

    #expect(try Data(contentsOf: target) == Data("good".utf8))
  }

  @Test("A failure at the write step leaves the previous content intact")
  func writeFailureIsHarmless() throws {
    let root = TemporaryRoot()
    let fileSystem = FaultInjectingFileSystem()
    let atomic = AtomicWrite(fileSystem: fileSystem)
    let target = root.url.appendingPathComponent("meta.json")

    try atomic.write(Data("good".utf8), to: target)
    fileSystem.arm(.write, on: ".tmp")

    #expect(throws: (any Error).self) {
      try atomic.write(Data("doomed".utf8), to: target)
    }
    #expect(try Data(contentsOf: target) == Data("good".utf8))
  }

  @Test("A failed write leaves no temporary behind")
  func noDebrisAfterFailure() throws {
    let root = TemporaryRoot()
    let fileSystem = FaultInjectingFileSystem()
    let atomic = AtomicWrite(fileSystem: fileSystem)
    let target = root.url.appendingPathComponent("meta.json")
    fileSystem.arm(.replace, on: "meta.json")

    #expect(throws: (any Error).self) {
      try atomic.write(Data("doomed".utf8), to: target)
    }

    let leftovers = try FileManager.default
      .contentsOfDirectory(at: root.url, includingPropertiesForKeys: nil)
      .filter { AtomicWrite.isTemporary($0) }
    #expect(leftovers.isEmpty)
  }

  @Test("The temporary is created beside the target, within one filesystem")
  func temporaryIsASibling() {
    let target = URL(fileURLWithPath: "/a/b/content.rtfd")
    let temporary = AtomicWrite.temporaryURL(beside: target)
    #expect(temporary.deletingLastPathComponent().path == "/a/b")
    #expect(AtomicWrite.isTemporary(temporary))
  }

  /// An RTFD bundle is a directory, so directory replacement has to be as safe
  /// as file replacement (specification §6.3).
  @Test("A directory write lands as a whole")
  func writesADirectory() throws {
    let root = TemporaryRoot()
    let atomic = AtomicWrite(fileSystem: LocalFileSystem())
    let target = root.url.appendingPathComponent("content.rtfd")

    try atomic.writeDirectory(
      ["TXT.rtf": Data("rtf".utf8), "image.png": Data([0x89, 0x50])], to: target)

    let back = try atomic.readDirectory(at: target)
    #expect(back["TXT.rtf"] == Data("rtf".utf8))
    #expect(back["image.png"] == Data([0x89, 0x50]))
  }

  @Test("Replacing a directory does not merge with the old one")
  func directoryReplacementIsNotAMerge() throws {
    let root = TemporaryRoot()
    let atomic = AtomicWrite(fileSystem: LocalFileSystem())
    let target = root.url.appendingPathComponent("content.rtfd")

    try atomic.writeDirectory(["TXT.rtf": Data("a".utf8), "old.png": Data("x".utf8)], to: target)
    try atomic.writeDirectory(["TXT.rtf": Data("b".utf8)], to: target)

    let back = try atomic.readDirectory(at: target)
    #expect(back.keys.sorted() == ["TXT.rtf"])
    #expect(back["TXT.rtf"] == Data("b".utf8))
  }

  @Test("A failed directory write leaves the previous bundle intact")
  func directoryFailureIsHarmless() throws {
    let root = TemporaryRoot()
    let fileSystem = FaultInjectingFileSystem()
    let atomic = AtomicWrite(fileSystem: fileSystem)
    let target = root.url.appendingPathComponent("content.rtfd")

    try atomic.writeDirectory(["TXT.rtf": Data("good".utf8)], to: target)
    fileSystem.arm(.replace, on: "content.rtfd")

    #expect(throws: (any Error).self) {
      try atomic.writeDirectory(["TXT.rtf": Data("doomed".utf8)], to: target)
    }
    #expect(try atomic.readDirectory(at: target)["TXT.rtf"] == Data("good".utf8))
  }

  @Test("Orphaned temporaries older than the age are swept")
  func sweepsOldDebris() throws {
    let root = TemporaryRoot()
    let atomic = AtomicWrite(fileSystem: LocalFileSystem())
    let debris = root.url.appendingPathComponent(".content.rtfd.123.abcd1234.tmp")
    let keeper = root.url.appendingPathComponent("content.rtfd")
    try Data("x".utf8).write(to: debris)
    try Data("y".utf8).write(to: keeper)

    atomic.sweepOrphanedTemporaries(
      in: root.url, olderThan: 3600, now: Date().addingTimeInterval(7200))

    #expect(!FileManager.default.fileExists(atPath: debris.path))
    #expect(FileManager.default.fileExists(atPath: keeper.path))
  }

  @Test("A write in progress is never swept")
  func sweepSparesRecentDebris() throws {
    let root = TemporaryRoot()
    let atomic = AtomicWrite(fileSystem: LocalFileSystem())
    let fresh = root.url.appendingPathComponent(".meta.json.123.abcd1234.tmp")
    try Data("x".utf8).write(to: fresh)

    atomic.sweepOrphanedTemporaries(in: root.url, olderThan: 3600, now: Date())

    #expect(FileManager.default.fileExists(atPath: fresh.path))
  }
}
