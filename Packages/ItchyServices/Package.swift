// swift-tools-version: 6.2
import PackageDescription

// ItchyServices holds the transform implementations, the MCP server, and the
// model client. Everything here talks to the store and never to a view.
let package = Package(
  name: "ItchyServices",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "ItchyServices", targets: ["ItchyServices"])
  ],
  dependencies: [
    .package(path: "../ItchyCore"),
    // The first dependency the application ships (D-4 permits one from R3, D-5
    // chose it, D-17 verified the fit). Apache-2.0 and MIT, both of which
    // combine into a GPL-3.0 work.
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
  ],
  targets: [
    .target(
      name: "ItchyServices",
      dependencies: [
        .product(name: "ItchyCore", package: "ItchyCore"),
        .product(name: "MCP", package: "swift-sdk"),
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "ItchyServicesTests",
      dependencies: ["ItchyServices"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
