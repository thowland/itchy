// swift-tools-version: 6.2
import PackageDescription

// Development-only harness. Not shipped (specification §1).
let package = Package(
  name: "itchyctl",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(path: "../Packages/ItchyCore")
  ],
  targets: [
    .executableTarget(
      name: "itchyctl",
      dependencies: [.product(name: "ItchyCore", package: "ItchyCore")],
      swiftSettings: [.swiftLanguageMode(.v6)]
    )
  ]
)
