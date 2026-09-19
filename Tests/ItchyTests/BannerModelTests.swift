import AppKit
import ItchyCore
import Testing

@testable import Itchy

/// `FR-8.9` and §11.7: a write from outside the application is indicated on the
/// pad, distinguishably from the person's own editing — and where it cannot be
/// undone, it says so rather than offering a button that does the wrong thing.
@Suite("External-write banner")
struct BannerModelTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func pad(
    writtenAt: Date? = nil, by origin: WriteOrigin = .mcp(client: "claude"), delta: Int = 12
  ) -> PadMetadata {
    var pad = PadMetadata(name: "scratch", created: now, modified: now)
    if let writtenAt {
      pad.externalWriteMarker = ExternalWriteMarker(
        at: writtenAt, origin: origin, characterDelta: delta)
    }
    return pad
  }

  @Test("A pad nothing has written to shows nothing")
  func noMarker() {
    #expect(BannerModel.state(for: pad(), now: now) == .hidden)
  }

  @Test("A recent write is shown, and says who wrote and how much")
  func recentWrite() {
    let state = BannerModel.state(for: pad(writtenAt: now.addingTimeInterval(-30)), now: now)
    guard case .shown(let text, let undo) = state else {
      Issue.record("expected a shown banner")
      return
    }
    #expect(text == "claude wrote 12 characters just now.")
    #expect(undo == .available)
  }

  /// Beyond a day it is history rather than news, and the pad's own text is the
  /// record.
  @Test("A write from yesterday is no longer news")
  func staleWrite() {
    let old = now.addingTimeInterval(-BannerModel.lifetime - 1)
    #expect(BannerModel.state(for: pad(writtenAt: old), now: now) == .hidden)
  }

  /// A clock that went backwards — a timezone change, a corrected system time —
  /// should not produce a banner claiming a write from the future.
  @Test("A marker dated in the future is not shown")
  func futureWrite() {
    let ahead = now.addingTimeInterval(60)
    #expect(BannerModel.state(for: pad(writtenAt: ahead), now: now) == .hidden)
  }

  /// D-9's consequence: the text view's undo stack begins when the panel opens,
  /// so a write that arrived while it was closed has nothing on it to revert.
  /// A button that looked live would undo the person's own last edit instead.
  @Test("A write that arrived while the pad was closed offers no undo")
  func closedPadWrite() {
    let state = BannerModel.state(
      for: pad(writtenAt: now.addingTimeInterval(-10)), now: now, wasOpen: false)
    guard case .shown(_, let undo) = state else {
      Issue.record("expected a shown banner")
      return
    }
    #expect(undo == .unavailableWrittenWhileClosed)
    #expect(BannerModel.undoLabel(undo).contains("no undo"))
    #expect(BannerModel.undoLabel(.available) == "Undo")
  }

  @Test("Who wrote is named when the client gave a name")
  func authors() {
    #expect(BannerModel.author(of: .mcp(client: "claude")) == "claude")
    #expect(BannerModel.author(of: .mcp(client: nil)) == "An agent")
    #expect(BannerModel.author(of: .mcp(client: "")) == "An agent")
    #expect(BannerModel.author(of: .transform("flatten")).contains("flatten"))
    #expect(BannerModel.author(of: .user) == "You")
  }

  @Test("What changed is said coarsely, and an emptied pad says so")
  func changes() {
    #expect(BannerModel.change(1) == "wrote 1 character")
    #expect(BannerModel.change(40) == "wrote 40 characters")
    #expect(BannerModel.change(0) == "emptied this pad")
  }

  @Test("When it happened is said in the units a person would use")
  func ages() {
    #expect(BannerModel.age(from: now, to: now) == "just now")
    #expect(BannerModel.age(from: now.addingTimeInterval(-60), to: now) == "1 minute ago")
    #expect(BannerModel.age(from: now.addingTimeInterval(-600), to: now) == "10 minutes ago")
    #expect(BannerModel.age(from: now.addingTimeInterval(-7_200), to: now) == "2 hours ago")
  }

  @Test("The view reads the shown case through one seam, and nothing from hidden")
  func viewUnwrapping() {
    let shown = BannerState.shown(text: "something", undo: .available)
    #expect(BannerText.message(shown) == "something")
    #expect(BannerText.offer(shown) == .available)
    #expect(BannerText.message(.hidden).isEmpty)
    #expect(shown.isShown)
    #expect(BannerState.hidden.isShown == false)
  }

  @Test("Only an external write raises the banner's routing")
  func routing() {
    let id = PadID()
    #expect(ExternalWriteRouting.pad(in: .contentChangedExternally(id, origin: .user)) == id)
    #expect(ExternalWriteRouting.pad(in: .metadataChanged(id)) == nil)
    #expect(ExternalWriteRouting.pad(in: .padAdded(id)) == nil)
  }
}

/// `FR-8.8`: an agent's write into an open panel is one undo from reverted, and
/// the Edit menu names it.
@Suite("Agent write plan")
struct AgentWritePlanTests {
  @Test("Replacing covers the whole pad; appending covers nothing and lands at the end")
  func ranges() {
    #expect(AgentWritePlan.range(for: .replaceAll, length: 40) == NSRange(location: 0, length: 40))
    #expect(AgentWritePlan.range(for: .append, length: 40) == NSRange(location: 40, length: 0))
    #expect(AgentWritePlan.range(for: .append, length: 0) == NSRange(location: 0, length: 0))
  }

  /// "Undo Write from claude" says which of the things running on this machine
  /// did it. "Undo" alone says only that something did.
  @Test("The undo step is named, and names the client when there is one")
  func names() {
    #expect(
      AgentWritePlan.actionName(for: .replaceAll, origin: .mcp(client: "claude"))
        == "Write from claude")
    #expect(
      AgentWritePlan.actionName(for: .append, origin: .mcp(client: "claude"))
        == "Append from claude")
    #expect(AgentWritePlan.actionName(for: .append, origin: .mcp(client: nil)) == "Agent Append")
    #expect(AgentWritePlan.actionName(for: .replaceAll, origin: .user) == "Agent Write")
  }
}
