// swift-tools-version: 6.2
import PackageDescription

// Fixture for Scripts/verify-coverage-gate.sh. Deliberately under-covered: most
// of `Neglected` is never called by its test, so the coverage gate must fail on
// it. If this fixture ever passes the gate, the gate is broken.
let package = Package(
  name: "UnderCovered",
  platforms: [.macOS(.v15)],
  products: [.library(name: "UnderCovered", targets: ["UnderCovered"])],
  targets: [
    .target(name: "UnderCovered"),
    .testTarget(name: "UnderCoveredTests", dependencies: ["UnderCovered"]),
  ]
)
