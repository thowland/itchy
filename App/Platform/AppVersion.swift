import Foundation

/// The version the About screen shows (D-22).
///
/// Read from the bundle rather than written into code, so that `make bump` and
/// the build-number stamp are the only places a version is set.
struct AppVersion: Equatable, Sendable {
  let marketing: String?
  let build: String?

  init(marketing: String?, build: String?) {
    self.marketing = marketing
    self.build = build
  }

  init(infoDictionary: [String: Any]?) {
    self.init(
      marketing: infoDictionary?["CFBundleShortVersionString"] as? String,
      build: infoDictionary?["CFBundleVersion"] as? String)
  }

  static var current: AppVersion {
    AppVersion(infoDictionary: Bundle.main.infoDictionary)
  }

  /// "Version 0.1.1 (412)". The build is left out when the stamp did not run,
  /// rather than showing a zero that looks like a real build.
  var display: String {
    switch (marketing, build) {
    case (.some(let version), .some(let build)) where build != "0":
      "Version \(version) (\(build))"
    case (.some(let version), _):
      "Version \(version)"
    case (nil, _):
      "Version unknown"
    }
  }
}
