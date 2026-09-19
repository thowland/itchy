import Foundation
import ItchyCore

/// The Models topic.
///
/// Separate from the other content files because it is the one topic where the
/// reader is deciding whether to let their text leave the machine, and the
/// order of the sections matters: what it does, then where the text goes, then
/// how to set it up.
extension HelpContent {
  static let models = HelpTopic(
    id: "models",
    title: "Models",
    symbol: "brain",
    blurb: "Letting a model rewrite a pad, and deciding where the text is allowed to go.",
    sections: [
      HelpSection(
        heading: "What the model-backed transforms do",
        blocks: [
          .text(
            "Three of them, and they all replace text with text: Tidy Prose rewrites for "
              + "clarity and fixes grammar, Summarise replaces the pad with a short summary "
              + "of it, and To Bullet Points rewrites it as a list. They sit in the same "
              + "wand menu as everything else, underneath the instant transforms, and they "
              + "undo the same way."),
          .text(
            "None of them answers a question about your text. There is no chat panel and no "
              + "conversation view, because a scratchpad that answers questions grows a "
              + "reply field, then a history, and ends up as a chat window with a save "
              + "button."),
          .note(
            "They do not appear in the menu at all until you have configured a model, so an "
              + "unconfigured Itchy looks exactly as it did before."),
        ]),
      HelpSection(
        heading: "Where your text goes",
        blocks: [
          .text(
            "Itchy looks for a model on your Mac first, under every setting and on every "
              + "pad. A model running locally sends nothing anywhere, so there is no policy "
              + "to satisfy and nothing to ask you about, and that is why local stays the "
              + "default even when a pad permits remote work."),
          .text(
            "If the local model cannot be reached, Itchy fails and tells you so. It does not "
              + "send your text to a remote service instead, under any setting and on any "
              + "pad. That case — local model down, remote configured, pad allows it — is "
              + "exactly where falling back would look helpful, which is why it is ruled "
              + "out rather than left to judgement."),
        ]),
      HelpSection(
        heading: "Setting up a local model",
        blocks: [
          .text(
            "Itchy talks to Ollama, or to anything that speaks its API, at "
              + "\(ModelSettings.defaultLocalEndpoint) by default."),
          .steps([
            "Install Ollama and pull a model — ollama pull llama3.2 will do.",
            "Open Settings → Models and put the model's name in the Model field under "
              + "“On this Mac”.",
            "Change the endpoint only if you are running the server somewhere other than "
              + "the default port.",
          ]),
          .note(
            "If you name a model you have not pulled, Itchy says the model is unavailable "
              + "rather than that the server is missing, because those need different things "
              + "from you."),
        ]),
      HelpSection(
        heading: "Setting up a remote model",
        blocks: [
          .text(
            "Optional, and off until you fill it in. Itchy speaks the OpenAI-compatible "
              + "chat format, so most hosted services and most local alternatives to Ollama "
              + "will work: put the endpoint and the model name in Settings → Models under "
              + "“Remote”, then paste the API key and press Save."),
          .text(
            "The key goes into your Keychain. It is never written to Itchy's own files and "
              + "never to its diagnostic log, and the log could not carry it in any case, "
              + "because the log can only say the things it has words for and none of them "
              + "is a credential."),
        ]),
      HelpSection(
        heading: "Deciding per pad",
        blocks: [
          .text(
            "Each pad carries its own answer to whether model work on it may reach a remote "
              + "service, and you set it in the pad's own settings, under the ⋯ button. "
              + "New pads are local only."),
          .steps([
            "Local only — nothing from this pad ever goes to a remote service, which is "
              + "what a new pad gets.",
            "May use a remote service — transforms that need a remote model may send this "
              + "pad's text to the one you configured.",
            "Ask me each time — Itchy asks before anything leaves, naming the pad, the "
              + "transform, where the text is going and how many characters are about to go.",
          ]),
          .text(
            "The pad shows which of the three it is on its status line once you have a "
              + "model configured, so you can tell without opening anything."),
          .note(
            "A pad set to local only can still use a local model. The policy governs text "
              + "leaving your Mac, and a model running on it does not."),
        ]),
      HelpSection(
        heading: "When it does not work",
        blocks: [
          .text(
            "The message in the pad's status line distinguishes the cases, because they "
              + "need different things from you:"),
          .steps([
            "“Could not reach the model” — the server is not running, or the endpoint is "
              + "wrong.",
            "“The model is not available” — the server is fine and that model has not been "
              + "pulled.",
            "“The model service refused the request” — usually an expired or wrong API key "
              + "on the remote side; the service's own explanation is included.",
          ]),
          .text(
            "In every case the pad is untouched. A transform that fails leaves your text "
              + "exactly as it was."),
        ]),
    ])
}
