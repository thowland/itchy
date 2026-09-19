import ItchyCore
import SwiftUI

/// The first-run window's contents.
///
/// This file is on the coverage exclusion list and may not branch; the wording
/// lives in `WelcomeText` and the decision to show it in `FirstRunPolicy`.
struct WelcomeView: View {
  let presentation: WelcomePresentation
  let onDismiss: () -> Void
  /// A closure rather than a reach into the environment: this window is hosted
  /// by its own controller and is not inside the coordinator's environment, and
  /// discovering that at runtime is a crash rather than a blank button.
  let onHelp: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 10) {
        Image(systemName: "cat.fill")
          .font(.system(size: 44))
          .foregroundStyle(.tint)
        Text(WelcomeText.title)
          .font(.largeTitle.weight(.semibold))
        Text(WelcomeText.tagline)
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      .padding(.top, 32)
      .padding(.bottom, 24)

      VStack(alignment: .leading, spacing: 16) {
        ForEach(WelcomeText.points, id: \.symbol) { point in
          WelcomePoint(symbol: point.symbol, text: point.text)
        }
      }
      .padding(.horizontal, 36)

      Spacer(minLength: 24)

      VStack(spacing: 14) {
        HStack(spacing: 10) {
          Button(HelpText.aboutButton, action: onHelp)
            .controlSize(.large)
            .accessibilityIdentifier("welcome.help")

          Button(WelcomeText.dismiss(for: presentation), action: onDismiss)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }

        HStack(spacing: 4) {
          Text(WelcomeText.authorLine)
            .foregroundStyle(.secondary)
          // Styled separately: a secondary foreground on the enclosing stack
          // also greys the link, and a link that does not look like one is not
          // a link.
          Link(WelcomeText.websiteTitle, destination: WelcomeText.website)
            .foregroundStyle(.tint)
        }
        .font(.caption)

        Text(WelcomeText.versionLine)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .textSelection(.enabled)
          .accessibilityIdentifier("welcome.version")
      }
      .padding(.bottom, 28)
    }
    .frame(width: 460, height: 540)
    .accessibilityIdentifier("welcome.window")
  }
}

/// One line of the overview.
struct WelcomePoint: View {
  let symbol: String
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 16))
        .foregroundStyle(.tint)
        .frame(width: 22)
        .accessibilityHidden(true)
      Text(text)
        .font(.callout)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
  }
}
