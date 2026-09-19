import Foundation
import ItchyCore
import ItchyServices

/// Configuring the agent, as opposed to configuring Itchy.
///
/// The agents topic explains this side of the connection; this one explains the
/// other side, which is where somebody actually gets stuck. The three clients
/// behave very differently and one of them cannot connect at all, so the
/// honest thing is a topic that says which is which rather than three variations
/// on the same instructions.
extension HelpContent {
  static let clients = HelpTopic(
    id: "clients",
    title: "Connecting Claude or ChatGPT",
    symbol: "cable.connector",
    blurb: "What to type on the agent's side, once the server is running.",
    sections: [
      HelpSection(
        heading: "What every client needs",
        blocks: [
          .text(
            "Three things, all of them in Settings → Agents: the address, the transport and "
              + "the token. Claude Desktop needs only the token, because it launches the "
              + "shim that ships inside Itchy and the shim finds the rest for itself."),
          .steps([
            "The address is http://127.0.0.1:PORT\(MCPServerHost.path), where PORT is the "
              + "number Settings → Agents shows. It is usually "
              + "\(MCPBounds.defaultPort), but if that port was taken Itchy will have bound "
              + "another one and the settings line says which.",
            "The transport is Streamable HTTP. Some clients call it “http”, some call it "
              + "“streamable-http”; they mean the same thing.",
            "The token is the bearer token beside the switch. Press Copy.",
          ]),
          .note(
            "The address starts with http rather than https, and it is 127.0.0.1 rather "
              + "than a hostname. The connection never leaves this machine, so there is "
              + "nothing in transit for TLS to protect, and no certificate authority will "
              + "issue a certificate for a loopback address in any case."),
        ]),
      HelpSection(
        heading: "Claude Code",
        blocks: [
          .text(
            "One command, because Claude Code speaks Streamable HTTP directly:"),
          .steps([
            "claude mcp add --transport http itchy "
              + "http://127.0.0.1:\(MCPBounds.defaultPort)\(MCPServerHost.path) "
              + "--header \"Authorization: Bearer PASTE-TOKEN-HERE\" --scope user",
            "Check it with: claude mcp list — Itchy should read ✔ Connected.",
            "Inside a session, /mcp shows the same thing and lists the five tools.",
          ]),
          .note(
            "Use --scope user, as above, so Itchy is available in every project. Avoid "
              + "--scope project, which writes the token into a .mcp.json file in the "
              + "repository, and that is a file most people commit."),
        ]),
      HelpSection(
        heading: "Codex",
        blocks: [
          .text(
            "Codex runs on your Mac and speaks Streamable HTTP, so it reaches Itchy "
              + "directly — no bridge. Either run:"),
          .steps([
            "codex mcp add itchy --url "
              + "http://127.0.0.1:\(MCPBounds.defaultPort)\(MCPServerHost.path) "
              + "--bearer-token-env-var ITCHY_TOKEN",
            "Then put the token in that variable, for example by adding "
              + "export ITCHY_TOKEN=\"PASTE-TOKEN-HERE\" to your shell profile.",
            "codex mcp list shows what is configured.",
          ]),
          .text(
            "Or write it into ~/.codex/config.toml yourself, which is the same thing:"),
          .steps([
            "[mcp_servers.itchy]",
            "url = \"http://127.0.0.1:\(MCPBounds.defaultPort)\(MCPServerHost.path)\"",
            "bearer_token_env_var = \"ITCHY_TOKEN\"",
          ]),
          .note(
            "Codex names an environment variable rather than storing the token, so the "
              + "token stays out of the configuration file. That file is shared with Codex "
              + "in the ChatGPT desktop application and the IDE extension, so configuring "
              + "it once covers all three."),
        ]),
      HelpSection(
        heading: "Claude Desktop",
        blocks: [
          .text(
            "Claude Desktop cannot be pointed at an address directly, for two reasons that "
              + "compound: its custom connectors are opened by Anthropic's servers, which "
              + "cannot reach an address that exists only on your Mac, and its configuration "
              + "file launches a command rather than speaking HTTP."),
          .text(
            "Itchy therefore ships a small program for it to launch, which does nothing but "
              + "pass messages along, and it lives inside the application. Edit "
              + "~/Library/Application Support/Claude/claude_desktop_config.json and add:"),
          .steps([
            "\"mcpServers\": { \"itchy\": { \"command\": "
              + "\"/Applications/Itchy.app/Contents/MacOS/itchy-mcp\", "
              + "\"env\": { \"ITCHY_TOKEN\": \"PASTE-TOKEN-HERE\" } } }",
            "Quit Claude Desktop completely and start it again — it reads that file only at "
              + "launch.",
          ]),
          .note(
            "The shim finds the port itself, so there is no address to keep in step when it "
              + "changes. If the server is off, or the token is wrong, it says which in "
              + "Claude Desktop's own log rather than failing silently."),
        ]),
      HelpSection(
        heading: "ChatGPT's own connectors",
        blocks: [
          .text(
            "The connectors you add inside ChatGPT itself cannot reach Itchy, and there is "
              + "no setting you have missed. Use Codex instead, above, which is OpenAI's "
              + "client that runs on your machine and does work."),
          .text(
            "The difference is where the connection is made from. A ChatGPT connector is "
              + "opened by OpenAI's servers, so it needs an address reachable from the "
              + "public internet over HTTPS and authenticates with OAuth rather than a token "
              + "you paste. Itchy listens on 127.0.0.1 and nothing else, which is a "
              + "requirement rather than a default — it is what makes the pads unreachable "
              + "from anywhere but this Mac."),
          .text(
            "You could put a tunnel in front of it and give ChatGPT the public address, and "
              + "I would not: it puts the contents of your exposed pads on the public "
              + "internet behind a single bearer token, to buy a convenience Codex already "
              + "gives you for nothing."),
          .note(
            "The same applies to Claude's custom connectors, for the same reason: anything "
              + "opened from a server rather than from your Mac cannot see 127.0.0.1. The "
              + "clients that work are the ones that run locally, which today means Claude "
              + "Code, Codex and Claude Desktop through the shim."),
        ]),
      HelpSection(
        heading: "When it does not connect",
        blocks: [
          .text(
            "In the order worth checking, because the first two are nearly always it:"),
          .steps([
            "Is the server actually on? Settings → Agents says “Listening on 127.0.0.1:…”, "
              + "and so does the menubar.",
            "Is the port the one the client is pointed at? If the configured port was in "
              + "use, Itchy bound a different one and said so under the port field.",
            "Is the token current? Regenerating it stops the old one working immediately, "
              + "including for a client that is already connected.",
            "Is any pad exposed? A client can connect perfectly and still see nothing, "
              + "because exposure is per pad and off by default. list_pads says so when "
              + "the answer is none.",
          ]),
          .note(
            "Switching on the diagnostic log in Settings → General records each request "
              + "arriving, whether its token was accepted and what every tool call did, "
              + "which is the quickest way to tell “the client never reached Itchy” from "
              + "“the client reached Itchy and was refused”."),
        ]),
    ])
}
