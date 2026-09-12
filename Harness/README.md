# itchyctl

Development-only command-line harness, built in Sprint 1. Not shipped.

It exercises `ItchyCore` and the store without the user interface — create, list,
read, write and delete pads, plus a `fault` subcommand that injects each case in
`PadStoreFault` for manual inspection (specification §6.7).

Its existence is part of why the store is testable: a storage layer that can only
be driven through a window is a storage layer that gets debugged by clicking.
