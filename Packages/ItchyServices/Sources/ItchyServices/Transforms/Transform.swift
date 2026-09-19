import Foundation
import ItchyCore

/// A single operation over a pad's contents (`FR-6.1`).
///
/// The protocol makes no structural distinction between the deterministic
/// transforms of specification §7.2 and the model-backed ones arriving in R4:
/// both are this type, appear in the same menu, and are told apart only by
/// progress and cancellation. `apply` is therefore `async` from the start, even
/// though every transform in this sprint returns immediately — making it `async`
/// later would be a breaking change at exactly the moment we would least want
/// to make one.
public protocol Transform: Sendable {
  /// Stable across releases. It is the identifier MCP will name a transform by
  /// and the one that appears in logs, so renaming a title must not change it.
  var id: String { get }
  /// Shown in the menu, and used as the undo action name (`FR-6.5`).
  var title: String { get }
  /// Gates against the pad's `RoutingPolicy` from R4 (§12). Every transform in
  /// the deterministic set answers `false`.
  var requiresNetwork: Bool { get }
  /// Whether the transform is offered for this input (`FR-6.3`). Runs on every
  /// menu open, so it must stay cheap.
  func applicability(to input: TransformInput) -> Applicability
  /// Produces the output. Must not mutate anything: applying the result is the
  /// caller's job, and on a throw the pad is left untouched (`FR-6.6`).
  func apply(to input: TransformInput) async throws -> TransformOutput
}

/// Whether a transform is offered, and if not, why not.
///
/// An enumeration rather than a `Bool` because the reason is shown to the
/// person when a transform is invoked over MCP and refused, where there is no
/// greyed-out menu item to read the refusal from (D-11).
public enum Applicability: Sendable, Equatable {
  case applicable
  case notApplicable(reason: String)

  public var isApplicable: Bool {
    self == .applicable
  }
}

/// Where the text a transform is given came from, and so where its output goes
/// back (`FR-6.4`).
public enum Scope: Sendable, Equatable {
  /// A selection, as a UTF-16 offset range into the pad's text. UTF-16 because
  /// that is what `NSTextView` reports and what it will be handed back.
  case selection(Range<Int>)
  case wholePad
}

/// What a transform is given.
///
/// `plainText` holds only the text in scope — the selection when there is one,
/// the whole pad otherwise — so that a transform never has to think about
/// scope, and an applicability predicate run on menu open is answering about
/// the text the person would actually be transforming. `scope` is carried for
/// the applier, which needs to know where to put the output back.
public struct TransformInput: Sendable, Equatable {
  public let plainText: String
  /// Present only for transforms that need styling, which in the deterministic
  /// set means `flatten` alone.
  public let rtfd: Data?
  public let scope: Scope
  public let padMode: PadMode

  public init(plainText: String, rtfd: Data? = nil, scope: Scope = .wholePad, padMode: PadMode = .plain) {
    self.plainText = plainText
    self.rtfd = rtfd
    self.scope = scope
    self.padMode = padMode
  }
}

/// What a transform produces.
///
/// `report` exists so that a comparison transform (`FR-6.7`) has somewhere to
/// put its output without mutating a pad: a report is shown, never applied.
public enum TransformOutput: Sendable, Equatable {
  case plainText(String)
  case styled(Data)
  case report(String)
}

/// Why a transform refused or failed.
///
/// Both cases carry a sentence fit to show someone, because `FR-6.6` requires
/// that a failure says why and the alternative is an error whose only honest
/// presentation is "something went wrong".
public enum TransformError: Error, Sendable, Equatable {
  /// The runner refused before doing any work, because the predicate said no.
  case notApplicable(reason: String)
  /// The transform ran and could not finish. `json.pretty` reaches this when a
  /// pad above the predicate's parse cap turns out not to be JSON after all.
  case failed(reason: String)

  public var reason: String {
    switch self {
    case .notApplicable(let reason), .failed(let reason): return reason
    }
  }
}
