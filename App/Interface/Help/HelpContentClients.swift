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
            "Three things, all of them in Settings → Agents: the address, the transport, "
              + "and the token."),
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
            "The address starts with http, not https, and it is 127.0.0.1 rather than a "
              + "name. Both are deliberate: the connection never leaves this machine, so "
              + "there is nothing for TLS to protect against and no certificate that could "
              + "be issued for a loopback address anyway."),
        ]),
      HelpSection(
        heading: "Claude Code",
        blocks: [
          .text(
            "The simplest of the three. One command, and Claude Code speaks Streamable "
              + "HTTP directly:"),
          .steps([
            "claude mcp add --transport http itchy "
              + "http://127.0.0.1:\(MCPBounds.defaultPort)\(MCPServerHost.path) "
              + "--header \"Authorization: Bearer PASTE-TOKEN-HERE\" --scope user",
            "Check it with: claude mcp list — Itchy should read ✔ Connected.",
            "Inside a session, /mcp shows the same thing and lists the five tools.",
          ]),
          .note(
            "Use --scope user, as above, so Itchy is available in every project. Do not use "
              + "--scope project: that writes the token into a .mcp.json file in the "
              + "repository, which is a file most people commit."),
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
            "Codex names an environment variable rather than taking the token itself, which "
              + "is the better arrangement: the token stays out of the configuration file. "
              + "That file is shared with Codex in the ChatGPT desktop application and the "
              + "IDE extension, so configuring it once covers all three."),
        ]),
      HelpSection(
        heading: "Claude Desktop",
        blocks: [
          .text(
            "Claude Desktop needs a small bridge, and the reason is worth understanding "
              + "because it explains ChatGPT too."),
          .text(
            "Desktop has two ways to reach an MCP server. Custom connectors take a URL, but "
              + "Anthropic's servers make that connection rather than your Mac, so they "
              + "cannot reach an address that only exists on your machine. Its configuration "
              + "file runs on your Mac and can reach Itchy, but it launches a command and "
              + "talks to it over its input and output — it does not speak HTTP."),
          .text(
            "So something local has to sit between them. Itchy will ship that bridge itself; "
              + "until it does, mcp-remote is the usual one. Edit "
              + "~/Library/Application Support/Claude/claude_desktop_config.json and add:"),
          .steps([
            "\"mcpServers\": { \"itchy\": { \"command\": \"npx\", \"args\": [\"mcp-remote\", "
              + "\"http://127.0.0.1:\(MCPBounds.defaultPort)\(MCPServerHost.path)\", "
              + "\"--allow-http\", \"--header\", \"Authorization:${AUTH}\"], "
              + "\"env\": { \"AUTH\": \"Bearer PASTE-TOKEN-HERE\" } } }",
            "Quit Claude Desktop completely and start it again. It only reads that file at "
              + "launch.",
          ]),
          .note(
            "The token goes in env rather than straight into the header, and there is no "
              + "space after “Authorization:”. That is a real quirk rather than a typo: "
              + "Desktop does not escape spaces inside those arguments, so a header written "
              + "the natural way arrives split in half. --allow-http is needed because "
              + "mcp-remote refuses plain HTTP otherwise, which is the right default "
              + "everywhere except a loopback address."),
        ]),
      HelpSection(
        heading: "ChatGPT's own connectors",
        blocks: [
          .text(
            "The connectors you add inside ChatGPT itself cannot reach Itchy, and this is "
              + "not a setting you have missed. Use Codex instead, above — it is OpenAI's "
              + "client that runs on your machine, and it works."),
          .text(
            "The difference is where the connection is made from. A ChatGPT connector is "
              + "opened by OpenAI's servers, so it needs an address reachable from the "
              + "public internet over HTTPS and authenticates with OAuth rather than a token "
              + "you paste. Itchy listens on 127.0.0.1 and nothing else, which is a "
              + "requirement rather than a default — it is what makes the pads unreachable "
              + "from anywhere but this Mac."),
          .text(
            "You could put a tunnel in front of it and give ChatGPT the public address. "
              + "Do not. That would mean the contents of your exposed pads leaving your "
              + "machine, protected by one bearer token, to buy a convenience Codex gives "
              + "you for nothing."),
          .note(
            "The same reasoning applies to Claude's custom connectors, and for the same "
              + "reason: anything opened from a server rather than from your Mac cannot see "
              + "127.0.0.1. Clients that run locally — Claude Code, Codex — are the ones "
              + "that work."),
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
            "Switching on the diagnostic log in Settings → General shows each request "
              + "arriving, whether its token was accepted, and what every tool call did. It "
              + "is the quickest way to tell “the client never reached Itchy” from “the "
              + "client reached Itchy and was refused”."),
        ]),
    ])
}
