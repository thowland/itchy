# D-19 — The editor font is a setting, and it reaches text already in a pad

*Taken during fit-and-finish, after R1.*

## What was asked

The editor's font was fixed at the system monospaced font at thirteen points,
which the author found too small to read comfortably. Settings now carry a
font family and a size. This is a reading-comfort preference rather than a
feature for keeping content, so it does not touch `CON-3`; it is recorded as
`FR-4.10`.

## Why the setting cannot simply be a default

A styled pad is RTFD, and RTFD stores a concrete font in every run of text.
There is no "default font" in the stored content for a setting to change: the
thirteen-point monospaced font is written into each run as the text is typed. A
setting that only governed new typing would leave every existing pad at the old
size, which fails the reason the setting was asked for.

Three answers were considered, and the author chose the first:

1. **Restyle body text.** Text in the editor's own font follows the setting;
   text that arrived in a font of its own keeps it.
2. **New text only.** Nothing stored changes, and existing pads stay small.
3. **Zoom.** Scale the rendering and leave fonts alone. It enlarges images too,
   and it is a magnification level rather than the font setting that was asked
   for.

## Which text is body text

`EditorFontPolicy.treatment(runFamily:mode:bodyFamilies:)` decides per run:

- In a **plain** pad, every run takes the font with no traits. A plain pad holds
  no attributes (`FR-4.4`), so there is nothing to preserve.
- In a **styled** pad, a run is body text when its family is one of the body
  families, or when it has no font at all. Body text takes the chosen family and
  size and keeps bold and italic. Every other run is left exactly as it was.

The body families are the built-in family (`.AppleSystemUIFontMonospaced`,
which every pad written before this setting is set in), the family currently
chosen, and up to eight families chosen previously.

The previous families are remembered because restyling happens in two places:
immediately in every open pad when the setting changes, and on the way into a
panel when a pad is opened. A pad that was closed while Menlo was chosen, and is
reopened after the setting has moved on to Courier, is set in Menlo, and without
the history it would not be recognised as body text. The list is bounded
because each remembered family is one more font in which pasted text could be
mistaken for the editor's own.

## What this gives up

A deliberate size change on text in the editor's own font is lost. Using Format
▸ Bigger on a line of body text and then changing the setting sets that line
back to the chosen size. That was accepted: a scratchpad is not where careful
typography lives, and the alternative left the setting unable to do its job.

Pasted text in a family the author once chose as the editor font is also treated
as body text. That is the cost of the history, and it is bounded by the history
being bounded.

## Neither undoable nor staged

Restyling changes attributes only. It registers no undo step, because it is not
an edit to what the pad says, and it does not stage the pad, because a settings
change should not rewrite every open pad on disk. Content read from the store is
restyled when it is opened in any case, and the pad's next save carries the new
fonts with it.

## Where it lives

- `AppSettings.editorFontFamily` (`nil` for the built-in font),
  `editorFontSize`, and `formerEditorFontFamilies`, with range and history
  bounds in `EditorFontBounds`, clamped on read like the pad limit.
- `EditorFontPolicy` makes the decisions. `BodyFont` resolves the font and
  applies the policy to an attributed string. A family that is no longer
  installed falls back to the built-in font at the chosen size, not to AppKit's
  twelve-point Helvetica.
- The paste fallback and flattening use the editor font rather than the
  built-in one, so plain pads stay in a single font.

## Known edge

Content the core writes directly (`PadContent.plainText`, used by the harness
and in time by agent writes) names `SFMono-Regular` in its RTF font table. That
name does not resolve, so the text decodes as twelve-point Helvetica. In a plain
pad the setting still reaches it. In a styled pad it does not, because
Helvetica is not a body family, and adding Helvetica would catch most pasted web
text. The better fix is for the core to write a font name that resolves, which
is a change to the storage format and is left for when agent writes arrive
(Sprint 9).
