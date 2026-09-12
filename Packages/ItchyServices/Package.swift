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
    .package(path: "../ItchyCore")
  ],
  targets: [
    .target(
      name: "ItchyServices",
      dependencies: [.product(name: "ItchyCore", package: "ItchyCore")],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "ItchyServicesTests",
      dependencies: ["ItchyServices"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
