import Foundation
import Testing

@testable import ItchyCore

@Suite("Schema migration")
struct MigrationTests {
  @Test("Version 1 is current, so nothing is migrated")
  func currentVersionIsUntouched() {
    let migrator = SchemaMigrator(current: 1, migrations: [])
    let object: [String: JSONValue] = ["schemaVersion": .number(1), "name": .string("x")]
    let (result, outcome) = migrator.migrate(object)
    #expect(outcome == .current)
    #expect(result == object)
  }

  /// `FR-5.8`: a file from a newer build is reported unreadable rather than
  /// guessed at. Guessing would mean writing it back in a shape the newer build
  /// did not expect.
  @Test("A newer schema version is refused, not guessed at")
  func futureVersionIsRefused() {
    let migrator = SchemaMigrator(current: 1)
    let (_, outcome) = migrator.migrate(["schemaVersion": .number(7)])
    #expect(outcome == .tooNew(found: 7, supported: 1))
  }

  @Test("An absent version reads as version 1")
  func absentVersionDefaults() {
    let migrator = SchemaMigrator(current: 1)
    #expect(migrator.version(of: ["name": .string("x")]) == 1)
  }

  @Test("Registered migrations run in order and stamp the current version")
  func migrationsRunInOrder() {
    let migrator = SchemaMigrator(
      current: 3,
      migrations: [
        SchemaMigration(from: 1, to: 2) { object in
          var next = object
          next["addedAtTwo"] = .bool(true)
          return next
        },
        SchemaMigration(from: 2, to: 3) { object in
          var next = object
          next["addedAtThree"] = .bool(true)
          return next
        },
      ])

    let (result, outcome) = migrator.migrate(["schemaVersion": .number(1)])
    #expect(outcome == .migrated(from: 1))
    #expect(result["addedAtTwo"] == .bool(true))
    #expect(result["addedAtThree"] == .bool(true))
    #expect(result["schemaVersion"] == .number(3))
  }

  @Test("A missing migration step stops the chain rather than skipping it")
  func gapStopsTheChain() {
    let migrator = SchemaMigrator(
      current: 3,
      migrations: [
        SchemaMigration(from: 2, to: 3) { object in
          var next = object
          next["addedAtThree"] = .bool(true)
          return next
        }
      ])
    let (result, _) = migrator.migrate(["schemaVersion": .number(1)])
    #expect(result["addedAtThree"] == nil)
  }
}
