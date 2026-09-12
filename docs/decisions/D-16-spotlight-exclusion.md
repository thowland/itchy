# D-16 — Spotlight exclusion is a `.noindex` directory, not `.metadata_never_index`

*Spike S-3, run before Sprint 5. Supersedes D-10.*

## What D-10 said

`NFR-3.4` requires that pad contents do not surface in system-wide search, while
staying readable to `grep`, to ordinary tooling and — from R3 — to the MCP
server. D-10 satisfied it with an empty `.metadata_never_index` file written into
the support directory at first launch and re-asserted on every launch.

## What the spike found

`.metadata_never_index` **has no effect on a directory**. It is a volume-root
marker, not a per-directory one. Measured directly:

| Location | Marker | `mdfind` finds the content |
|---|---|---|
| `~/Library/Application Support/…` | none | yes |
| `~/Library/Application Support/…` | `.metadata_never_index` | **yes** |
| `~/Library/Application Support/…` | directory named `*.noindex` | **no** |

Two things needed establishing before believing that. The first is that
`~/Library/Application Support` is indexed at all — it is, confirmed by putting a
unique token there and finding it with `mdfind`. So `NFR-3.4` is a real
requirement rather than belt and braces, which is worth knowing on its own. The
second is that the test could detect a working mechanism; the `.noindex` row is
that control, and it is the mechanism Xcode uses for DerivedData.

## Decision

The pads directory is named `pads.noindex`. `.metadata_never_index` is no longer
written, because writing it implied a guarantee it never gave.

```
~/Library/Application Support/Itchy/
├── index.json
├── settings.json
└── pads.noindex/<uuid>/
```

The suffix is load-bearing and the tests say so: renaming that directory without
it silently restores Spotlight indexing of every pad, with nothing failing.

`.noindex` affects Spotlight only. `grep`, `cat`, the shadow files' intended
consumers and the MCP server are all unaffected — which is precisely the
distinction `NFR-3.4` draws.

## Migration

An install written before this change keeps its pads under `pads/`, where they
would stay indexed forever. On load, a legacy directory is renamed into place if
the new one does not yet exist — atomic, and it costs nothing. Verified in the
built application: an old-style install relaunches with its pad intact under
`pads.noindex`.

## What this changes elsewhere

Specification §6.1's layout and `NFR-3.4`'s acceptance criterion both now refer
to the directory name rather than to a marker file. The criterion itself is
unchanged and still the right one: content unique to a pad returns no Spotlight
hit, while `grep` over the support directory finds it. Verified both ways in the
built application.
