import Foundation
import Testing

@testable import ItchyCore

/// Every case here runs against a controlled sleeper, so no real time passes.
/// A test that waits 750 ms to observe a debounce is a test that gets deleted
/// for being slow (specification §6.6).
@Suite("Save scheduler")
struct SaveSchedulerTests {
  @Test("The debounce interval is the one the requirement states")
  func intervalIsSevenFifty() {
    #expect(SaveScheduler.debounce == .milliseconds(750))
  }

  @Test("Nothing is written until the interval elapses")
  func noWriteBeforeTheInterval() async throws {
    let sleeper = ControlledSleeper()
    let scheduler = SaveScheduler(interval: .milliseconds(750), sleeper: sleeper)
    let flushed = Counter()

    await scheduler.schedule(PadID()) { await flushed.increment() }
    await sleeper.waitUntilSleeping()

    #expect(await flushed.value == 0)
    #expect(await sleeper.requestedIntervals == [.milliseconds(750)])

    await sleeper.advance()
    await flushed.waitFor(1)
    #expect(await flushed.value == 1)
  }

  @Test("Staging again restarts the interval rather than adding a second write")
  func restagingCoalesces() async throws {
    let sleeper = ControlledSleeper()
    let scheduler = SaveScheduler(interval: .milliseconds(750), sleeper: sleeper)
    let flushed = Counter()
    let id = PadID()

    await scheduler.schedule(id) { await flushed.increment() }
    await sleeper.waitUntilSleeping()
    await scheduler.schedule(id) { await flushed.increment() }

    // Releases the cancelled sleep and the live one together, so whether the
    // replacement task has reached its sleep yet does not decide the outcome.
    await sleeper.releaseAll()
    await flushed.waitFor(1)

    // The cancelled task must not also flush: two stagings, one write.
    #expect(await flushed.value == 1)
    #expect(await scheduler.pendingCount == 0)
  }

  @Test("A cancelled debounce never writes")
  func cancellationPreventsTheWrite() async throws {
    let sleeper = ControlledSleeper()
    let scheduler = SaveScheduler(interval: .milliseconds(750), sleeper: sleeper)
    let flushed = Counter()
    let id = PadID()

    await scheduler.schedule(id) { await flushed.increment() }
    await sleeper.waitUntilSleeping()
    await scheduler.cancel(id)
    await sleeper.interrupt()

    #expect(!(await scheduler.isPending(id)))
    #expect(await flushed.value == 0)
  }

  @Test("Pads are debounced independently")
  func perPadIndependence() async throws {
    let sleeper = ControlledSleeper()
    let scheduler = SaveScheduler(interval: .milliseconds(750), sleeper: sleeper)
    let first = PadID()
    let second = PadID()

    await scheduler.schedule(first) {}
    await scheduler.schedule(second) {}
    await sleeper.waitUntilSleeping(count: 2)

    #expect(await scheduler.pendingCount == 2)
    await scheduler.cancel(first)
    #expect(!(await scheduler.isPending(first)))
    #expect(await scheduler.isPending(second))
  }

  @Test("Cancelling all clears every pending write")
  func cancelAll() async throws {
    let sleeper = ControlledSleeper()
    let scheduler = SaveScheduler(interval: .milliseconds(750), sleeper: sleeper)
    await scheduler.schedule(PadID()) {}
    await scheduler.schedule(PadID()) {}
    await sleeper.waitUntilSleeping(count: 2)

    await scheduler.cancelAll()
    #expect(await scheduler.pendingCount == 0)
  }
}

/// A counter a test can wait on without sleeping and without spinning.
actor Counter {
  private var count = 0
  private var target: Int?
  private var waiter: CheckedContinuation<Void, Never>?

  func increment() {
    count += 1
    guard let target, count >= target else { return }
    let continuation = waiter
    waiter = nil
    self.target = nil
    continuation?.resume()
  }

  var value: Int { count }

  func waitFor(_ wanted: Int) async {
    guard count < wanted else { return }
    target = wanted
    await withCheckedContinuation { continuation in
      waiter = continuation
    }
  }
}
