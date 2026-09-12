import ItchyCore
import Testing

@testable import Itchy

@Suite("Status bar model")
struct StatusBarModelTests {
  private func pad(
    _ name: String = "scratch",
    mode: PadMode = .styled,
    provenance: [ProvenanceEntry] = [],
    exposed: Bool = false,
    routing: RoutingPolicy = .localOnly
  ) -> PadMetadata {
    PadMetadata(
      name: name, mode: mode, created: .distantPast, modified: .distantPast,
      provenance: provenance, isExposedToMCP: exposed, routingPolicy: routing)
  }

  /// `FR-3.6`: the pad's state is legible from the panel. In R1 that is its name
  /// and its mode, and nothing else exists yet to show.
  @Test("R1 shows name and mode")
  func firstRelease() {
    let segments = StatusBarModel.segments(for: pad("notes", mode: .plain))
    #expect(segments.map(\.kind) == [.name, .mode])
    #expect(segments.map(\.text) == ["notes", "plain"])
  }

  @Test("Provenance appears only once something has been pasted")
  func provenanceSegment() {
    #expect(!StatusBarModel.segments(for: pad()).contains { $0.kind == .provenance })

    let entry = ProvenanceEntry(arrived: .distantPast, byteCount: 1, kind: .text)
    let one = StatusBarModel.segments(for: pad(provenance: [entry]))
    #expect(one.first { $0.kind == .provenance }?.text == "1 paste")

    let two = StatusBarModel.segments(for: pad(provenance: [entry, entry]))
    #expect(two.first { $0.kind == .provenance }?.text == "2 pastes")
  }

  /// The status bar grows by release rather than being restructured
  /// (specification §10).
  @Test("Exposure and routing appear only in the releases that introduce them")
  func laterReleases() {
    let segments = StatusBarModel.segments(
      for: pad(exposed: true, routing: .remotePermitted),
      showsExposure: true, showsRouting: true)
    #expect(segments.map(\.kind) == [.name, .mode, .exposure, .routing])
    #expect(segments.first { $0.kind == .exposure }?.text == "exposed")
    #expect(segments.first { $0.kind == .routing }?.text == "remote ok")
  }

  @Test("An unexposed pad says so rather than staying silent")
  func privateByDefault() {
    let segments = StatusBarModel.segments(for: pad(), showsExposure: true)
    #expect(segments.first { $0.kind == .exposure }?.text == "private")
  }

  @Test(
    "Every routing policy has a label",
    arguments: RoutingPolicy.allCases)
  func routingLabels(policy: RoutingPolicy) {
    #expect(!StatusBarModel.routingLabel(policy).isEmpty)
  }

  /// Specification §6.7: a faulted pad opens onto the fault, not onto an editor.
  @Test("A fault is surfaced on the pad itself")
  func fault() {
    let target = pad()
    let segments = StatusBarModel.segments(for: target, fault: .contentMissing(target.id))
    let fault = try? #require(segments.first { $0.kind == .fault })
    #expect(fault?.text.contains("missing") == true)
  }
}
