import AppKit
import ItchyCore
import ItchyServices

/// Invoking a transform on a pad (§7.3).
///
/// The coordinator gathers, hands to `TransformRunner`, and applies what comes
/// back. It decides nothing: applicability and routing are the runner's,
/// scope is `TransformScope`'s, styling is `TransformStylePlan`'s, and how long
/// a failure stays on screen is `TransformNotice`'s.
extension PadCoordinator {
  func applyTransform(id: String, to padID: PadID) {
    guard let transform = TransformRegistry.transform(id: id) ?? modelTransform(id: id),
      let editor = editors[padID],
      let input = editor.transformInput()
    else { return }
    let pad = metadata(forID: padID)
    let runner = TransformRunner(
      policy: pad?.routingPolicy ?? .default,
      consent: AlertConsent(),
      subject: ConsentSubject(
        padName: pad?.name ?? "this pad",
        endpoint: settings.models.remoteEndpoint))
    Task { @MainActor in
      do {
        let output = try await runner.run(transform, on: input)
        editor.applyTransform(
          output, scope: input.scope, transformID: transform.id, actionName: transform.title)
        DebugLog.shared.record(
          .transformApplied(
            transform.id, scope: String(describing: input.scope),
            characters: input.plainText.count))
        clearNotice(for: padID)
      } catch let error as TransformError {
        // `FR-6.6`: the pad is untouched — the runner never applies — and the
        // reason is shown rather than swallowed.
        DebugLog.shared.record(.transformDeclined(transform.id, reason: error.reason))
        showNotice(TransformNotice.message(for: transform, reason: error.reason), for: padID)
      } catch {
        DebugLog.shared.record(.transformDeclined(transform.id, reason: "\(error)"))
        showNotice(TransformNotice.message(for: transform, reason: "\(error)"), for: padID)
      }
    }
  }

  /// The rows for a pad's Transform menu, surveyed against what is selected
  /// right now (`FR-6.3`, `FR-6.4`). Model-backed ones come last (`FR-9.6`).
  func transformRows(for padID: PadID) -> [[TransformMenuModel.Row]] {
    guard let input = editors[padID]?.transformInput() else { return [] }
    return TransformMenuModel.rows(for: input, models: modelTransforms)
  }

  /// Model transforms are built from settings rather than held in the registry,
  /// so they are looked up separately.
  func modelTransform(id: String) -> (any Transform)? {
    modelTransforms.first { $0.id == id }
  }

  func showNotice(_ text: String, for padID: PadID) {
    notices[padID] = text
    noticeTasks[padID]?.cancel()
    noticeTasks[padID] = Task { @MainActor [weak self] in
      try? await Task.sleep(for: TransformNotice.duration)
      guard !Task.isCancelled else { return }
      self?.clearNotice(for: padID)
    }
  }

  func clearNotice(for padID: PadID) {
    noticeTasks[padID]?.cancel()
    noticeTasks[padID] = nil
    notices.removeValue(forKey: padID)
  }

  private func metadata(forID padID: PadID) -> PadMetadata? {
    pads.first { $0.id == padID }
  }
}

/// How a transform failure is put in front of someone (`FR-6.6`).
///
/// In the pad's own status bar rather than a modal alert. A scratchpad that
/// stops to be dismissed is a scratchpad that interrupts, and the status bar
/// already carries the one other thing that can go wrong with a pad — its
/// fault — in the same place and the same red.
enum TransformNotice {
  /// Long enough to read a sentence, short enough that it is gone before it is
  /// in the way. Cleared early by the next transform that succeeds.
  static let duration: Duration = .seconds(6)

  static func message(for transform: any Transform, reason: String) -> String {
    "\(transform.title): \(reason)"
  }
}
