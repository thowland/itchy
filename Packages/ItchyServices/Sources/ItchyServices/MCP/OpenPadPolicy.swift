import Foundation
import ItchyCore

/// Whether an agent's write may proceed (§11.6).
///
/// This exists because of a failure mode the write tools introduce and the
/// registry-aware writer removes. `StorePadWriter` is correct whenever the
/// pad's panel is closed, and wrong when it is open: the panel holds the
/// authoritative text, and its next save — on the serialisation debounce, so
/// within about 120 ms of the next keystroke, and unconditionally when the pad
/// closes — writes the panel's version over the agent's. The agent is told it
/// succeeded and nothing of what it wrote survives.
///
/// The cheap mitigation is to refuse rather than lose, and refusing is what this
/// decides. Losing a write silently is the one failure mode this project's
/// storage rules are otherwise written to prevent, and introducing it at the
/// MCP boundary alone would be odd.
///
/// When a writer can reach the open panel — Sprint 9's registry-aware one — the
/// refusal stops applying, without this file or its call site changing shape.
public enum WriteAdmission: Sendable, Equatable {
  case proceed
  case refuseBecauseOpen
}

public enum OpenPadPolicy {
  public static func admit(isOpen: Bool, writerReachesOpenPads: Bool) -> WriteAdmission {
    guard isOpen, !writerReachesOpenPads else { return .proceed }
    return .refuseBecauseOpen
  }
}

/// Whether a pad's panel is on screen.
///
/// A seam, because the answer lives in `PadWindowRegistry` on the main actor and
/// the services layer must not know that a window server exists. The default
/// says nothing is open, which is the right answer for `itchyctl` and for every
/// test that is not about this.
public protocol PadPresence: Sendable {
  func isOpen(_ id: PadID) async -> Bool
}

public struct NoPadsOpen: PadPresence {
  public init() {}
  public func isOpen(_ id: PadID) async -> Bool { false }
}

/// What an agent is told when its write is refused rather than lost.
public enum MCPWriteRefusal: Error, Sendable, Equatable {
  case padOpenInInterface

  public var message: String {
    switch self {
    case .padOpenInInterface:
      return "That pad is open in Itchy, and the window holds the authoritative "
        + "text. Writing now would be overwritten without warning. Ask again once "
        + "it is closed."
    }
  }
}
