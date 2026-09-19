import Foundation
import ItchyCore

/// What the person is being asked, when a pad is set to ask each time
/// (`FR-9.1`, §12).
///
/// A value, so the wording is testable and the prompt itself is the only part
/// that needs a window server. It names the pad, the destination and the amount
/// of text, because "allow this?" with no nouns in it is a question people
/// answer yes to without reading.
public struct ConsentRequest: Sendable, Equatable {
  public let padName: String
  public let transformTitle: String
  public let endpoint: String
  public let characters: Int

  public init(padName: String, transformTitle: String, endpoint: String, characters: Int) {
    self.padName = padName
    self.transformTitle = transformTitle
    self.endpoint = endpoint
    self.characters = characters
  }

  public var title: String {
    "Send “\(padName)” to a remote model?"
  }

  public var detail: String {
    "\(transformTitle) needs a remote model. This will send \(characters) "
      + "character\(characters == 1 ? "" : "s") from this pad to \(host), which is outside "
      + "this Mac.\n\nThis pad is set to ask each time. You can change that in the pad's "
      + "own settings."
  }

  /// The host rather than the whole URL: it is the part that answers "where is
  /// my text going", and a path full of version numbers is not.
  public var host: String {
    URL(string: endpoint)?.host() ?? endpoint
  }

  public static let allow = "Send"
  public static let deny = "Don't Send"
}

/// What the runner knows about the pad it is running against, for the sole
/// purpose of describing it in the question.
///
/// A small struct rather than two parameters so that adding a third thing worth
/// saying does not change `TransformRunner`'s signature.
public struct ConsentSubject: Sendable, Equatable {
  public let padName: String
  public let endpoint: String

  public init(padName: String = "this pad", endpoint: String = "a remote service") {
    self.padName = padName
    self.endpoint = endpoint
  }
}

/// Asks. A seam, because the asking needs a window server and every decision
/// around it does not.
public protocol ConsentProviding: Sendable {
  func request(_ consent: ConsentRequest) async -> Bool
}

/// Answers no without asking.
///
/// What `itchyctl` and the suite get. Refusing is the right default for a thing
/// that cannot ask: `askEachTime` means the person decides, and nobody deciding
/// is not the same as yes.
public struct DeclinesConsent: ConsentProviding {
  public init() {}
  public func request(_ consent: ConsentRequest) async -> Bool { false }
}
