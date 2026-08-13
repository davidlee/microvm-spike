# docs — the map

Usage is [README.md](../README.md). How to work in this repo, plus the
architecture invariants and the gotchas that have already cost time, is
[CLAUDE.md](../CLAUDE.md). Everything else is here.

| question | doc |
| --- | --- |
| where is this up to, what is next, what is still open? | [status.md](./status.md) |
| why is it built like this? | [design.md](./design.md) |
| what must a repo be, for this to confine it? | [contract-target.md](./contract-target.md) |
| what does doctrine ask of this, and supply to it? | [contract-doctrine.md](./contract-doctrine.md) |
| what does the confinement actually claim? | [threat-model.md](./threat-model.md) |
| why was *that* decided, and what was tried first? | [notes.md](./notes.md) — the numbered ledger |
| what has been measured, and what is the number? | [probes.md](./probes.md) |
| what would N capsules on one host cost? | [plan-c-multi-capsule.md](./plan-c-multi-capsule.md) |
| ...and what would implementing that touch? | [plan-c-implementation.md](./plan-c-implementation.md) |
| what does administering a fleet of them cost — across projects, refs and slices? | [plan-d-fleet.md](./plan-d-fleet.md) |
| how would this work without firecracker, or on macOS? | [plan-b-other-jails.md](./plan-b-other-jails.md) |
| which hypervisor, and why this one? | [eval-hypervisors.md](./eval-hypervisors.md) |
| why doesn't the capsule port to macOS? | [eval-macos.md](./eval-macos.md) |
| what does doctrine want from *this round* of probes? | [import-doctrine.md](./import-doctrine.md) — disposable packet |

## Conventions

- **[notes.md](./notes.md) is cited as `NOTES item N`**, from source comments as
  well as from the other docs. Numbers are frozen and append-only: resolve an item
  in place, never renumber, never delete.
- **[probes.md](./probes.md) owns the figures.** Link to it instead of copying a
  number — the last time a measurement lived in three files, two of them were the
  harness's own patience rather than the capsule's.
- **[status.md](./status.md) owns the present tense.** Plans record what a thing
  would cost, not whether it has happened yet.
- There is no changelog. `git log` is the record, and the ledger's resolved items
  carry the reasoning a changelog would lose.
- `*.local.md` is gitignored — personal reference material, not project docs.
