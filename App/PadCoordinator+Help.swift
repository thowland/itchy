import AppKit
import ItchyCore

/// The help window, and the two ways into it.
///
/// Reachable from the menubar and from About, which are the two places somebody
/// who is stuck will already be looking: the menubar because it is the only
/// part of Itchy that is always visible, and About because it is where people
/// go when they want to know what a thing is.
extension PadCoordinator {
  func showHelp(topic: String = HelpBook.defaultTopic) {
    guard let existing = help else {
      presentHelp(topic: topic)
      return
    }
    // Already open on some topic. Bring it forward rather than opening a
    // second window on the same book; reopening it is how the topic changes.
    guard existing.topic == topic else {
      existing.close()
      presentHelp(topic: topic)
      return
    }
    existing.show()
  }

  var isShowingHelp: Bool { help?.isVisible ?? false }

  var helpTopic: String? { help?.topic }

  func closeHelp() {
    help?.close()
  }

  private func presentHelp(topic: String) {
    let controller = HelpWindowController(topic: topic) { [weak self] in
      self?.help = nil
    }
    help = controller
    controller.show()
  }
}
