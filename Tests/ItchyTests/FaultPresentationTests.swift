import ItchyCore
import Testing

@testable import Itchy

/// Specification §6.7 states the rule this suite exists to hold: no fault path
/// may ever produce an empty editable pad over unreadable content, because that
/// would destroy the content on the next save.
@Suite("Fault presentation")
struct FaultPresentationTests {
  @Test("No fault means the editor is shown")
  func noFault() {
    #expect(FaultPresentation.presentation(for: nil) == nil)
    #expect(FaultPresentation.allowsEditing(nil))
  }

  @Test(
    "A fault that prohibits editing never yields an editor",
    arguments: [
      PadStoreFault.contentMissing(PadID()),
      .contentUnreadable(PadID(), underlying: "x"),
      .metadataUnreadable(PadID(), underlying: "x"),
      .metadataSchemaTooNew(PadID(), found: 9, supported: 1),
    ])
  func prohibitingFaults(fault: PadStoreFault) throws {
    let presentation = try #require(FaultPresentation.presentation(for: fault))
    #expect(!presentation.allowsEditing)
    #expect(!FaultPresentation.allowsEditing(fault))
    #expect(!presentation.headline.isEmpty)
    #expect(!presentation.detail.isEmpty)
    #expect(presentation.offersRevealInFinder, "the user should be able to look at the files")
  }

  @Test(
    "A fault that does not concern readable content still allows editing",
    arguments: [
      PadStoreFault.writeFailed(PadID(), underlying: "x"),
      .shadowDesynchronised(PadID()),
      .diskSpaceExhausted,
    ])
  func permittingFaults(fault: PadStoreFault) throws {
    let presentation = try #require(FaultPresentation.presentation(for: fault))
    #expect(presentation.allowsEditing)
    #expect(FaultPresentation.allowsEditing(fault))
  }

  @Test("Every fault has a headline a person can read")
  func headlines() {
    let faults: [PadStoreFault] = [
      .metadataUnreadable(PadID(), underlying: ""),
      .metadataSchemaTooNew(PadID(), found: 0, supported: 0),
      .contentUnreadable(PadID(), underlying: ""),
      .contentMissing(PadID()),
      .shadowDesynchronised(PadID()),
      .indexUnreadable(underlying: ""),
      .writeFailed(nil, underlying: ""),
      .padLimitReached(limit: 0),
      .diskSpaceExhausted,
      .unknownPad(PadID()),
    ]
    for fault in faults {
      let presentation = FaultPresentation.presentation(for: fault)
      #expect(presentation?.headline.isEmpty == false, "no headline for \(fault)")
    }
  }
}

@Suite("Settings model")
struct SettingsModelTests {
  /// `FR-2.1`: the control is one of three enforcement points, not the only one.
  @Test("The control's range is the permitted range")
  func range() {
    #expect(SettingsModel.padCountRange.lowerBound == PadBounds.minimumCount)
    #expect(SettingsModel.padCountRange.upperBound == PadBounds.hardCeiling)
  }

  @Test("The control clamps as well as offering a range")
  func clamping() {
    #expect(SettingsModel.clampPadCount(500) == PadBounds.hardCeiling)
    #expect(SettingsModel.clampPadCount(-1) == PadBounds.minimumCount)
  }

  @Test("The ceiling is stated, not merely enforced")
  func caption() {
    #expect(SettingsModel.padCountCaption.contains("20"))
  }

  /// `FR-2.2`: the setting must say that lowering affects creation only.
  @Test("Lowering below the pads that exist explains what will not happen")
  func loweringNotice() throws {
    let notice = try #require(SettingsModel.loweringNotice(padCount: 2, existing: 5))
    #expect(notice.contains("nothing is deleted"))
    #expect(SettingsModel.loweringNotice(padCount: 9, existing: 5) == nil)
  }

  @Test("Both modes have a label that explains the difference")
  func modeLabels() {
    #expect(SettingsModel.defaultModeLabel(.styled).contains("images"))
    #expect(SettingsModel.defaultModeLabel(.plain).contains("text"))
  }
}

@Suite("Pad mode labels")
struct PadModeLabelTests {
  @Test("The opposite of each mode is the other one")
  func opposites() {
    #expect(PadModeLabel.opposite(.styled) == .plain)
    #expect(PadModeLabel.opposite(.plain) == .styled)
  }

  @Test("The toggle is named for where it goes, not where it is")
  func labels() {
    #expect(PadModeLabel.other(.styled) == "Plain")
    #expect(PadModeLabel.other(.plain) == "Styled")
  }
}

@Suite("Deletion prompt")
struct DeletionPromptTests {
  /// `CON-2` prohibits prompts; `FR-2.6` makes deletion the one exception,
  /// because the action is destructive rather than organisational.
  @Test("The prompt names the pad being deleted")
  func namesThePad() {
    let pad = PadMetadata(name: "json dump", created: .distantPast, modified: .distantPast)
    #expect(DeletionPrompt.title(for: pad).contains("json dump"))
  }

  @Test("With no pad selected the prompt is still coherent")
  func noPad() {
    #expect(!DeletionPrompt.title(for: nil).isEmpty)
  }

  @Test("The message says the action cannot be undone")
  func message() {
    #expect(DeletionPrompt.message.contains("cannot be undone"))
  }
}
