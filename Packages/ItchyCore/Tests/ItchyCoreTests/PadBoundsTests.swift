import Testing

@testable import ItchyCore

/// `FR-2.1` requires the ceiling to hold at three enforcement points, and its
/// acceptance criterion specifically includes a hand-edited stored value — so the
/// read-path clamp is a requirement, not a nicety.
@Suite("Pad bounds")
struct PadBoundsTests {
  @Test("The default is nine and the ceiling is twenty")
  func defaults() {
    #expect(PadBounds.defaultCount == 9)
    #expect(PadBounds.hardCeiling == 20)
  }

  @Test(
    "A requested count is clamped into range",
    arguments: [
      (requested: -5, expected: 1),
      (requested: 0, expected: 1),
      (requested: 1, expected: 1),
      (requested: 9, expected: 9),
      (requested: 20, expected: 20),
      (requested: 21, expected: 20),
      (requested: 500, expected: 20),
      (requested: Int.max, expected: 20),
    ])
  func clamping(requested: Int, expected: Int) {
    #expect(PadBounds.clamp(requested) == expected)
  }

  @Test("A stored value above the ceiling is detected so it can be written back")
  func rewriteDetection() {
    #expect(PadBounds.needsRewrite(40))
    #expect(PadBounds.needsRewrite(0))
    #expect(!PadBounds.needsRewrite(9))
    #expect(!PadBounds.needsRewrite(20))
  }

  @Test("Creation refuses past the configured limit, not past the ceiling")
  func creationHonoursTheConfiguredLimit() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load(padLimit: 2)

    _ = try await store.createPad(name: "one")
    _ = try await store.createPad(name: "two")

    await #expect(throws: PadStoreFault.padLimitReached(limit: 2)) {
      _ = try await store.createPad(name: "three")
    }
  }

  @Test("A stored limit above the ceiling is clamped on load")
  func loadClampsStoredLimit() async {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load(padLimit: 9999)
    #expect(await store.padLimit == PadBounds.hardCeiling)
  }

  @Test("Lowering the limit below the pads present hides nothing (FR-2.2)")
  func loweringNeverHides() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load(padLimit: 5)
    for name in ["a", "b", "c", "d"] {
      _ = try await store.createPad(name: name)
    }

    await store.setPadLimit(2)

    #expect(await store.pads.count == 4)
    #expect(await store.padLimit == 2)
    await #expect(throws: PadStoreFault.padLimitReached(limit: 2)) {
      _ = try await store.createPad(name: "e")
    }
  }
}
