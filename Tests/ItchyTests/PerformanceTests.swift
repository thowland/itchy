import ItchyCore
import XCTest

@testable import Itchy

/// `NFR-1.1` is a number, so it is measured rather than asserted by feel.
///
/// 250 ms at the ninety-fifth percentile from hotkey to a focused, typeable pad,
/// against a fixture of nine pads at realistic sizes including one at the size
/// marker. The first iteration after launch is included rather than discarded as
/// a warm-up, because it is the iteration the user actually experiences.
@MainActor
final class PerformanceTests: XCTestCase {
  private var root: URL!

  override func setUp() async throws {
    // A test that runs long here has hung, not found a slow path: the fixture is
    // nine small files on a local disk (see TestTiming).
    executionTimeAllowance = 10
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-perf-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try await seedRealisticPads()
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: root)
  }

  /// Nine pads, one of them at the size marker (`FR-5.9`), which is the fixture
  /// the requirement names.
  private func seedRealisticPads() async throws {
    let store = PadStore(layout: PadStorageLayout(root: root))
    await store.load()
    for index in 0..<PadBounds.defaultCount {
      let pad = try await store.createPad(name: "pad \(index)")
      let bytes =
        index == 0
        ? PadStore.sizeMarkerThreshold + 1
        : 40_000
      await store.stage(
        PadContent(
          bundle: ["TXT.rtf": Data(repeating: 0x41, count: bytes)],
          plainText: String(repeating: "a", count: min(bytes, 40_000))),
        for: pad.id, origin: .user)
    }
    try await store.flushAll()
  }

  private func makeCoordinator() -> PadCoordinator {
    let layout = PadStorageLayout(root: root)
    return PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())
  }

  /// Launch must not block on reading pad content (`FR-1.6`), which is what
  /// makes the budget reachable at all.
  func testLaunchDoesNotReadContent() async {
    let coordinator = makeCoordinator()
    await coordinator.start()
    XCTAssertEqual(coordinator.pads.count, PadBounds.defaultCount)

    let plan = LaunchPlan.plan(for: coordinator.pads)
    XCTAssertFalse(plan.readsContentEagerly)
  }

  /// The number itself. Twenty trials, first included, ninety-fifth percentile
  /// under 250 ms.
  ///
  /// Skipped on CI by `Scripts/test.sh`, not by anything in here (D-32). The
  /// budget is a claim about the machine somebody types on, and a hosted runner
  /// is virtualised, shares its host and composites without a GPU, so the number
  /// it produces measures the runner. `testLaunchDoesNotReadContent` is the part
  /// of this file that still runs there, and it is the one that would catch the
  /// only change that could genuinely break the budget.
  func testHotKeyToTypeablePadIsUnderBudget() async throws {
    let coordinator = makeCoordinator()
    await coordinator.start()
    let target = try XCTUnwrap(coordinator.pads.first)

    var durations: [TimeInterval] = []
    for _ in 0..<20 {
      let started = CFAbsoluteTimeGetCurrent()
      coordinator.perform(.open(target.id))
      await waitUntilOpen(coordinator, target.id)
      durations.append(CFAbsoluteTimeGetCurrent() - started)
      coordinator.perform(.close(target.id))
      await waitUntilClosed(coordinator)
    }

    let sorted = durations.sorted()
    let percentile95 = sorted[Int(Double(sorted.count) * 0.95) - 1]
    let median = sorted[sorted.count / 2]
    print(
      "NFR-1.1: median \(Int(median * 1000)) ms, "
        + "p95 \(Int(percentile95 * 1000)) ms, budget 250 ms")
    XCTAssertLessThan(
      percentile95, 0.250,
      "NFR-1.1: 95th percentile hotkey-to-pad was \(Int(percentile95 * 1000)) ms")
  }

  /// Fails rather than returning quietly, so a stalled panel is reported as a
  /// stall instead of poisoning the measurement with a bogus duration.
  private func waitUntilOpen(
    _ coordinator: PadCoordinator, _ padID: PadID,
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    await wait(
      for: { coordinator.openPanelCount > 0 }, description: "panel to open",
      file: file, line: line)
  }

  private func waitUntilClosed(
    _ coordinator: PadCoordinator,
    file: StaticString = #filePath, line: UInt = #line
  ) async {
    await wait(
      for: { coordinator.openPanelCount == 0 }, description: "panel to close",
      file: file, line: line)
  }

  private func wait(
    for condition: @MainActor () -> Bool, description: String,
    file: StaticString, line: UInt
  ) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < deadline {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(2))
    }
    XCTFail("timed out waiting for \(description)", file: file, line: line)
  }
}
