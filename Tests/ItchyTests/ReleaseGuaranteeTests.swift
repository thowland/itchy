import Carbon.HIToolbox
import ItchyCore
import Testing

@testable import Itchy

/// Guarantees the first release makes about itself, asserted rather than
/// assumed. Most of these are the kind of property that holds on the day it is
/// written and quietly stops holding later.
@Suite("Release guarantees")
struct ReleaseGuaranteeTests {
  /// The core stores the hotkey as opaque numbers so it needs no Carbon
  /// dependency, which means the two definitions can drift. They must not.
  @Test("The stored default hotkey is the one the binding describes")
  func hotKeyDefaultsAgree() {
    let settings = AppSettings()
    let binding = HotKeyBinding(
      keyCode: settings.hotKeyCode, carbonModifiers: settings.hotKeyModifiers)
    #expect(binding == HotKeyBinding.default)
    #expect(binding.displayString == "⌃⌥Space")
  }

  /// `NFR-3.1`: in R1 and R2 Itchy makes no outbound network connection
  /// whatsoever. The MCP server arrives in R3 and the model client in R4; until
  /// then nothing in the built product should link a networking stack.
  @Test("No networking framework is linked into the application")
  func noNetworkingLinked() throws {
    let bundle = Bundle(for: AppDelegate.self)
    let binary = bundle.executableURL?.path
    let executable = try #require(binary)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
    process.arguments = ["-L", executable]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(
      decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

    // Without this the test passes vacuously whenever otool fails.
    #expect(output.contains(".dylib") || output.contains(".framework"), "otool produced nothing")

    // Frameworks that would mean the product can reach the network.
    for framework in ["Network.framework", "CFNetwork.framework"] {
      #expect(!output.contains(framework), "R1 links \(framework); NFR-3.1 says it must not")
    }
  }

  /// `NFR-3.5`: no analytics, no crash reporting service, no usage data.
  ///
  /// The test host injects XCTest's own frameworks, which are not shipped, so
  /// those are excluded by name. Everything else embedded in the bundle is
  /// something R1 would actually distribute.
  @Test("No analytics or crash-reporting dependency is shipped")
  func noTelemetry() throws {
    let bundle = Bundle(for: AppDelegate.self)
    let embedded = bundle.privateFrameworksURL
      .flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
    let shipped = embedded.filter { name in
      !name.hasPrefix("XC") && !name.hasPrefix("libXC") && name != "Testing.framework"
    }
    #expect(shipped.isEmpty, "R1 ships no embedded frameworks: \(shipped)")
  }

  /// `NFR-3.4`, D-16: the suffix is the whole mechanism, and a rename that drops
  /// it restores Spotlight indexing with nothing failing.
  @Test("Pads are stored in a directory Spotlight will not index")
  func spotlightExclusion() {
    #expect(PadStorageLayout.padsDirectoryName.hasSuffix(".noindex"))
  }

  /// `FR-1.1`: the bundle declares accessory mode, which is the real mechanism —
  /// the delegate's assertion is belt and braces.
  @Test("The bundle declares accessory mode and a minimum system version")
  func bundleDeclarations() throws {
    let bundle = Bundle(for: AppDelegate.self)
    #expect(bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    let minimum = try #require(
      bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String)
    #expect(minimum.hasPrefix("15"), "CON-5: the deployment floor is macOS 15")
  }

  /// `NFR-5.1`: every function is reachable from the keyboard. The menubar's
  /// per-pad rows carry key equivalents for the first nine pads.
  @Test("The first nine pads are reachable by key equivalent")
  func keyboardReachability() {
    let pads = (1...12).map {
      PadMetadata(name: "pad \($0)", created: .distantPast, modified: .distantPast)
    }
    let rows = MenuModel.rows(pads: pads)
    #expect(rows.prefix(9).allSatisfy { $0.keyEquivalent != nil })
  }

  @Test("The hotkey status explains itself when registration fails")
  func hotKeyStatusWording() {
    #expect(HotKeyStatusText.text(isRegistered: true).contains("used last"))
    #expect(HotKeyStatusText.text(isRegistered: false).contains("already taken"))
  }
}
