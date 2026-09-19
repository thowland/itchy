import Foundation

/// What a model is actually asked (§12, `FR-9.6`).
///
/// Values, so the prompts are reviewable in one place and testable without a
/// model. They are written against one standing risk: a model asked to improve
/// text will happily answer *about* the text instead — "Here's a clearer
/// version:" — and a transform that inserts commentary into a pad has replaced
/// the person's content with a conversation. Every instruction below says
/// return the text and nothing else, and `ModelAnswer` strips the preamble when
/// it arrives anyway.
public enum ModelPrompt {
  /// The shared rule, prepended to every instruction rather than repeated in
  /// each, so that changing it changes all of them.
  public static let rule =
    "You are a text transformation tool inside a scratchpad application. "
    + "Return only the transformed text. Do not explain, do not introduce your "
    + "answer, do not wrap it in code fences, and do not add a closing remark. "
    + "Preserve the original language. If the input cannot be transformed as "
    + "asked, return it unchanged."

  public static func instruction(_ task: String) -> String {
    "\(rule)\n\n\(task)"
  }

  /// The text itself, kept out of the instruction so a pad that happens to
  /// contain instructions is data rather than a second set of orders.
  public static func body(_ request: ModelRequest) -> String {
    request.text
  }
}

/// Cleaning up what came back.
///
/// Models add preambles. A transform's output is written straight into a pad as
/// one undoable step, so anything that arrives alongside the answer becomes the
/// person's content — which is worse than a transform that failed.
public enum ModelAnswer {
  /// Fences are the common one: a model asked to rewrite prose returns it
  /// wrapped in triple backticks perhaps a third of the time.
  public static func cleaned(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    text = strippingFence(text)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  internal static func strippingFence(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    guard lines.count >= 2, lines[0].hasPrefix("```") else { return text }
    guard let closing = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "```" })
    else { return text }
    guard closing > 0 else { return text }
    return lines[1..<closing].joined(separator: "\n")
  }
}
