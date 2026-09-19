# D-26 — A diagnostic log that cannot quote you, and help that lives in the binary

*Taken September 2026, alongside the MCP server's first weeks of use.*

## Why both at once

They are the same problem seen from two sides. The MCP boundary is the first
part of Itchy whose behaviour is not visible from the interface: a write that
went to the store rather than the panel, a backup that decided not to happen, an
agent request refused before it reached the SDK. The log is for the person
building it; the help is for the person using it. Neither existed, and the
absence of both was starting to show.

## The diagnostic log

### It is off, and it is in `/tmp`

Off by default, because it is a thing somebody switches on to reproduce a
problem rather than a thing that should be running. The setting persists across
launches anyway, since the problems most worth a log are the ones that happen
during startup, and a log you have to switch on after launch cannot see them.

`/tmp` rather than the support directory, for two reasons. The person has to be
able to find it and send it, and `/tmp` is a path that can be said out loud. And
the system sweeps it, so a log switched on and forgotten does not accumulate in
their Library indefinitely.

### It cannot say what is in a pad

This is the part that mattered, and it is structural rather than a policy.

`LogEvent`'s initialiser is private. The only way to make one is a factory, and
the factories take counts where they could take content: `chars=41`, never the
forty-one characters. So no call site can log a pad's text, and adding something
the log is able to say means editing one file that somebody reviews.

The alternative — a `log(_ message: String)` and a convention — would have been
one careless interpolation away from a world-readable file containing the text
of every agent write. Pads are kept out of Spotlight (`NFR-3.4`) and exposed to
nothing until the person says so (`NFR-3.2`); a diagnostic file that quietly
undid both would be the worst kind of feature, the sort that is only discovered
to have been a mistake afterwards.

Pad *names* are recorded. That is a real if small concession: `/tmp` is readable
by anyone with an account on the machine. It is made because half of what there
is to debug at the MCP boundary is name resolution, and a log of identifiers
alone is useless for it. The settings caption and the log's own header both say
so, so nobody switches it on without being told.

### It is synchronous, and it never reports a failure

Synchronous because a call site on the typing path must cost nothing and must
not need an `await` — a logger you have to await is a logger that changes the
ordering of the thing it was meant to observe. Disabled, `record` is a lock, a
nil check and a return.

It never throws and never surfaces an error. There is nowhere sensible to report
"could not write the log" to, and a logger that interrupts what it is observing
is worse than no logger.

The file restarts rather than rotating into numbered siblings. This is a
diagnostic for something happening now; yesterday's events in a second file are
clutter nobody reads. Switching logging on truncates, so the first line is
always the start of the attempt.

### What it found on its first real run

Two things, within a minute of being pointed at a running build, which is the
argument for having built it.

`archiveIfNeeded` reported `outcome=failed` on a fresh store. `takeArchive`
answers nil when there are no pads and throws when the copy fails, and the
coordinator had flattened both with `try?`. A new user's first launch was
recording a failed backup. `ArchiveAttempt` now distinguishes
`nothingToArchive` from `failed`.

And the launch archive ran twice, because the daily call fell back to `.launch`
when daily archiving was switched off. The second was always a no-op — the
fingerprint had not changed since the first, a moment earlier — but it said so
twice, and a log that repeats itself teaches you to skim it.

Both were pre-existing, both were invisible, and both were found by reading four
lines of output.

### `ArchivePolicy.due` beside `shouldArchive`

`shouldArchive` returns a `Bool`, which D-11 says a decision should not. It is
kept, because most callers want only the answer. `due` is the same decision
returning the reason, and it exists because "there is no backup" has four causes
the person cares about telling apart. A test holds the two to each other across
every combination, so they cannot drift.

## The help

### It is Swift values, not a bundled document

Not a stylistic choice. `CON-4` makes the store the only component that touches
disk, so a help view that loaded a Markdown resource would either break that
rule or route documentation through the pad store, and both are worse than
writing the prose in Swift.

Values buy something back. The content is compiled, so the suite can hold help
to the same standard as code: every topic has sections, every sidebar symbol
exists on this system, and — the useful one — what the prose says about a
control is checked against the control. The pad ceiling, the retention
default and maximum, the pads directory name, the log's path and the two
settings labels are interpolated from the code rather than typed as prose, so
they cannot go stale. An early draft said "ten is the default and fifty is the
most" in words, and a test asserting the numbers would have passed for the wrong
reason.

### The view decides nothing

`HelpView` is a view file and so may not branch (D-11, §15.3). It cannot switch
over a block kind to choose a font. So `HelpBook.lines(for:)` flattens a topic
into lines that each carry concrete numbers — size, indent, opacity, the space
above — and the view maps them straight onto modifiers. The one thing that
cannot be a number, the font weight, goes through `HelpWeight`.

That is more indirection than a help window deserves on its own. It is the same
rule the rest of the interface follows, and the alternative is an exception
whose justification is that this file is not very important.

### Two ways in, and no search

From the menubar, because it is the only part of Itchy that is always visible,
and from About, because that is where people go to find out what something is.

No search across topics. Six topics fit in a sidebar, and searching six things
is slower than reading their titles. This is the same argument `CON-1` makes
about pads, applied to a much smaller collection.

## The token store seam

Not planned, and found by the suite hanging.

The agent-server tests reached for the real Keychain, and macOS asked the person
running them whether this binary could read an item a differently-signed build
had created. Every run stopped until somebody answered. On CI nobody would have.

`MCPTokenStore` is now the seam: the application resolves to `MCPTokenKeychain`
and everything else to `InMemoryTokenStore`, with `TokenStoreResolver` making
the choice. `arch-lint` gained a fifth check forbidding any file under `Tests`
or `Harness` from naming the Keychain type, with no exception mechanism — a rule
with an escape hatch is a rule that erodes, and this is the kind of failure that
does not look like a failure. It looks like a machine that has stopped.

It is also an early sighting of the problem the stdio shim is blocked on. A
Keychain grant is keyed to the code hash, so an ad-hoc signed build asks again
after every rebuild. The answer is the same one D-17's note about TCC gives:
sign Debug with a real identity.

## What would reverse any of this

If the log ever needs to carry a pad's text — to reproduce a corruption, say —
the closed vocabulary is what stands in the way, and it should. The right move
would be a separate, explicitly-named export that the person invokes once, not a
widening of what the log may say.

If the help grows past a dozen topics, the sidebar stops being a table of
contents and search starts earning its place. Six is not that.
