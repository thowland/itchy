# D-18 — Pads are archived automatically, and the retention is the user's

*Taken during fit-and-finish, after R1.*

## What this is in tension with

`CON-1` prohibits a document library, and `CON-3` says a feature serving
permanent content is declined regardless of merit. Archives keep copies of pad
content after the pad is gone. Read strictly, they are the thing the vision
document exists to refuse.

They are added anyway, and the distinction is who they are for. An archive is
insurance against *us*: the storage format is still changing, this application
is at its first release, and a defect in the store would otherwise destroy
content with no way back. Nothing in the interface browses them, nothing
searches them, and no pad is reachable through them. They are a developer's
safety net that happens to live on the user's disk, and they should be removed
once the format has been stable for long enough that the risk they cover has
gone.

The author's instruction was explicit: "These are supposed to be ephemeral, but
given the state of the system and the likely development pace, let's bake this
in now." Recorded here so that the reason is reversible with the decision.

## What is kept, and where

```
~/Library/Application Support/Itchy/
└── archives.noindex/
    └── 2026-09-13-013935Z/
        ├── index.json
        └── pads/<uuid>/{content.rtfd/, content.txt, meta.json}
```

A whole copy of the pads tree — metadata, shadow text, and the RTFD bundles with
their images. Restoring is copying the directory back, which was verified by
deleting the live pads and doing exactly that. There is deliberately no restore
path in code: a recovery mechanism only ever runs when something has already
gone wrong, and one made of `cp` cannot itself be broken.

`archives.noindex` carries the suffix for the same reason `pads.noindex` does
(D-16, `NFR-3.4`). A backup that Spotlight indexes when the original is not
would be a privacy hole opened by the thing meant to prevent data loss.

## When

On launch, on quit, and optionally once a day — but only when the pads have
changed since the last archive. Without that check, a launch-and-quit cycle
takes two identical copies and a day of restarts fills the retention limit with
duplicates, pushing out the one snapshot that mattered. The comparison is a
fingerprint of pad count and latest modification time, so no content is read
(`FR-1.6` applies here too).

## The privacy cost, and who decides

An archive holds pads the user has since deleted. That is the point and it is
also the problem, so:

- Retention is a setting, and **zero is one of the answers** — it disables
  archiving entirely and is the honest option for someone who would rather no
  copies existed.
- The settings pane states the cost rather than implying it: that copies include
  deleted pads, and how to keep none.
- The number and total size of what is kept is displayed, so the cost is visible.
- "Delete All Backups" removes everything.
- There is a ceiling of fifty for the same reason the pad count has one: an
  unbounded setting erodes into unbounded disk use, and these hold real content.

## Cost in space

Copies are made with `clonefile`, so on APFS an archive shares storage with the
live pads and consumes nothing until one side changes. Measured: a pads
directory of 12K apparent produced a 16K archive whose files are distinct inodes
sharing extents. Without it, ten archives of a full store — twenty pads at the
64 MB ceiling — would be measured in gigabytes. The fallback to an ordinary copy
exists because `clonefile` fails across filesystems and on anything that is not
APFS, and an archive that refuses to be taken is worse than one that costs
space.

## When to remove this

When the storage format has been stable across several releases and the store
has not lost anything. At that point this is a document history for content the
vision document says should not have one, and it should go.
