import Foundation
import ItchyCore

/// Which pads an agent may see (`FR-8.7`, §11.5).
///
/// Nothing is exposed by default. The rule this exists to make hard to break is
/// the second one: an unexposed pad must be absent from `list_pads` *and*
/// indistinguishable from a nonexistent one when named directly, or the tool
/// surface becomes a way to confirm that a pad called "salary review" exists.
///
/// The way that is guaranteed is structural — `visible(in:)` is the only way
/// the router is given pads at all, so an unexposed pad cannot be resolved by
/// any path, rather than being filtered out at each of several call sites that
/// must all remember to.
public enum ExposurePolicy {
  public static func visible(in pads: [PadMetadata]) -> [PadMetadata] {
    pads.filter(\.isExposedToMCP)
  }

  public static func isVisible(_ pad: PadMetadata) -> Bool {
    pad.isExposedToMCP
  }
}
