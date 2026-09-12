// swift-tools-version: 6.2
import PackageDescription

// ItchyCore holds the pad model, the store, and the transform protocol.
// It must never depend on AppKit or SwiftUI (D-2, NFR-4.3); Scripts/arch-lint.sh
// enforces that textually, and this package's inability to link a UI framework
// enforces it structurally.
let package = Package(
  name: "ItchyCore",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "ItchyCore", targets: ["ItchyCore"])
  ],
  targets: [
    .target(
      name: "ItchyCore",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "ItchyCoreTests",
      dependencies: ["ItchyCore"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
