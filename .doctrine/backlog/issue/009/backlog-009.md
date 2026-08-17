# ISS-009: A repurposed slot provisions onto the previous assignment's residue

An assignment resets a slot's **tracked** files and nothing else. The guest's
checkout is reset by `receive.denyCurrentBranch = updateInstead`
(`vm/capsule.nix:203`), which checks out the pushed commit — so every untracked
and gitignored file in the work tree survives the act that was supposed to end
the assignment holding it. The volume's other trees (`/work/home`, the caches,
`/work/baseline`) survive it too, and nothing says so.

This is `NOTES item 50`'s
shape one tier out. There, a quarantine is keyed by the slot and outlives the
assignment that filled it; here, the **volume** is, and it does. Item 50's
state-half finding is the same mechanism seen from inside: the ref that
fast-forwards across a reprovision does so because it lives on the volume, which
a forced push to `work` does not touch.

## What `setup` does and does not do about it

`host/cli.nix`'s `handoff` owns two steps that exist for exactly this
(`NOTES item 53`'s decisions 3 and 5):
`archiveRefs` (`:1274`, called `:1773`) and `guestDropState` (`:118`, called
`:1790`). `setup` (`:1540`) calls neither. Both verbs stand a slot up on new
work; only one of them treats the slot as something that was already holding
some.

The asymmetry reads as deliberate for the archive — `handoff` is forcing over a
destination and `setup` is not — but the state chain is not about forcing. A slot
that has ever collected holds `refs/capsule/state/<stage>` on its volume, the
incoming `--state-from-host` chain is rooted elsewhere, and the push is refused
for a cause that is not the cause. `setup` has no interception for it, so the
first repurpose of any collected slot hits it.

## Observed, 2026-08-17, slot `a` — SL-254 to SL-256

Reassigning `a` from doctrine's `SL-254` (done, exhibit landed on `edge`) to
`SL-256`:

1. `capsule a setup edge --unit 256 --purpose … --state-from-host` was refused
   twice before it provisioned. First for the volume's stale state chain, dropped
   by hand with the `update-ref -d` that `guestDropState` would have run. Then
   for one modified tracked file — a regenerated `skills-lock.json` — under the
   message `ISS-003` is about, which sent a reader to `--force` for the second
   time in as many days.
2. Both refusals landed **after** the record writes, which is by design
   (`setup` writes `unit` and `purpose` in front of the push), so the slot was
   recorded as `SL-256`'s while still holding `SL-254`'s tree — generation 13, a
   base pinned to a commit the assignment had never had.
3. The tree it was then provisioned onto held 26 ignored/untracked entries of
   `SL-254`'s furniture: `.claude/sl254-orchestrator-brief.local.md`,
   `.doctrine/slice/254/phases`, `.doctrine/agents/`, `.doctrine/memory/shipped/`,
   `.claude/skills/`, `.codex/`.
4. One of those was **stale by exactly the change the finished slice made**.
   `.doctrine/agents/dispatch-worker.md` is a generated file (the install
   template's `{{ prompt resolve --role worker }}` expanded) and is gitignored at
   `.gitignore:52`. The guest's copy still carried
   `mcp__doctrine__worker_commit` in its `tools:` line — the token `SL-254`
   removed — and doctrine's own conformance test names that path as the entity it
   fails on. So the residue was not merely old: it contradicted the code shipped
   beside it, and the disagreement surfaced as a red test on the base ref.

The recovery was a hermetic reset with no verb behind it: `capsule a stop`, `sudo
rm /var/lib/microvms/a/capsule-work.img`, `capsule a start`, `ssh-keygen -R
capsule-a` for the fresh host keys, then `setup` again. Priced from
`docs/probes.md`: ~6.4 s to ssh on a cold volume and ~109 s for
the cold baseline, against ~50 s warm — so the whole reset is about two minutes
and the discarded crate cache is nearly all of it.

## What this does not prove (`STD-001`, `ADR-003`)

**The baseline failure is not attributed.** `just web-build test` exited 101 both
before the reset and after it (`/work/baseline/history.tsv`, `mib_before 133` on
the post-reset runs, so the volume was genuinely cold). The stale worker def is
established as *residue that crossed a provision* and as *the entity doctrine's
conformance check named*; whether it caused that exit is open, and on the fresh
volume `.doctrine/agents/` holds no claude worker def at all. Do not read step 4
as a diagnosis of the red baseline.

**Nothing here is a case suite.** Every observation is one live run on this host.
The refusals are reachable from `policyCases`' arrangement — item 53's suite
already builds two assignments to one slot — and the residue is not: it needs a
volume that has held one assignment and been provisioned into another.

## Directions, not a decision

- **Refuse rather than provision.** `setup` on a slot whose record carries a
  generation is a repurpose, and the honest answer may be to say so and name the
  reset, the way the dirty refusal names a remedy — with `ISS-003`'s lesson that
  the remedy has to be one that works.
- **Reset rather than refuse.** A `--fresh` that recreates the volume is the
  deterministic act an operator actually wants here, and it is
  `IMP-001`'s territory: volume verbs, and
  `plan-d-fleet.md` S4/S5's hand-typed `rm -rf`. Filed `after` it for that reason.
- **Carry `handoff`'s two steps into `setup`.** Cheapest of the three and fixes
  the two refusals rather than the residue. It does not touch `/work/home`, which
  is where an agent's own state from the previous unit of work lives.

Evidence rung (`STD-001`): observed on this host, once, in production; unbuilt.
