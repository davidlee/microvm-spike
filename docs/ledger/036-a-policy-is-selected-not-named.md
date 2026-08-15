# NOTES item 36 — a policy is selected from a declared set, never named by a project

*State: **two of four slices built and green, unswitched**. The vocabulary and
each slot's set are declared, and the allowlist is a policy's — selected by
`--policy` on the devshell path and by a per-slot symlink on the module path.
What is left is the two collect limbs, the `policy` verb that re-points the
symlink, and the cases; the checklist is at the foot of this file. This is
[item 25](./025-assignment-is-a-perimeter-verb.md)'s
resolution shape turned into a mechanism, and it is the run-time half of
[Plan D](../plan-d-fleet.md) D2 — the declaration half is
[item 30](./030-a-pool-audits-what-exists.md)'s and has landed.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What is still fused

`target.nix` holds `allowlist` and `collectMaxPackBytes`, and both are controls.
The allowlist is one file for the whole fleet, named by the target, and the
ingestion bound is one integer beside it. That was invisible while a target was a
build-time literal and one capsule ran one project. The pool makes it visible: ten
slots share one allowlist because the only thing that could vary it is the value
that also says which project a slot holds.

Item 25 states the exposure precisely and it is worth restating, because it is
*not* the obvious one. The guest cannot widen its own egress — the record is
host-side, the guest has no route to it and no channel to ask, and none of that
changes. The exposure is **authority**: whoever may hand slot `d` a project may
hand it a different allowlist, because the project names the allowlist. The verb
Plan D wants cheap, frequent and delegable is the same verb that decides what a
capsule may talk to.

On this host the assigner and the host operator are one human, so the fusion
costs nothing today. It costs everything the first time a program assigns.

## The shape

**A policy is a host declaration in its own file.** `policies.nix`, for the same
reason `net.nix`, `target.nix` and `capsules.nix` are files: several places need
these values and none may spell them twice. Each entry is the three limbs
[contract-assignment.md](../contract-assignment.md) gives the noun:

| limb | what it is | where it is read |
| --- | --- | --- |
| `allowlist` | a plain-file path, not a store path | the proxy, at start |
| `collectMaxPackBytes` | the ingestion bound | `capsule-collect`, per fetch |
| `mayCollect` | whether this slot may collect at all | `capsule-collect`, before the door opens |

All three move out of `target.nix` in one change. Moving only the allowlist would
leave `policy` a one-field noun and would say that an ingestion bound is a
property of the project, which is the same mistake one field over.

**The set is per slot.** `capsules.nix` declares which policies each slot may
take; an assigner selects within that set or is refused. The permissive answer —
a dev host where any slot may take any policy — is a slot declaring the whole
vocabulary, which is Plan D §0's rule that permissiveness **falls out of a
declaration** rather than being the mechanism's default. `policies.nix` exports
the vocabulary's names for exactly that, so declaring it is one word per slot and
not a list that drifts.

**The record's `policy` field is written by the front end**, `capsule <slot>
policy <name>`, validated against that slot's set and bumping the generation.
This is `unit`'s shape exactly ([item 32](./032-the-sideband-channel.md),
[item 29](./029-the-record-is-front-end-written.md)): a program may not read host
state, the front end may, and the field already exists in the record as null.

**A policy is live; a profile is pinned.** The refresh rule, and here it has a
cost worth naming rather than a mechanism: the proxy renders its tinyproxy
config at start, so a policy change reaches a running capsule when its proxy
restarts. That is *already* true of editing an allowlist today — the plain file
is re-read at start and not while running — so "live" costs one proxy restart for
one slot, and the guest sees egress drop for the length of it. A tightening has
to bite, and a tightening nobody applied is not a control.

## Three decisions that could have gone the other way

**A slot's policy has a declared default; a slot's name still does not.**
[Item 28](./028-a-slot-has-no-default.md) refuses a default slot, and the
distinction is not a softening of it. A slot's *name* has no default because a
name that means nothing cannot be guessed on a human's behalf. A slot's *policy*
has one because the host operator owns it, and **absence is not a state a
perimeter may be in**: a slot whose record names no policy must run something,
and the only two candidates are the host operator's declared choice or a refusal
to start. The declared default is the one that does not strand a slot whose
assigner has not run yet — and it is the operator's declaration, not the
assigner's, so nothing about the authority split moves. What *is* refused is an
assigner naming a policy outside the slot's set.

**The front end resolves; the proxy does not read the record.** The tempting
version has the proxy unit read `assignment.json` at start and look its policy
up. That makes the perimeter a reader of the assignment record and gives a
hardened unit a reason to see host state it otherwise has no business in. The
version taken instead: the `policy` verb re-points a per-slot symlink
(`<state>/slot/<n>/allowlist`) at the declared policy's file, and the proxy unit
binds that one stable path plus the policy directory read-only. Same rule as
everywhere else here — a program does not probe for which value it should use
(item 20); the front end resolves, which is a front end's latitude (item 28), and
`perimeter/` still knows nothing but a path.

**`policies.nix` holds paths, not contents.** An allowlist stays a plain file
outside the store, which is the existing rule and the reason it can change
without a rebuild. What the declaration adds is *which* file, not what is in it.

## What this does not change

The perimeter stays host-side. The proxy stays in the capsule's namespace. The
guest still has no route to any of it, and nothing here is read out of the target
repo ([item 16](./016-target-agnostic.md)). This item moves a value between two
host-side authorities; it does not move a control toward the confined thing.

## What it will need to be checked with

The branches worth pinning are refusals a live host reaches expensively: an
assigner naming a policy outside a slot's set, a slot whose declared set is empty,
and a `policy` verb against a slot that has none declared. Those are the third
kind of check (CLAUDE.md) — the front end's own text against a substituted
declaration, the way `guardCases` now takes a fixture rather than following
`capsules.nix`. The proxy actually *using* the selected allowlist is not that
kind: it is a live-host claim, and the honest instrument for it is
`probe/netns-egress.sh` run against two slots on two policies — one host
allowlisted for `a` and denied for `b`, asserted both directions, which is the
rule that probe was written under.

## Where the build got to

| slice | state |
| --- | --- |
| the vocabulary, and each slot's declared default and set | **built**, two eval refusals watched firing |
| the allowlist moves — `perimeter/` loses its value, both call sites resolve a policy | **built**, three `capsule-host` refusals exercised |
| `collectMaxPackBytes` and `mayCollect` move | not started |
| `capsule <slot> policy <name>`, the status column, and the cases | not started |

**Nothing is switched**, so this host still runs the fleet-wide allowlist. The
switch is also what materialises the per-slot symlinks, since tmpfiles is what
creates them at each slot's declared policy.

**What the third slice has to decide**, and the precedent is `unit`'s exactly
([item 32](./032-the-sideband-channel.md)): `collectMaxPackBytes` is a build-time
literal today, baked into `capsule-collect`'s store path as `ulimit -f` blocks,
and it becomes a run-time argument the front end fills from the slot's policy —
explicit flag wins, and a direct call with neither **refuses**, because a collect
with no declared bound is the unbounded ingest the bound exists to prevent.
`mayCollect` is the same shape one field over and refuses before the door opens.

**What the fourth has to decide** is what a policy change does to a slot that is
running: the call taken is that the verb restarts that slot's proxy, so a
tightening bites without a re-assign and one slot's egress drops for the length
of a restart. It writes the record and re-points the symlink under the same
`flock` the record already takes, because a record and a symlink that disagree is
a perimeter nobody can read.
