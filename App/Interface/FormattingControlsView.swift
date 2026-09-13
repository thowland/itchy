import ItchyCore
import SwiftUI

/// Bold, italic and underline, in a styled pad's status bar (D-20).
///
/// On the coverage exclusion list, so it may not branch: what is shown is
/// `FormattingBarModel`'s, what a toggle does is `FormattingPlan`'s.
struct FormattingControls: View {
  let formatting: FormattingState
  let mode: PadMode
  let onToggle: (FormatTrait) -> Void

  var body: some View {
    HStack(spacing: 0) {
      ForEach(FormatTrait.allCases, id: \.self) { trait in
        FormatButton(trait: trait, isActive: formatting.active.contains(trait)) {
          onToggle(trait)
        }
      }
    }
    .padding(.trailing, 4)
    .frame(width: FormattingBarModel.visibility(for: mode).width)
    .clipped()
    .opacity(FormattingBarModel.visibility(for: mode).opacity)
    .disabled(FormattingBarModel.visibility(for: mode).isDisabled)
    .accessibilityHidden(FormattingBarModel.visibility(for: mode).isDisabled)
  }
}

struct FormatButton: View {
  let trait: FormatTrait
  let isActive: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: FormattingBarModel.symbol(for: trait))
        .frame(width: 22, height: 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .foregroundStyle(FormattingBarModel.style(isActive: isActive))
    .help(FormattingBarModel.help(for: trait))
    .accessibilityLabel(FormattingPlan.actionName(for: trait))
    .accessibilityValue(FormattingBarModel.accessibilityValue(isActive: isActive))
    .accessibilityIdentifier("pad.format.\(trait.rawValue)")
  }
}
