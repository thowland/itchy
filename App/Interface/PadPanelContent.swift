import ItchyCore
import SwiftUI

/// What a pad panel contains: the editor, or the fault.
///
/// The choice is `FaultPresentation`'s, not this view's — specification §6.7
/// prohibits ever showing an empty editor over unreadable content, and that rule
/// is enforced in a tested seam rather than in a view body.
struct PadPanelContent: View {
  let pad: PadMetadata
  let editor: PadTextCoordinator
  let initial: NSAttributedString
  let font: NSFont
  let fault: PadStoreFault?
  let coordinator: PadCoordinator
  @State private var isShowingSettings = false

  var body: some View {
    let current = coordinator.metadata(for: pad)
    VStack(spacing: 0) {
      PadBody(
        presentation: FaultPresentation.presentation(for: fault),
        pad: current,
        editor: editor,
        initial: initial,
        font: font,
        onReveal: { coordinator.revealInFinder(pad.id) })
      Divider()
      HStack(spacing: 0) {
        PadStatusBar(
          segments: StatusBarModel.segments(
            for: current, fault: fault, notice: coordinator.notices[pad.id]))
        FormattingControls(formatting: editor.formatting, mode: current.mode) { trait in
          editor.toggle(trait)
        }
        TransformMenu(pad: current, coordinator: coordinator)
        PadActionsMenu(pad: current, coordinator: coordinator) {
          coordinator.prepareForPadSettings()
          isShowingSettings = true
        }
      }
    }
    .sheet(isPresented: $isShowingSettings) {
      PadSettingsView(pad: current, coordinator: coordinator)
    }
  }
}

/// Editor or fault, decided by `FaultPresentation.allowsEditing`.
struct PadBody: View {
  let presentation: FaultPresentation.Presentation?
  let pad: PadMetadata
  let editor: PadTextCoordinator
  let initial: NSAttributedString
  let font: NSFont
  let onReveal: () -> Void

  var body: some View {
    if let presentation, !presentation.allowsEditing {
      FaultedPadView(presentation: presentation, onReveal: onReveal)
    } else {
      PadTextEditor(coordinator: editor, mode: pad.mode, initial: initial, font: font)
    }
  }
}

/// Per-pad actions, on the pad rather than in the menubar.
///
/// The menubar stays a list of pads to open; anything done *to* a pad is reached
/// from the pad itself or from the Pads window.
struct PadActionsMenu: View {
  let pad: PadMetadata
  let coordinator: PadCoordinator
  let onShowSettings: () -> Void

  var body: some View {
    Menu {
      Button("Pad Settings…", action: onShowSettings)
      Divider()
      Button("Copy All as Plain Text") {
        coordinator.copyAsPlainText(pad.id)
      }
      Divider()
      Button("Switch to \(PadModeLabel.other(pad.mode))") {
        coordinator.setMode(pad.id, to: PadModeLabel.opposite(pad.mode))
      }
      Divider()
      Button("Empty Pad") {
        coordinator.emptyPad(pad.id)
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .padding(.trailing, 8)
    .accessibilityIdentifier("pad.actions")
    .accessibilityLabel("Actions for \(pad.name)")
  }
}

/// Naming for the mode toggle. A seam, because "the other mode" is a decision
/// and view files do not make decisions (D-11).
enum PadModeLabel {
  static func opposite(_ mode: PadMode) -> PadMode {
    mode == .styled ? .plain : .styled
  }

  static func other(_ mode: PadMode) -> String {
    opposite(mode).rawValue.capitalized
  }
}

/// The deterministic transforms, on the pad (`FR-6.2`, `FR-6.3`).
///
/// Built from `TransformMenuModel`'s rows rather than from the registry
/// directly, so that what is shown, what is enabled and what the refusal says
/// are all decided somewhere they can be tested. The rows are surveyed when the
/// menu is built, which is when the selection is what it is (`FR-6.4`).
struct TransformMenu: View {
  let pad: PadMetadata
  let coordinator: PadCoordinator

  var body: some View {
    let groups = coordinator.transformRows(for: pad.id)
    Menu {
      ForEach(Array(groups.enumerated()), id: \.offset) { index, rows in
        if index > 0 { Divider() }
        ForEach(rows) { row in
          Button(row.title) {
            coordinator.applyTransform(id: row.id, to: pad.id)
          }
          .disabled(!row.isEnabled)
          .help(row.reason ?? "")
        }
      }
    } label: {
      Image(systemName: "wand.and.sparkles")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .disabled(!TransformMenuModel.isEnabled(for: groups))
    .accessibilityIdentifier("pad.transforms")
    .accessibilityLabel("Transform \(pad.name)")
  }
}
