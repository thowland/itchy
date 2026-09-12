import AppKit
import ItchyCore
import SwiftUI

/// Hosts the `NSTextView` in SwiftUI.
///
/// This file is on the coverage exclusion list: it is framework contract, and
/// the decisions it would otherwise make live in `PadTextCoordinator`,
/// `PastePlan` and `ContentCodec` (D-11, specification §15.2).
struct PadTextEditor: NSViewRepresentable {
  let coordinator: PadTextCoordinator
  let mode: PadMode
  let initial: NSAttributedString

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = PadTextView.scrollableTextView()
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    let textView = scrollView.documentView as? PadTextView ?? PadTextView()
    textView.configure(for: mode)
    textView.textStorage?.setAttributedString(initial)
    // The identifier goes on the text view itself rather than on the SwiftUI
    // wrapper, because that is the element carrying the accessibility value the
    // UI suite reads.
    textView.setAccessibilityIdentifier("pad.editor")
    textView.setAccessibilityLabel("Pad contents")
    coordinator.attach(textView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    let textView = scrollView.documentView as? PadTextView
    textView.map { $0.configure(for: mode) }
  }
}
