# Itchy — Vision

*Draft, September 2026*

## The problem we are trying to address

A significant amount of the text we handle in a working day has a life measured in hours or weeks, and no natural home anywhere in that window. A tracking number, a block of JSON from a failing request, a paragraph of copy that three people are still arguing over, a partial SQL statement, a screenshot of a table someone pasted into Teams — each of these needs to be held somewhere legible, referred to a few times, pasted into two or three other applications, and then left alone until it either becomes relevant again or quietly stops mattering.

The tools currently absorbing that traffic were built for other purposes, and each fails in a specific way. A note-taking application asks for a title, a folder, and a commitment to permanence that the content does not deserve; the cost of filing exceeds the value of the item, so the item does not get filed. A clipboard manager retains the content but treats it as a stream of undifferentiated events, which means the item is recoverable only if you can remember roughly when it passed through and can recognise it in a list of two hundred similar-looking entries. An untitled TextEdit window holds the content well enough until the day the machine restarts. Slack messages to oneself work, in the sense that the content survives, at the cost of routing internal working state through a corporate system of record.

What is missing is a place that behaves like the desk surface rather than the filing cabinet — persistent, immediately reachable, indifferent to organisation, and forgiving about what gets put on it.

## What Itchy is

Itchy is a menubar-resident scratchpad service for macOS. It presents a small fixed set of pads, on the order of eight to ten, reachable from a single click in the menubar. Opening a pad produces a floating window that can be positioned anywhere on the display, retains its position, accepts styled text and pasted images, and holds its contents indefinitely without being asked to. Closing the window puts the pad away without any save prompt or filing decision; the content is simply still there the next time the pad is opened.

The editing model sits somewhere between Stickies and an early TeachText — enough formatting support that pasted content survives with its structure intact, enough conversion tooling that styled content can be flattened to plain text on demand, and no ambition beyond that. There is no outline mode, no document library, no tagging, and no search across a corpus, because the corpus is ten items and the user can see all of them at once.

The name follows from the function; a scratchpad is for scratches.

## What Itchy is not

It is not a note-taking application and will not grow into one. Once a piece of content has earned a title and a place in a hierarchy, it belongs in whatever system already serves that purpose, and Itchy's job at that point is to export it cleanly and let it go. It is not a clipboard history manager, although it will interoperate with one. It is not a document editor, and the moment a feature request begins with the words "it would be useful if it could also," the appropriate response is to check whether the request is about transient content or permanent content, and to decline it if the latter.

## The state of the field, stated fairly

This category is well served, and the honest case against building anything here is strong enough that it should be set out before the case for.

Antinote covers the core of what is described above, does it well, and sells for five dollars with a lifetime licence. It opens on a global hotkey over fullscreen applications, navigates by gesture, and handles inline arithmetic, currency conversion, and unit conversion through natural-language input, along with mode keywords that turn a pad into a calculator or a checklist. Tot occupies the fixed-slot design space with seven colour-coded pads and syncs across devices. SideNotes handles the edge-panel model, Noticky the floating-sticky-over-fullscreen model, and Apple's own Stickies has shipped since 1994. Inline calculation in particular, which was on our initial feature list, is thoroughly claimed, and Soulver and Numi occupy the ground beyond that.

Any new entrant that differentiates on being a faster, prettier, or slightly more capable scratchpad is competing on ground that is already occupied by mature products with years of polish, and would deserve to lose. Adding a model-backed chat panel does not change that assessment; every incumbent in this category can add one in a sprint, and several already have, which makes it a feature rather than a position.

## The position we would take

Our view is that the one thing none of these applications can adopt without reconsidering what they are is to treat the pad as a surface that software agents can read from and write to.

The mechanism matters here, so it is worth setting out. When working with a coding agent, the exchange consists largely of text moving in both directions — a stack trace or a schema or a half-written function goes in, a diagnosis or a patch or a rewritten block comes back, and the human edits the result before it goes anywhere else. That traffic currently has no shared surface; it moves through the terminal scrollback, the clipboard, and a text editor window, and none of those is addressable by both parties. If each pad is exposed as a resource over the Model Context Protocol, the pad becomes a working surface that the agent and the person can both see, which changes the exchange from a conversation about text to shared custody of text. The agent can be told to put its output in pad four; the person can edit pad four and tell the agent to read it again; the content persists across agent sessions, which the agent's own context does not.

The usual framing of a feature like this is that the application should consume MCP input. We would suggest the inversion is more valuable, and it is also the harder thing to retrofit, because it requires the data model to be addressable, the storage format to be machine-readable, and the concurrency story to account for a second writer — all of which are architectural decisions that have to be made early.

Three secondary positions follow from the same reasoning and are worth holding, though none of them would justify the project on its own:

Content provenance. Recording which application and which URL a pasted chunk came from, along with when it arrived, addresses the actual failure mode of transient storage, which is not losing the content but losing the ability to reconstruct what it was for. Clipboard managers carry this information; note applications discard it.

Styled content and images. Much of the category is plain-text by design, and Antinote in particular is explicit that it holds no formatting and no images. Supporting pasted screenshots and preserved table structure is unglamorous and it is a real gap, particularly for anyone whose working material includes rendered content rather than source text.

Transforms ahead of conversation. Most of what a person would ask a model to do to a scratchpad — reformat this JSON, decode this string, strip this styling, change this case, tell me what changed between these two pads — is deterministic, instantaneous, and free. Building a transform menu where the model-backed operations sit alongside the deterministic ones, under the same interface, puts the cheap and reliable operations first and treats the model as one more transform rather than as the centre of the product.

Finally, and with some relevance to the content we personally handle, the model routing posture should be explicit and per-pad. A pad marked local should reach only a locally running model; a pad marked otherwise may reach a remote API. The default should be local, and the state should be visible on the pad itself.

## Who this is for

The primary user is the author, and that fact should be allowed to govern the design. The failure mode of a personal tool is to imagine a market partway through and start making compromises for users who do not exist.

If it does reach a wider audience, the plausible audience is developers who work with coding agents daily and who currently have no shared scratch surface between themselves and those agents. That is a narrow population, and it is a population that installs things.

## Staging

The first release should be the scratchpad and nothing else — menubar, pads, floating panels, styled text with images, indefinite retention, and the conversion tooling needed to flatten styling. This is deliberately unambitious, and it is also the part that has to be good, because every later capability is reached through it.

The transform menu and provenance capture follow, both of which are self-contained and neither of which requires network access. The MCP server comes third, once the storage format has settled enough that a second writer is safe. Model routing comes last, because it is the feature most likely to be reshaped by whatever the platform looks like by the time we reach it.

## How we would know it worked

The measure is behavioural rather than featural. If, a month after the first release is in daily use, working text is still being routed through messages-to-self and untitled editor windows, the application has failed regardless of how well it is built, and the reason will almost certainly be friction in the first two seconds of use. If the pads have absorbed that traffic, the project has succeeded at its stated purpose, and everything after that is a separate question.
