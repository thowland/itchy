# D-15 — Spike S-2 resolved: `TextEditor` still does not render attachments

*Run at the start of Sprint 3, before any text-layer work.*

## The question

Specification §9.1 settles the editor as `NSTextView` rather than SwiftUI's
`TextEditor`, on the grounds that `TextEditor` does not render text attachments:
an attributed string loaded from RTFD with an embedded image reports the
attachment present and draws nothing. `FR-4.2` — pasted screenshots — is a
first-release requirement, so if that had been fixed on shipping macOS 26 the
decision was worth reopening. The `[VERIFY]` mark existed for exactly this.

## What was run

The same attributed string — text, an image attachment, more text — round-tripped
through RTFD and displayed twice side by side, once in `TextEditor` bound to an
`AttributedString` and once in an `NSTextView`. Captured as
`docs/spike-s2-texteditor-attachments.png`.

## Result

The behaviour is unchanged.

- The attachment survives the RTFD round trip: one attachment present.
- `AttributedString(_:including: \.appKit)` conversion succeeds, so the
  attachment reaches SwiftUI's model intact.
- `TextEditor` renders "Before the image.  After the image." — the text, and
  nothing where the image is.
- `NSTextView` draws the image inline, correctly.

This is the failure §9.1 describes, and it is the quiet kind: nothing throws,
nothing logs, the model is correct, and the image is simply absent.

## Decision

§9.1 stands. The editor is `NSTextView` wrapped in an `NSViewRepresentable`, and
the `[VERIFY]` mark is cleared. The decision is not to be revisited on the
grounds that the SwiftUI code would be shorter, because it would also not show
the user their screenshot.

## Incidental finding, worth keeping

An `NSTextAttachment` built with `attachmentCell` rather than `image` is dropped
silently by RTFD serialisation — the round trip reports zero attachments. The
first run of this spike hit it and briefly looked like evidence that RTFD could
not carry images at all. `ContentCodec` must therefore set `image` on
attachments it constructs, and Sprint 3's fixtures do.
