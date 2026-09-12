import Testing

@testable import UnderCovered

@Test("Only the covered path is exercised, on purpose")
func onlyOnePath() {
  #expect(Neglected.covered(1) == 2)
}
