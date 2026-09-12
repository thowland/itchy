import Testing

@testable import ItchyCore

@Test("Core module exposes the current on-disk schema version")
func schemaVersionIsOne() {
  #expect(ItchyCore.schemaVersion == 1)
}
