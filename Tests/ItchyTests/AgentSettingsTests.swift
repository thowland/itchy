import AppKit
import ItchyCore
import ItchyServices
import Testing

@testable import Itchy

/// What the interface says about the agent server, and what enabling it
/// actually does (`FR-8.4`, `FR-8.10`, `NFR-3.2`, §11.8).
@Suite("Agent settings and visible state")
struct AgentSettingsTests {
  // MARK: - The states, and what they say

  @Test("Off says that nothing can reach the pads")
  func offStatus() {
    #expect(MCPSettingsModel.status(.off).contains("Nothing outside Itchy"))
    #expect(MCPServerState.off.isListening == false)
    #expect(MCPServerState.off.port == nil)
  }

  @Test("Listening names the loopback address and the port")
  func listeningStatus() {
    let status = MCPSettingsModel.status(.listening(port: 8_899))
    #expect(status.contains("127.0.0.1:8899"))
    #expect(status.contains("only this machine") || status.contains("Only this machine"))
    #expect(MCPServerState.listening(port: 8_899).port == 8_899)
    #expect(MCPServerState.listening(port: 8_899).isListening)
  }

  /// A toggle that says "on" while the port is taken by something else is a
  /// toggle that lies, which is why failure is one of the states rather than a
  /// silent return to off.
  @Test("A failure is a state of its own, and reads as a warning")
  func failureStatus() {
    let state = MCPServerState.failed(reason: "that port is already in use.")
    #expect(MCPSettingsModel.status(state).contains("already in use"))
    #expect(MCPSettingsModel.isWarning(state))
    #expect(MCPSettingsModel.isWarning(.off) == false)
    #expect(MCPSettingsModel.isWarning(.listening(port: 1)) == false)
    #expect(MCPSettingsModel.isWarning(.starting) == false)
  }

  @Test("Every state says something")
  func everyStateSpeaks() {
    let all: [MCPServerState] = [.off, .starting, .listening(port: 1), .failed(reason: "x")]
    #expect(all.allSatisfy { !MCPSettingsModel.status($0).isEmpty })
  }

  /// A port that is taken is the failure that will actually happen, and
  /// "address already in use" is not what it should say.
  @Test("A failure to bind is explained in the person's terms")
  func failureWording() {
    #expect(
      ServerFailureText.of(LoopbackListener.ListenerError.couldNotBind("POSIXErrorCode: 48"))
        .contains("already in use"))
    #expect(ServerFailureText.of(LoopbackListener.ListenerError.invalidPort(-1)).contains("-1"))
    #expect(ServerFailureText.of(LoopbackListener.ListenerError.notRunning).isEmpty == false)
    #expect(ServerFailureText.of(PadStoreFault.diskSpaceExhausted).contains("unexpected"))
  }

  // MARK: - The port

  @Test("The port field offers only ports an accessory application can bind")
  func portRange() {
    #expect(MCPSettingsModel.portRange.lowerBound == MCPBounds.lowestUnprivilegedPort)
    #expect(MCPSettingsModel.portRange.upperBound == MCPBounds.maximumPort)
    #expect(MCPSettingsModel.clampPort(22) == MCPBounds.lowestUnprivilegedPort)
    #expect(MCPSettingsModel.clampPort(70_000) == MCPBounds.maximumPort)
    #expect(MCPSettingsModel.clampPort(8_899) == 8_899)
  }

  /// Otherwise a person reads the field, reads the shim's error, and has no way
  /// to connect the two.
  @Test("The bound port is named when it is not the configured one")
  func portNote() {
    #expect(MCPSettingsModel.portNote(configured: 8_899, state: .listening(port: 8_899)) == nil)
    #expect(MCPSettingsModel.portNote(configured: 8_899, state: .off) == nil)
    let note = MCPSettingsModel.portNote(configured: 8_899, state: .listening(port: 51_234))
    #expect(note?.contains("51234") == true)
    #expect(note?.contains("8899") == true)
  }

  // MARK: - The token

  @Test("The token is hidden until it is asked for")
  func tokenDisplay() {
    let token = "abcdefgh"
    #expect(MCPSettingsModel.tokenDisplay(token, revealed: true) == token)
    #expect(MCPSettingsModel.tokenDisplay(token, revealed: false) == "••••••••")
    #expect(MCPSettingsModel.tokenDisplay(nil, revealed: true).contains("Not generated"))
    #expect(MCPSettingsModel.tokenDisplay("", revealed: true).contains("Not generated"))
    #expect(MCPSettingsModel.revealLabel(revealed: false) == "Show")
    #expect(MCPSettingsModel.revealLabel(revealed: true) == "Hide")
  }

  /// An agent that stops working after a click the person did not connect to it
  /// is a support question rather than a security property.
  @Test("Regeneration says that the previous token stops working")
  func regenerationNote() {
    #expect(MCPSettingsModel.regenerateNote.contains("straight away"))
  }

  // MARK: - Exposure, NFR-3.2

  @Test("An exposed pad says so even while the server is off")
  func exposureVisibility() {
    #expect(StatusBarModel.showsExposure(serverEnabled: false, isExposed: true))
    #expect(StatusBarModel.showsExposure(serverEnabled: true, isExposed: false))
    // Before either is true, the word would answer a question nobody has asked.
    #expect(StatusBarModel.showsExposure(serverEnabled: false, isExposed: false) == false)
  }

  @Test("Exposing a pad says what it means, and what is still missing")
  func exposureNote() {
    #expect(MCPSettingsModel.exposureNote(isExposed: false, serverEnabled: true) == nil)
    #expect(
      MCPSettingsModel.exposureNote(isExposed: true, serverEnabled: false)?
        .contains("switched on") == true)
    #expect(
      MCPSettingsModel.exposureNote(isExposed: true, serverEnabled: true)?
        .contains("replace") == true)
  }

  // MARK: - The menubar, §11.8

  @Test("The menubar says the server is listening, and on which port")
  func menuRow() {
    #expect(MenuModel.serverRow(.listening(port: 8_899)) == "Agents: listening on 8899")
    #expect(MenuModel.serverRow(.starting)?.contains("starting") == true)
    #expect(MenuModel.serverRow(.failed(reason: "x"))?.contains("could not start") == true)
  }

  /// The requirement is that the state is visible when there is a state, not
  /// that a line of the menu is permanently spent saying "no".
  @Test("An off server takes no room in the menu")
  func menuRowSilentWhenOff() {
    #expect(MenuModel.serverRow(.off) == nil)
  }
}
