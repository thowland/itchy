import Foundation
import ItchyCore
import ItchyMCPShimCore

// The stdio shim (`FR-8.2`). It proxies and does nothing else.
//
// Everything it decides is in ShimConfiguration and Framing; this reads the
// environment, resolves where to connect, and hands over to the proxy.

let standardError = FileHandle.standardError
let standardOutput = FileHandle.standardOutput

@Sendable func complain(_ message: String) {
  try? standardError.write(contentsOf: Data((message + "\n").utf8))
}

@Sendable func emit(_ data: Data) {
  try? standardOutput.write(contentsOf: data)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let layout =
  ShimConfiguration.supportRoot(in: arguments).map(PadStorageLayout.at(path:))
  ?? (try? PadStorageLayout.standard())
let endpoint = layout.flatMap { EndpointStore(layout: $0).read() }

let resolution = ShimConfiguration.resolve(
  endpoint: endpoint,
  token: ProcessInfo.processInfo.environment[ShimConfiguration.tokenVariable],
  isRunning: { kill($0, 0) == 0 || errno == EPERM })

guard case .ready(let url, let token) = resolution else {
  complain(ShimConfiguration.message(for: resolution) ?? "itchy-mcp: cannot start.")
  exit(1)
}

let proxy = Proxy(url: url, token: token, write: emit, complain: complain)
await proxy.run(reading: FileHandle.standardInput)
