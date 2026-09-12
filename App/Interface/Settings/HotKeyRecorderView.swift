import AppKit
import SwiftUI

/// Records a key combination for the global hotkey (`FR-1.4`).
///
/// A local event monitor rather than a global one: it only needs to see keys
/// while this control has focus, which requires no permission — the same
/// reasoning as D-6.
struct HotKeyRecorderView: NSViewRepresentable {
  @Binding var binding: HotKeyBinding
  @Binding var isRecording: Bool

  func makeNSView(context: Context) -> RecorderView {
    let view = RecorderView()
    view.onCapture = { captured in
      binding = captured
      isRecording = false
    }
    return view
  }

  func updateNSView(_ nsView: RecorderView, context: Context) {
    nsView.isRecording = isRecording
    nsView.display(binding)
  }

  /// The button that captures the next combination pressed.
  final class RecorderView: NSButton {
    var onCapture: ((HotKeyBinding) -> Void)?
    private var monitor: Any?

    var isRecording = false {
      didSet { isRecording ? startMonitoring() : stopMonitoring() }
    }

    override init(frame frameRect: NSRect) {
      super.init(frame: frameRect)
      bezelStyle = .rounded
      setButtonType(.momentaryPushIn)
      target = self
      action = #selector(toggle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("not used")
    }

    deinit {
      MainActor.assumeIsolated { stopMonitoring() }
    }

    func display(_ binding: HotKeyBinding) {
      title = HotKeyRecorderTitle.text(isRecording: isRecording, binding: binding)
    }

    @objc private func toggle() {
      isRecording.toggle()
      display(HotKeyBinding.default)
    }

    private func startMonitoring() {
      // Stop first rather than guarding on nil: idempotent without a branch,
      // which is what a coverage-excluded file is allowed to be (D-11, §15.3).
      stopMonitoring()
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        self?.capture(event)
        return nil
      }
    }

    private func stopMonitoring() {
      guard let monitor else { return }
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }

    private func capture(_ event: NSEvent) {
      let proxy = NSEventModifierFlagsProxy(
        control: event.modifierFlags.contains(.control),
        option: event.modifierFlags.contains(.option),
        shift: event.modifierFlags.contains(.shift),
        command: event.modifierFlags.contains(.command))
      guard let candidate = HotKeyCapture.binding(keyCode: UInt32(event.keyCode), flags: proxy)
      else { return }
      isRecording = false
      onCapture?(candidate)
    }
  }
}
