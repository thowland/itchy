import Foundation
import ItchyCore

/// What a model is asked, and what it answers.
public struct ModelRequest: Sendable, Equatable {
  public let instruction: String
  public let text: String
  public let model: String

  public init(instruction: String, text: String, model: String) {
    self.instruction = instruction
    self.text = text
    self.model = model
  }
}

/// Why a model call failed, in words fit to put in a pad's status bar.
///
/// An enumeration because the four cases need different things from the
/// person — start the server, pull a model, check the endpoint, wait — and a
/// single "the model failed" tells them to do none of those.
public enum ModelFailure: Error, Sendable, Equatable {
  case unreachable(endpoint: String)
  case noSuchModel(String)
  case refused(status: Int, detail: String)
  case emptyAnswer
  case timedOut(seconds: Int)

  public var reason: String {
    switch self {
    case .unreachable(let endpoint):
      return "Could not reach the model at \(endpoint). Is it running?"
    case .noSuchModel(let name):
      return "The model “\(name)” is not available. Pull it first, or choose another "
        + "in Settings → Models."
    case .refused(let status, let detail):
      return "The model service refused the request (\(status)). \(detail)"
    case .emptyAnswer:
      return "The model returned nothing."
    case .timedOut(let seconds):
      return "The model did not answer within \(seconds) seconds."
    }
  }
}

/// A model that can be asked to rework some text.
///
/// A seam, so that every transform above it is testable without a model, and so
/// that the local and remote clients are interchangeable to everything except
/// `ModelRouter`, which is the only thing allowed to choose between them.
public protocol ModelClient: Sendable {
  func complete(_ request: ModelRequest) async throws -> String
}
