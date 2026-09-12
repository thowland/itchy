import Carbon.HIToolbox
import ItchyCore
import Testing

@testable import Itchy

/// `FR-1.4`'s toggle is the part most likely to be quietly wrong, because
/// "already frontmost and focused" is ambiguous for a non-activating panel.
@Suite("Hot key action")
struct HotKeyActionTests {
  private func pad(_ name: String) -> PadMetadata {
    PadMetadata(name: name, created: .distantPast, modified: .distantPast)
  }

  @Test("With no pads at all the hotkey creates one")
  func noPads() {
    #expect(
      HotKeyAction.decide(pads: [], lastOpened: nil, frontmostKeyPad: nil) == .createAndOpen)
  }

  @Test("The target is the most recently opened pad")
  func targetsLastOpened() {
    let first = pad("a")
    let second = pad("b")
    #expect(
      HotKeyAction.decide(pads: [first, second], lastOpened: second.id, frontmostKeyPad: nil)
        == .open(second.id))
  }

  @Test("With nothing opened yet the target is the first slot")
  func targetsFirstSlot() {
    let first = pad("a")
    let second = pad("b")
    #expect(
      HotKeyAction.decide(pads: [first, second], lastOpened: nil, frontmostKeyPad: nil)
        == .open(first.id))
  }

  /// A pad can be deleted while still recorded as last opened.
  @Test("A stale last-opened pad falls back to the first slot")
  func staleLastOpened() {
    let first = pad("a")
    #expect(
      HotKeyAction.decide(pads: [first], lastOpened: PadID(), frontmostKeyPad: nil)
        == .open(first.id))
  }

  /// The toggle: pressing again while the target is frontmost and focused puts
  /// it away.
  @Test("Pressing while the target is frontmost and focused closes it")
  func togglesClosed() {
    let target = pad("a")
    #expect(
      HotKeyAction.decide(pads: [target], lastOpened: target.id, frontmostKeyPad: target.id)
        == .close(target.id))
  }

  /// Focus being on a *different* pad is not the toggle case — the user is
  /// asking for the target, not putting the other one away.
  @Test("Another pad having focus still opens the target")
  func otherPadFocused() {
    let first = pad("a")
    let second = pad("b")
    #expect(
      HotKeyAction.decide(pads: [first, second], lastOpened: first.id, frontmostKeyPad: second.id)
        == .open(first.id))
  }

  @Test("A visible but unfocused target is brought forward, not closed")
  func visibleButUnfocused() {
    let target = pad("a")
    #expect(
      HotKeyAction.decide(pads: [target], lastOpened: target.id, frontmostKeyPad: nil)
        == .open(target.id))
  }
}

@Suite("Hot key binding")
struct HotKeyBindingTests {
  /// D-6: ⌃⌥Space, and Carbon masks because `RegisterEventHotKey` takes those.
  @Test("The default binding is Control-Option-Space")
  func defaultBinding() {
    let binding = HotKeyBinding.default
    #expect(binding.keyCode == UInt32(kVK_Space))
    #expect(binding.carbonModifiers & UInt32(controlKey) != 0)
    #expect(binding.carbonModifiers & UInt32(optionKey) != 0)
    #expect(binding.displayString == "⌃⌥Space")
  }

  @Test("A binding with no modifiers is refused")
  func requiresModifiers() {
    #expect(!HotKeyBinding(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: 0).isValid)
    #expect(HotKeyBinding.default.isValid)
  }

  @Test(
    "Modifier symbols appear in the conventional order",
    arguments: [
      (UInt32(cmdKey), "⌘"),
      (UInt32(controlKey | cmdKey), "⌃⌘"),
      (UInt32(controlKey | optionKey | shiftKey | cmdKey), "⌃⌥⇧⌘"),
    ])
  func modifierOrder(mask: UInt32, expected: String) {
    let binding = HotKeyBinding(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: mask)
    #expect(binding.displayString == expected + "J")
  }

  @Test("Named keys read as their symbol rather than a number")
  func namedKeys() {
    #expect(HotKeyBinding.keyName(for: UInt32(kVK_Space)) == "Space")
    #expect(HotKeyBinding.keyName(for: UInt32(kVK_Escape)) == "⎋")
    #expect(HotKeyBinding.keyName(for: UInt32(kVK_ANSI_Z)) == "Z")
  }

  @Test("An unmapped key still produces something legible")
  func unmappedKey() {
    #expect(!HotKeyBinding.keyName(for: 999).isEmpty)
  }

  @Test("Modifier flags convert into Carbon masks")
  func carbonConversion() {
    let flags = NSEventModifierFlagsProxy(control: true, option: true)
    #expect(HotKeyBinding.carbonModifiers(from: flags) == UInt32(controlKey | optionKey))
    #expect(HotKeyBinding.carbonModifiers(from: NSEventModifierFlagsProxy()) == 0)
  }

  @Test("A binding round-trips through settings")
  func codable() throws {
    let binding = HotKeyBinding(keyCode: 12, carbonModifiers: UInt32(cmdKey))
    let data = try JSONEncoder().encode(binding)
    #expect(try JSONDecoder().decode(HotKeyBinding.self, from: data) == binding)
  }
}

@Suite("Launch plan")
struct LaunchPlanTests {
  private func pad(_ name: String, pinned: Bool = false) -> PadMetadata {
    PadMetadata(name: name, created: .distantPast, modified: .distantPast, isPinned: pinned)
  }

  /// `FR-1.6`, and the reason `NFR-1.1`'s budget is reachable at all.
  @Test("Content is never read eagerly")
  func neverReadsContent() {
    #expect(!LaunchPlan.plan(for: [pad("a"), pad("b")]).readsContentEagerly)
    #expect(!LaunchPlan.plan(for: []).readsContentEagerly)
  }

  @Test("Metadata is read, because the menubar needs it to be live")
  func readsMetadata() {
    #expect(LaunchPlan.plan(for: []).readsIndexAndMetadata)
  }

  /// `FR-2.7`: pinned pads reopen, and only those.
  @Test("Only pinned pads reopen")
  func reopensPinnedOnly() {
    let plan = LaunchPlan.plan(for: [pad("a"), pad("b", pinned: true), pad("c", pinned: true)])
    #expect(plan.padsToReopen.count == 2)
  }

  @Test("With nothing pinned nothing reopens")
  func nothingPinned() {
    #expect(LaunchPlan.plan(for: [pad("a")]).padsToReopen.isEmpty)
  }
}

@Suite("Hot key capture")
struct HotKeyCaptureTests {
  /// A modifier-less binding would take a bare letter system-wide, and the user
  /// would find out by discovering that key no longer works anywhere.
  @Test("A combination with no modifiers is refused")
  func refusesBareKeys() {
    #expect(
      HotKeyCapture.binding(keyCode: UInt32(kVK_ANSI_J), flags: NSEventModifierFlagsProxy())
        == nil)
  }

  @Test("Shift alone is not enough")
  func refusesShiftOnly() {
    #expect(
      HotKeyCapture.binding(
        keyCode: UInt32(kVK_ANSI_J), flags: NSEventModifierFlagsProxy(shift: true)) == nil)
  }

  @Test("A real combination is accepted and carries its modifiers")
  func acceptsRealCombination() throws {
    let binding = try #require(
      HotKeyCapture.binding(
        keyCode: UInt32(kVK_Space),
        flags: NSEventModifierFlagsProxy(control: true, option: true)))
    #expect(binding == HotKeyBinding.default)
  }

  @Test(
    "Each single modifier other than shift is sufficient",
    arguments: [
      NSEventModifierFlagsProxy(control: true),
      NSEventModifierFlagsProxy(option: true),
      NSEventModifierFlagsProxy(command: true),
    ])
  func singleModifiers(flags: NSEventModifierFlagsProxy) {
    #expect(HotKeyCapture.binding(keyCode: UInt32(kVK_ANSI_K), flags: flags) != nil)
  }
}

@Suite("Hot key recorder title")
struct HotKeyRecorderTitleTests {
  @Test("While recording it asks for a combination")
  func recording() {
    #expect(
      HotKeyRecorderTitle.text(isRecording: true, binding: .default).contains("Press"))
  }

  @Test("Otherwise it shows the binding it holds")
  func idle() {
    #expect(
      HotKeyRecorderTitle.text(isRecording: false, binding: .default) == "⌃⌥Space")
  }
}

@Suite("Login item policy")
struct LoginItemPolicyTests {
  /// A login item created from a build directory keeps pointing there after the
  /// build is deleted, and the user finds it in System Settings with no idea
  /// what put it there.
  @Test(
    "Only an installed copy may register itself automatically",
    arguments: [
      ("/Applications/Itchy.app", true),
      ("/System/Applications/Itchy.app", true),
      ("/Users/someone/Apps/itchy/.build/DerivedData/Build/Products/Debug/Itchy.app", false),
      ("/Users/someone/Downloads/Itchy.app", false),
      ("/tmp/Itchy.app", false),
    ])
  func installedOnly(path: String, expected: Bool) {
    #expect(LoginItemPolicy.mayRegisterAutomatically(bundlePath: path) == expected)
  }

  @Test("Being installed is about where the bundle lives, nothing else")
  func installedDetection() {
    #expect(LoginItemPolicy.isInstalled(bundlePath: "/Applications/Itchy.app"))
    #expect(!LoginItemPolicy.isInstalled(bundlePath: "/Applications-elsewhere/Itchy.app"))
  }
}
