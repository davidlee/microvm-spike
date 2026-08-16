# docs — the map

Usage is [README.md](../README.md). How to work in this repo, plus the
architecture invariants and an index of the gotchas that have already cost time,
is [CLAUDE.md](../CLAUDE.md) — the gotcha bodies are in the memory corpus
(`doctrine memory search --tag gotcha`). **Governance is
[.doctrine/project-orientation.md](../.doctrine/project-orientation.md)** —
onboarding, routing, and the two id spaces. This file maps question to file for
the `docs/` tree, and that tree is now the *design* half: contracts, plans,
evaluations, and the frozen ledger.

| question | doc |
| --- | --- |
| where is this up to, what is next, what is still open? | `doctrine backlog list` and `doctrine knowledge list` — [status.md](./status.md) is a tombstone that maps the old sections onto them |
| why is it built like this? | [design.md](./design.md) |
| what must a repo be, for this to confine it? | [contract-target.md](./contract-target.md) |
| what is a slot assigned, and who may say so? | [contract-assignment.md](./contract-assignment.md) — record and policy built, selection of a profile unbuilt |
| where does a guest's tool set come from, and how does it compose? | [contract-flavour.md](./contract-flavour.md) — composition built (`fragments.nix`), selection unbuilt |
| what does doctrine ask of this, and supply to it? | [contract-doctrine.md](./contract-doctrine.md) |
| what does the confinement actually claim? | [threat-model.md](./threat-model.md) |
| why was *that* decided, and what was tried first? | [ledger/index.md](./ledger/index.md) — **closed archive**, items 1–54; new decisions are `doctrine adr new` |
| what has been measured, and what is the number? | [probes.md](./probes.md) |
| what would N capsules on one host cost? | [plan-c-multi-capsule.md](./plan-c-multi-capsule.md) |
| ...and what would implementing that touch? | [plan-c-implementation.md](./plan-c-implementation.md) |
| what does administering a fleet of them cost — across projects, refs and slices? | [plan-d-fleet.md](./plan-d-fleet.md) |
| how would this work without firecracker, or on macOS? | [plan-b-other-jails.md](./plan-b-other-jails.md) |
| what would a guest that is *not* a capsule cost — several people ssh'd into one shared box? | [plan-e-room.md](./plan-e-room.md) |
| which hypervisor, and why this one? | [eval-hypervisors.md](./eval-hypervisors.md) |
| why doesn't the capsule port to macOS? | [eval-macos.md](./eval-macos.md) |
| what does doctrine want from *this round* of probes? | [import-doctrine.md](./import-doctrine.md) — disposable packet |

## Conventions

- **[the ledger](./ledger/index.md) is a closed archive, cited as `NOTES item
  N`** — from source comments as well as from the other docs. The citation is an
  id, not a path: the item lives in `ledger/NNN-slug.md`, one file each, and
  moving or renaming a file changes nothing about how it is cited. Numbers are
  frozen: resolve an item in place, never renumber, never delete. **It stops at
  item 54 and takes no more** (`ADR-002`) — 238 of those citations are in source
  files, so the ids had to survive whatever replaced the ledger. New decisions
  are `doctrine adr new`.
- **[probes.md](./probes.md) owns the figures.** Link to it instead of copying a
  number — the last time a measurement lived in three files, two of them were
  the harness's own patience rather than the capsule's.
- **No file in `docs/` owns the present tense.** `capsule all status` answers
  what is true on this host, `git log` answers how it got true, and
  `doctrine backlog list` / `doctrine knowledge list` answer what is next and
  what is open. Plans record what a thing would cost, never whether it has
  happened. [status.md](./status.md) is the tombstone that maps the old sections
  onto those, and it is kept only because ~40 places link to it — an authored
  present tense reached 2463 lines here
  ([item 54](./ledger/054-status-grew-a-changelog.md)), and the eviction rule
  written to bound it was itself unenforced.
- **`contract-*.md` are the governing artifacts**, and they split by *authority*
  rather than by where a value happens to live: what a repo owes
  (`-target`), what the guest can do (`-flavour`), what a slot is assigned and
  who may say so (`-assignment`), and doctrine's two roles (`-doctrine`). Two of
  them describe a shape that is only partly built and say so at the top; a design
  artifact carries no state, so what exists is a backlog or knowledge record's to
  say.
- There is no changelog. `git log` is the record; the frozen ledger's resolved
  items carry the reasoning a changelog would lose, and `doctrine adr` carries it
  from here. **That is a claim on the
  commit message, not just a prohibition** — the one time the messages degraded
  to bare item numbers, a 720-line changelog grew at the top of status.md to
  hold what they stopped carrying, and nobody had written it down as a decision
  ([item 54](./ledger/054-status-grew-a-changelog.md)). The style the rule
  depends on is in [CLAUDE.md](../CLAUDE.md).
- `*.local.md` is gitignored — personal reference material, not project docs.
