# CHR-012: Close ADR-003's two cross-corpus gaps

`ADR-003` sets the ownership rule — this repo mints evidence about its own
mechanism, doctrine mints evidence about doctrine's choice and cites across — and
then admits, in *Verification*, that nothing enforces either half. Two gaps, and
they are different sizes.

**1. The dispute needs its other half, and only a human on doctrine's side can
write it.** `EVD-002` here now names doctrine's `EVD-019` and says the 8.31 s
headline must not be read as time-to-interactive. doctrine's `EVD-019` says
nothing about this record, and `QUE-217` reads doctrine's side. One sentence in
`EVD-019`'s body, in doctrine's repo — not this repo's to write.

While there: `EVD-025` cites `../microvm-spike/docs/eval-macos.md` and
`../microvm-spike/docs/plan-b-other-jails.md`. Both are relative paths out of one
working tree into another, resolving only from a directory neither repo declares,
and both name this repo under its old checkout name. `ADR-003` clause 2 says
repo-relative, so those are `docs/eval-macos.md` and `docs/plan-b-other-jails.md`
qualified by the repo, not by `..`.

**2. Neither mechanism exists, and both live in doctrine.**

- **A cross-corpus lint** for clause 1: grep doctrine's `EVD` bodies for this
  repo's paths (`probe/`, `host/`, `capsule-*`, `microvm-spike`) and report any
  record whose subject is oubliette's mechanism rather than doctrine's choice.
  Cheap, and the only thing that makes clause 1 more than prose.
- **A cross-corpus relation.** `doctrine link EVD-002 disputes EVD-019` refuses:
  a target resolves only within one corpus. So every citation across the boundary
  is a sentence, invisible to `backlinks`, `relation census` and every
  reachability question. That is a doctrine feature request, not a fix here, and
  it may well be the right refusal — but `ADR-003` is the second consumer to want
  it and the first to be blocked by it.

Nothing here is oubliette's to build. What this item is for is that the ADR does
not read as if the gaps were closed.

Evidence rung (`STD-001`): `ADR-003` is **build** — written and unenforced. This
item is what would move it.
