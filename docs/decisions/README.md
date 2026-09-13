# Decision log

Decisions D-1 through D-11 were taken in `../itchy-specification.md` §2 and live
there with their reasoning attached. They are indexed here so that this
directory is a complete record rather than a partial one.

New decisions taken during implementation get their own file here, numbered from
D-12, following the same shape: what was decided, and why, in enough detail that
someone can reverse it later knowing what they are giving up. A decision that
contradicts the specification updates the specification in the same commit.

| # | Decision |
|---|---|
| D-1 | Swift 6.3, strict concurrency from the first commit; `swift-format` from the Xcode toolchain, not Homebrew |
| D-2 | Local SPM packages for Core and Services; an Xcode app target for Platform and Interface |
| D-3 | Swift Testing for new tests; XCTest only where its machinery is required |
| D-4 | No third-party dependencies in R1 or R2 |
| D-5 | MCP transport deferred to spike S-4, with the official Swift SDK as the stated default |
| D-6 | Carbon `RegisterEventHotKey` for the global hotkey, not a global event monitor |
| D-7 | A directory per pad, written atomically, with a schema version in every JSON file |
| D-8 | The shadow text file is written by the store, inside the same save, for every pad |
| D-9 | Undo lives on the text view; the store defers to it |
| D-10 | Spotlight exclusion by `.metadata_never_index` — **superseded by D-16** |
| D-11 | Decisions live in value-typed code; view files translate and apply |

New decisions:

| # | Decision |
|---|---|
| [D-12](D-12-xcode-project.md) | The Xcode project is generated from a checked-in `project.yml`; `Itchy.xcodeproj` is not committed |
| [D-13](D-13-rtfd-bundle-representation.md) | Pad content is an RTFD bundle map, not opaque `Data` |
| [D-14](D-14-panel-activation.md) | A pad appearing does not activate; a pad focused necessarily does |
| [D-15](D-15-spike-s2-resolved.md) | Spike S-2 resolved: `TextEditor` still does not render attachments; §9.1 stands |
| [D-16](D-16-spotlight-exclusion.md) | Spotlight exclusion is a `.noindex` directory, not `.metadata_never_index`; supersedes D-10 |
| [D-17](D-17-spike-s1-s4.md) | Spikes S-1 and S-4 resolved: Carbon hotkey stands, MCP SDK adopted |
| [D-18](D-18-archives.md) | Pads are archived automatically; retention, including none, is the user's |
| [D-19](D-19-editor-font.md) | The editor font and size are settings, and body text already in a pad follows them |
| [D-20](D-20-formatting-controls.md) | Styled pads get bold, italic and underline, as buttons and as ⌘B/⌘I/⌘U |
| [D-21](D-21-pad-settings.md) | Each pad has its own settings sheet, reached from the pad; open panels see live metadata |
| [D-22](D-22-versioning.md) | Semantic versions biased toward patches, set in an xcconfig; About shows version and build |
