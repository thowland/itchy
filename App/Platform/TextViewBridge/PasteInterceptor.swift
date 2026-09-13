import AppKit
import ItchyCore

/// Reads the pasteboard into a descriptor and carries out the plan.
///
/// Every incoming paste and drop passes through here, because provenance capture
/// (`FR-7.1`) and image downsampling (`FR-4.3`) both hook in and neither should
/// have its own entry point (specification §9.4). The decisions themselves are in
/// `PastePlan` and `DownsamplePolicy`.
@MainActor
enum PasteInterceptor {
  /// Step 1 of §9.4, and the ordering that makes provenance correct: the source
  /// application is read from the tracker, not queried now.
  static func describe(
    _ pasteboard: NSPasteboard,
    source: NSRunningApplication? = PreviousAppTracker.shared.previous
  ) -> PasteDescriptor {
    var descriptor = PasteDescriptor()
    descriptor.sourceBundleID = source?.bundleIdentifier
    descriptor.sourceAppName = source?.localizedName

    descriptor.hasRTFD = pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.rtfd.rawValue])
    descriptor.hasRTF = pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.rtf.rawValue])
    descriptor.hasHTML = pasteboard.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.html.rawValue])

    let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage] ?? []
    descriptor.imageSizes = images.map(\.size)

    descriptor.plainText = pasteboard.string(forType: .string)
    descriptor.url = readWebURL(from: pasteboard)
    descriptor.fileURLs = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
    descriptor.fileURLs = descriptor.fileURLs.filter(\.isFileURL)
    descriptor.byteCount = byteCount(of: pasteboard, images: images)
    return descriptor
  }

  /// The web URL browsers put alongside the HTML, not a dragged file.
  static func readWebURL(from pasteboard: NSPasteboard) -> URL? {
    guard let text = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string),
      let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme == "http" || url.scheme == "https"
    else { return nil }
    return url
  }

  private static func byteCount(of pasteboard: NSPasteboard, images: [NSImage]) -> Int {
    let textBytes = pasteboard.string(forType: .string)?.utf8.count ?? 0
    let imageBytes = images.reduce(0) { total, image in
      total + Int(image.size.width * image.size.height * 4)
    }
    return max(textBytes, imageBytes)
  }

  /// Applies a plan to the text view, as one undoable operation.
  ///
  /// Returns the provenance entry to record, if any. Nothing is written to disk
  /// here: the change notification stages through the store exactly as a
  /// keystroke does.
  @discardableResult
  static func apply(
    _ plan: PastePlan,
    descriptor: PasteDescriptor,
    from pasteboard: NSPasteboard,
    to textView: NSTextView,
    now: Date = Date()
  ) -> ProvenanceEntry? {
    guard plan.representation != .nothing else { return nil }
    let insertion = textView.selectedRange().location
    let font = (textView as? PadTextView)?.bodyFont ?? ContentCodec.defaultFont
    let inserted = attributedValue(
      for: plan, descriptor: descriptor, pasteboard: pasteboard, font: font)
    guard inserted.length > 0 else { return nil }

    textView.undoManager?.beginUndoGrouping()
    textView.undoManager?.setActionName("Paste")
    textView.insertText(inserted, replacementRange: textView.selectedRange())
    textView.undoManager?.endUndoGrouping()

    return ProvenanceBuilder.entry(
      from: descriptor, plan: plan, insertedAt: insertion, length: inserted.length, now: now)
  }

  /// Builds what actually gets inserted.
  static func attributedValue(
    for plan: PastePlan,
    descriptor: PasteDescriptor,
    pasteboard: NSPasteboard,
    font: NSFont = ContentCodec.defaultFont
  ) -> NSAttributedString {
    guard !plan.discardsStyling else {
      return NSAttributedString(string: descriptor.plainText ?? "", attributes: [.font: font])
    }
    switch plan.representation {
    case .rtfd, .rtf, .html:
      return readStyled(from: pasteboard) ?? plainFallback(descriptor, font: font)
    case .image:
      return imageAttachment(plan: plan, pasteboard: pasteboard) ?? NSAttributedString()
    case .plainText:
      return plainFallback(descriptor, font: font)
    case .nothing:
      return NSAttributedString()
    }
  }

  private static func plainFallback(_ descriptor: PasteDescriptor, font: NSFont) -> NSAttributedString {
    NSAttributedString(string: descriptor.plainText ?? "", attributes: [.font: font])
  }

  private static func readStyled(from pasteboard: NSPasteboard) -> NSAttributedString? {
    let classes: [AnyClass] = [NSAttributedString.self]
    let objects = pasteboard.readObjects(forClasses: classes) as? [NSAttributedString]
    return objects?.first
  }

  /// `FR-4.3`: images above the threshold are downsampled on arrival, so a pad
  /// accumulating screenshots cannot grow without anyone noticing.
  private static func imageAttachment(
    plan: PastePlan,
    pasteboard: NSPasteboard
  ) -> NSAttributedString? {
    guard let image = (pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first
    else { return nil }
    let target = plan.downsampleTargets.first.flatMap { $0 }
    let final = target.map { ImageResampler.resample(image, to: $0) } ?? image
    let attachment = NSTextAttachment()
    // D-15: `image`, not `attachmentCell` — RTFD serialises the attachment's
    // file wrapper, and a cell-based attachment has none.
    attachment.image = final
    return NSAttributedString(attachment: attachment)
  }
}

/// Performs the resampling `DownsamplePolicy` asks for.
enum ImageResampler {
  static func resample(_ image: NSImage, to size: CGSize) -> NSImage {
    let result = NSImage(size: size)
    result.lockFocus()
    image.draw(
      in: NSRect(origin: .zero, size: size),
      from: NSRect(origin: .zero, size: image.size),
      operation: .copy,
      fraction: 1.0)
    result.unlockFocus()
    return result
  }
}
