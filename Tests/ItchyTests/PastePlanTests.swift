import CoreGraphics
import Foundation
import ItchyCore
import Testing

@testable import Itchy

/// The case matrix that would otherwise be checked by pasting things by hand and
/// looking at the result (implementation plan, Sprint 3).
@Suite("Paste plan")
struct PastePlanTests {
  private func browserPaste() -> PasteDescriptor {
    PasteDescriptor(
      hasRTFD: false, hasRTF: false, hasHTML: true,
      plainText: "quoted text",
      url: URL(string: "https://example.invalid/orders/88121"),
      sourceBundleID: "com.apple.Safari", sourceAppName: "Safari", byteCount: 412)
  }

  private func screenshotPaste(width: CGFloat = 3_024, height: CGFloat = 1_964)
    -> PasteDescriptor
  {
    PasteDescriptor(
      imageSizes: [CGSize(width: width, height: height)],
      sourceBundleID: "com.apple.screencaptureui", byteCount: 4_200_000)
  }

  /// Styled mode prefers the richest representation (specification §9.4 step 4).
  @Test("Styled mode takes RTFD over everything else")
  func prefersRTFD() {
    let descriptor = PasteDescriptor(
      hasRTFD: true, hasRTF: true, hasHTML: true,
      imageSizes: [CGSize(width: 10, height: 10)], plainText: "text")
    #expect(PastePlan.plan(for: descriptor, mode: .styled).representation == .rtfd)
  }

  @Test(
    "The preference order is rtfd, rtf, html, image, plain text",
    arguments: [
      (PasteDescriptor(hasRTF: true, hasHTML: true, plainText: "t"), PasteRepresentation.rtf),
      (PasteDescriptor(hasHTML: true, plainText: "t"), .html),
      (PasteDescriptor(imageSizes: [CGSize(width: 8, height: 8)], plainText: "t"), .image),
      (PasteDescriptor(plainText: "t"), .plainText),
      (PasteDescriptor(), .nothing),
    ])
  func preferenceOrder(descriptor: PasteDescriptor, expected: PasteRepresentation) {
    #expect(PastePlan.plan(for: descriptor, mode: .styled).representation == expected)
  }

  /// `FR-4.4`: pasting styled content with an image into a plain pad yields
  /// unstyled text and no attachment.
  @Test("Plain mode reduces everything to text and discards attachments")
  func plainModeDiscards() {
    let rich = PasteDescriptor(
      hasRTFD: true, imageSizes: [CGSize(width: 4_000, height: 3_000)],
      plainText: "just the words")
    let plan = PastePlan.plan(for: rich, mode: .plain)

    #expect(plan.representation == .plainText)
    #expect(plan.discardsStyling)
    #expect(plan.downsampleTargets.isEmpty, "no image is being inserted to downsample")
  }

  @Test("Plain mode with no text at all yields nothing")
  func plainModeImageOnly() {
    let imageOnly = PasteDescriptor(imageSizes: [CGSize(width: 10, height: 10)])
    #expect(PastePlan.plan(for: imageOnly, mode: .plain).representation == .nothing)
  }

  /// `FR-4.3`: images above the threshold are downsampled on arrival.
  @Test("A Retina screenshot is scheduled for downsampling")
  func screenshotIsDownsampled() throws {
    let plan = PastePlan.plan(for: screenshotPaste(), mode: .styled)
    #expect(plan.representation == .image)
    let target = try #require(plan.downsampleTargets.first ?? nil)
    #expect(target.width == 1_600)
  }

  @Test("A small image is left alone")
  func smallImageUntouched() {
    let plan = PastePlan.plan(for: screenshotPaste(width: 400, height: 300), mode: .styled)
    #expect(plan.downsampleTargets == [nil])
  }

  @Test("Several images each get their own decision")
  func manyImages() {
    let descriptor = PasteDescriptor(
      imageSizes: [CGSize(width: 4_000, height: 2_000), CGSize(width: 100, height: 100)])
    let plan = PastePlan.plan(for: descriptor, mode: .styled)
    #expect(plan.downsampleTargets.count == 2)
    #expect(plan.downsampleTargets[0] != nil)
    #expect(plan.downsampleTargets[1] == nil)
  }

  @Test("An empty pasteboard produces no plan at all")
  func emptyPasteboard() {
    #expect(PastePlan.plan(for: PasteDescriptor(), mode: .styled) == .empty)
    #expect(PastePlan.plan(for: PasteDescriptor(), mode: .plain) == .empty)
  }

  @Test(
    "Provenance kind follows what was actually inserted",
    arguments: [
      (PasteDescriptor(hasRTFD: true), ProvenanceEntry.Kind.styledText),
      (PasteDescriptor(imageSizes: [CGSize(width: 9, height: 9)]), .image),
      (PasteDescriptor(plainText: "t"), .text),
    ])
  func provenanceKinds(descriptor: PasteDescriptor, expected: ProvenanceEntry.Kind) {
    #expect(PastePlan.plan(for: descriptor, mode: .styled).provenanceKind == expected)
  }

  @Test("A file drop is recorded as a file whatever it renders as")
  func fileDrop() {
    let descriptor = PasteDescriptor(
      hasRTFD: true,
      fileURLs: [URL(fileURLWithPath: "/tmp/notes.rtfd")])
    #expect(PastePlan.plan(for: descriptor, mode: .styled).provenanceKind == .file)
  }
}

@Suite("Provenance builder")
struct ProvenanceBuilderTests {
  private let now = Date(timeIntervalSince1970: 1_789_000_000)

  /// `FR-7.1`: source application, URL where available, and a timestamp.
  @Test("A browser paste records the application and the page")
  func browserPaste() throws {
    let descriptor = PasteDescriptor(
      hasHTML: true, plainText: "quoted",
      url: URL(string: "https://example.invalid/x"),
      sourceBundleID: "com.apple.Safari", sourceAppName: "Safari", byteCount: 412)
    let plan = PastePlan.plan(for: descriptor, mode: .styled)

    let entry = try #require(
      ProvenanceBuilder.entry(
        from: descriptor, plan: plan, insertedAt: 10, length: 6, now: now))

    #expect(entry.sourceAppName == "Safari")
    #expect(entry.sourceURL?.host() == "example.invalid")
    #expect(entry.kind == .styledText)
    #expect(entry.arrived == now)
  }

  /// `FR-7.4`: the range is recorded as it was at insertion and treated as
  /// approximate thereafter.
  @Test("The range recorded is the one at insertion")
  func rangeAtInsertion() throws {
    let descriptor = PasteDescriptor(plainText: "abc", byteCount: 3)
    let plan = PastePlan.plan(for: descriptor, mode: .styled)
    let entry = try #require(
      ProvenanceBuilder.entry(from: descriptor, plan: plan, insertedAt: 42, length: 3, now: now))
    #expect(entry.approximateRange == 42..<45)
  }

  @Test("A paste from an application supplying no URL still records the application")
  func noURL() throws {
    let descriptor = PasteDescriptor(
      plainText: "x", sourceBundleID: "com.apple.Terminal", sourceAppName: "Terminal")
    let plan = PastePlan.plan(for: descriptor, mode: .styled)
    let entry = try #require(
      ProvenanceBuilder.entry(from: descriptor, plan: plan, insertedAt: 0, length: 1, now: now))
    #expect(entry.sourceAppName == "Terminal")
    #expect(entry.sourceURL == nil)
  }

  @Test("Nothing pasted means nothing recorded")
  func nothingPasted() {
    let entry = ProvenanceBuilder.entry(
      from: PasteDescriptor(), plan: .empty, insertedAt: 0, length: 0, now: now)
    #expect(entry == nil)
  }
}
