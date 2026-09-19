// swift-tools-version: 6.2
import PackageDescription

// The stdio shim (`FR-8.2`). Depends on ItchyCore alone, deliberately: it reads
// `endpoint.json` through the store's own API, and it must not acquire the MCP
// SDK, because a shim that can parse the protocol is a shim that will end up
// interpreting it (specification §11.1).
//
// Split into a library and a one-file executable so that the parts worth
// testing can be imported — by this package's own tests, and by the
// application's suite, which launches the binary to demonstrate FR-8.2.
let package = Package(
  name: "itchy-mcp",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "itchy-mcp", targets: ["itchy-mcp"]),
    .library(name: "ItchyMCPShimCore", targets: ["ItchyMCPShimCore"]),
  ],
  dependencies: [
    .package(path: "../Packages/ItchyCore")
  ],
  targets: [
    .target(
      name: "ItchyMCPShimCore",
      dependencies: [.product(name: "ItchyCore", package: "ItchyCore")],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .executableTarget(
      name: "itchy-mcp",
      dependencies: ["ItchyMCPShimCore"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "ItchyMCPShimCoreTests",
      dependencies: ["ItchyMCPShimCore"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
