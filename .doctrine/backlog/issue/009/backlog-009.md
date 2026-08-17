# ISS-009: A repurposed slot provisions onto the previous assignment's residue

An assignment resets a slot's **tracked** files and nothing else. The guest's
checkout is reset by `receive.denyCurrentBranch = updateInstead`
(`vm/capsule.nix:203`), which checks out the pushed commit — so every untracked
and gitignored file in the work tree survives the act that was supposed to end
the assignment holding it. The volume's other trees (`/work/home`, the caches,
`/work/baseline`) survive it too, and nothing says so.

This is `NOTES item 50`'s shape one tier out. There, a quarantine is keyed by the
slot and outlives the assignment that filled it; here, the **volume** is, and it
does. Item 50's state-half finding is the same mechanism seen from inside: the
ref that fast-forwards across a reprovision does so because it lives on the
volume, which a forced push to `work` does not touch.

## What is already decided, and the one axis it is silent on

**`Plan D` D4 owns the framing, and states it harder than this item first did.**
A volume carries the previous assignment's caches and build tree, and under a new
owner those "are not stale garbage — they are *input supplied by a different
principal*, and a build that reads them is a build the new owner did not
specify." So reuse is refused on a non-clean volume with `--reset` as the answer,
and a dev host may waive that by declaration.

**Its refusal set is project, flavour and policy. The axis this item is about is
`unit`.** Slot `a`'s repurpose changed none of the three — same profile, same
policy, same extras, same human — and D4 as written would not have refused it.
That is not evidence anyone excluded `unit`: the field arrives at `NOTES item 32`,
after the plan's text. The question D4 never got asked is whether **a slice
boundary is a change of principal**, and the observed harm below is the argument
that it is at least a change of *author*: one agent's generated output
contradicting the next agent's code.

**`Plan D` D3 owns the verb.** `capsule <slot> volume {df,reset,reset-home,
clone-from <m>}`, host-side, refusing while the VM runs; `reset` is S4 without
the hand-typed `rm -rf`. There is no `resize` because the size is a `truncate`
applied only when the image is absent (§5), so a reset *is* delete and recreate.
Nothing here should mint a second name for it — an earlier draft of this item
proposed a `--fresh`, which is that mistake.

## What `setup` does and does not do about it

`host/cli.nix`'s `handoff` owns two steps that exist for exactly this
(`NOTES item 53`'s decisions 3 and 5): `archiveRefs` (`:1274`, called `:1773`)
and `guestDropState` (`:118`, called `:1790`). `setup` (`:1540`) calls neither.
Both verbs stand a slot up on new work; only one of them treats the slot as
something that was already holding some.

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
3. The tree it was then provisioned onto held 26 ignored and untracked entries of
   `SL-254`'s furniture: `.claude/sl254-orchestrator-brief.local.md`,
   `.doctrine/slice/254/phases`, `.doctrine/agents/`, `.doctrine/memory/shipped/`,
   `.claude/skills/`, `.codex/`.
4. One of those was **stale by exactly the change the finished slice made**.
   `.doctrine/agents/dispatch-worker.md` is a generated file (the install
   template's `{{ prompt resolve --role worker }}` expanded) and is gitignored at
   `.gitignore:52`. The guest's copy still carried `mcp__doctrine__worker_commit`
   in its `tools:` line — the token `SL-254` removed — and doctrine's own
   conformance check names that path as the entity it fails on. So the residue was
   not merely old: it contradicted the code shipped beside it.

The recovery was a hermetic reset with no verb behind it — S4's *today*, executed
by hand: `capsule a stop`, `sudo rm /var/lib/microvms/a/capsule-work.img`,
`capsule a start`, `just reset-known-hosts a` for the fresh host keys, then
`setup` again. Priced from `docs/probes.md`: ~6.4 s to ssh on a cold volume and
~109 s for the cold baseline against ~50 s warm — so the reset is about two
minutes and the discarded crate cache is nearly all of it.

## What this does not prove (`STD-001`, `ADR-003`)

**The baseline failure is not attributed.** `just web-build test` exited 101 both
before the reset and after it (`/work/baseline/history.tsv`, `mib_before 133` on
the post-reset runs, so the volume was genuinely cold). The stale worker def is
established as *residue that crossed a provision* and as *the entity doctrine's
conformance check named*; whether it caused that exit is open, and on the fresh
volume `.doctrine/agents/` holds no claude worker def at all. Do not read step 4
as a diagnosis of the red baseline.

**Nothing here is a case suite.** Every observation is one live run on this host.
The refusals are reachable from `policyCases`' existing fixture — it substitutes
`capsules` and `moduleState`, so a refusal that reads only the record lands in
the sandbox, which is the arrangement item 53's 80 rounds already use. The
*residue* is not reachable there: it needs a volume that has held one assignment
and been provisioned into another.

**`handoff`'s two steps have themselves never run on a host** (item 53: the
verify, the archive and the drop). `CHR-002` is the open item for that, and this
item's hand-run drop is the closest anything has come.

## Disposition — two steps, in this order

Executed off this item rather than promoted to a slice: small scale, and the
first step is a few lines in a branch that already exists. Recorded here because
the *order* is a human's call and was made deliberately (2026-08-17): reuse is
what the operator wants in practice, a fresh VM per slice is the posture worth
having, so the cheap correctness fix goes first and the posture follows it.

1. **Carry `handoff`'s two steps into `setup`.** `archiveRefs` keyed on the
   record's generation, and `guestDropState` over the stages the collect just
   took, both skipped rather than refused where a slot has never been assigned.
   Kills both refusals from the run above, is coverable in `policyCases`'
   existing fixture, and **leaves the residue** — reuse keeps working, which is
   the default the operator asked for. Say that out loud in the change.
2. **Then the fresh half, on top of D3's `volume reset`.** The verb is D3's and
   the composition is `setup`'s, the way `setup` already composes provision,
   inject and baseline. Two names, deliberately, because they are two acts and
   the plan already separates them: **`volume reset`** discards the whole volume —
   checkout, caches, `$HOME`, host keys — and **`volume reset-home`** is the
   `/work/home` half alone, which is where the previous agent's own state lives
   and which a checkout reset does not reach. A repurpose that names only one of
   them is under-specified.

Both steps are gated by things worth naming rather than discovering: a reset
refuses while the VM runs, and *running* is a question about a namespace and
never about a process name (`mem.fact.oubliette.dead-guest-is-not-a-dead-vm`);
the image is root-owned, so the delete needs the seam `capsule start` and
`host/proxy-restart.nix` already use; the fresh host keys have a home in
`just reset-known-hosts` and want no second copy; and the verb may not know what
a `.doctrine/` is — POL-002 makes the mechanism *recreate the volume*, never
*delete these paths*, which is the same reason `reset-home` is coarse.

Filed `after` `IMP-001` because step 2 needs D3. Step 1 needs nothing.

Evidence rung (`STD-001`): observed on this host, once, in production; unbuilt.
