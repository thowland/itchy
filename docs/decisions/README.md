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
| D-10 | Spotlight exclusion by `.metadata_never_index` |
| D-11 | Decisions live in value-typed code; view files translate and apply |
