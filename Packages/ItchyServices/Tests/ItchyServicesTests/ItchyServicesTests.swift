import Testing

@testable import ItchyServices

@Test("Services reads the schema version through Core")
func servicesDefersToCore() {
  #expect(ItchyServices.schemaVersion == 1)
}
