# docs — the map

Usage is [README.md](../README.md). How to work in this repo, plus the
architecture invariants and the gotchas that have already cost time, is
[CLAUDE.md](../CLAUDE.md). Everything else is here.

| question | doc |
| --- | --- |
| where is this up to, what is next, what is still open? | [status.md](./status.md) |
| why is it built like this? | [design.md](./design.md) |
| what must a repo be, for this to confine it? | [contract-target.md](./contract-target.md) |
| what is a slot assigned, and who may say so? | [contract-assignment.md](./contract-assignment.md) — unbuilt |
| where does a guest's tool set come from, and how does it compose? | [contract-flavour.md](./contract-flavour.md) — unbuilt |
| what does doctrine ask of this, and supply to it? | [contract-doctrine.md](./contract-doctrine.md) |
| what does the confinement actually claim? | [threat-model.md](./threat-model.md) |
| why was *that* decided, and what was tried first? | [ledger/index.md](./ledger/index.md) — the numbered ledger |
| what has been measured, and what is the number? | [probes.md](./probes.md) |
| what would N capsules on one host cost? | [plan-c-multi-capsule.md](./plan-c-multi-capsule.md) |
| ...and what would implementing that touch? | [plan-c-implementation.md](./plan-c-implementation.md) |
| what does administering a fleet of them cost — across projects, refs and slices? | [plan-d-fleet.md](./plan-d-fleet.md) |
| how would this work without firecracker, or on macOS? | [plan-b-other-jails.md](./plan-b-other-jails.md) |
| which hypervisor, and why this one? | [eval-hypervisors.md](./eval-hypervisors.md) |
| why doesn't the capsule port to macOS? | [eval-macos.md](./eval-macos.md) |
| what does doctrine want from *this round* of probes? | [import-doctrine.md](./import-doctrine.md) — disposable packet |

## Conventions

- **[the ledger](./ledger/index.md) is cited as `NOTES item N`**, from source
  comments as well as from the other docs. The citation is an id, not a path:
  the item lives in `ledger/NNN-slug.md`, one file each, and moving or renaming
  a file changes nothing about how it is cited. Numbers are frozen and
  append-only: resolve an item in place, never renumber, never delete.
- **[probes.md](./probes.md) owns the figures.** Link to it instead of copying a
  number — the last time a measurement lived in three files, two of them were
  the harness's own patience rather than the capsule's.
- **[status.md](./status.md) owns the present tense.** Plans record what a thing
  would cost, not whether it has happened yet.
- **`contract-*.md` are the governing artifacts**, and they split by *authority*
  rather than by where a value happens to live: what a repo owes
  (`-target`), what the guest can do (`-flavour`), what a slot is assigned and
  who may say so (`-assignment`), and doctrine's two roles (`-doctrine`). Two of
  them describe a shape that is not built and say so at the top; a design
  artifact carries no state, so what exists is still status.md's to say.
- There is no changelog. `git log` is the record, and the ledger's resolved
  items carry the reasoning a changelog would lose.
- `*.local.md` is gitignored — personal reference material, not project docs.
