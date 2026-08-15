# NOTES item 36 — a policy is selected from a declared set, never named by a project

*State: **finished — built, switched, and proven at the wire by the units
themselves**. The two claims this item was left owing both needed a running slot
and both are made: `capsule b collect` was refused by `mayCollect` under
`sealed`, and the `policy` verb's proxy-restart branch ran six times across two
slots. `a` on `build` answered `200` in the same breath as `b` on `sealed`
answered `403 Filtered` — through `capsule-proxy-a` and `capsule-proxy-b`, not a
probe's proxy — and `b` came back to `200` when it was put on `build`
([probes](../probes.md#what-the-units-own-perimeter-answered-the-first-time-one-ran)).
Running that branch found [item 41](./041-a-delegable-verb-that-ends-in-root.md):
the verb this item built to be delegable ends in a `sudo` nobody delegated. What
follows is the design as decided.*

*The vocabulary and each
slot's set are declared, all three limbs have moved out of `target.nix`, `capsule
<slot> policy <name>` selects within a slot's set, and 28 cases pin it. Switched
on this host, which is also what materialised the per-slot symlinks: `a` and `b`
both resolve `build`, and `capsule all status` has a `policy` column. The claim
the cases could not make is made — `probe/netns-egress.sh` **33/33**, stage 2b's
six included, so a selected allowlist is what a guest meets and `sealed` has
served something. **And the last claim is made**: `probe/two-capsules.sh` run 3,
fourteen assertions green, `build` and `sealed` on two guests at the same moment
with the answers swapping when the policies do (run 4, **42/42**, is that same
round re-taken once a stale assertion of the probe's own was fixed). **A declared
slot has been put on `sealed`**: `b`, record and link together, first time.
Starting that slot is what found
[item 39](./039-a-bind-is-not-a-traversal.md) — **this item's proxy unit had
never once started**, on any slot, because the allowlist it binds sat under a
directory it cannot traverse. Everything above about selection is unaffected and
none of it was where the fault was; what it corrects is the word *switched*,
which was read as *running* and is not the same claim. This is
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
| `collectMaxPackBytes` and `mayCollect` move | **built**, four `capsule-collect` refusals exercised |
| `capsule <slot> policy <name>`, the status column, and the cases | **built**, 28 cases green, two mutations watched red |
| the live claim — the same guest under two policies | **run**: `probe/netns-egress.sh` 33/33, stage 2b green ([probes](../probes.md#run-3--a-selected-policy-reaches-the-wire)) |
| two guests under two policies at once | **run**: `probe/two-capsules.sh` 40/42 then 42/42 ([probes](../probes.md#run-4--the-fix-run)) |
| a **declared slot** on `sealed` | **half-run**: `b`'s record and link, on a slot that was down — the proxy restart and the `mayCollect` refusal want it up |

**Switched.** tmpfiles created the per-slot symlinks at each slot's declared
policy, so `/var/lib/capsule/slot/{a,b}/allowlist` point at `build`'s file and
the `policy` column reads `build` for every declared slot. Nothing had to be
assigned for that: an operator's declaration is what an unassigned slot runs, and
that is the whole reason the link is tmpfiles' rather than the verb's.

## Putting a declared slot on `sealed`

The one thing two probes could not say, because both sealed a capsule of their
own making. `capsule b policy sealed`, on a slot that was down:

```
capsule b: policy sealed, generation 4
  capsule-proxy-b is not running; it will render sealed when it starts
```

`slot/b/allowlist` moved from `egress-allow.txt` to `egress-none.txt`, the record
went from `"policy": null` to `"policy": "sealed"` at generation 4, and the
status column reads `sealed` for `b` against `build` for the other nine. Both
halves under the one `flock`, link first, exactly as the cases pin them — so
what a case asserts against a sandbox is now what the host does to a real slot.

**And starting the slot found that this item's proxy unit has never run.** Its
allowlist was bound from under `stateDir`, which the proxy's uid cannot traverse,
so `capsule-proxy-b` crash-looped on `filter file: Permission denied` — on every
slot and under every policy, since before any of this was assigned.
[Item 39](./039-a-bind-is-not-a-traversal.md) is the whole of it, including why
28 cases, an eval check and two wire proofs all had to miss it. Nothing about
*selection* is wrong; what was wrong is the one path a selection is delivered on.

**Two things are still owed, and they are the same thing: the slot was down.**
The verb took the `is-active` false arm rather than restarting a proxy, which is
correct and is not the branch that needed exercising. And `capsule b collect`
refused — but on the **transport**, not on `mayCollect`:

```
no way in to capsule 'b': /run/capsule/b/ssh.sock is not a socket.
```

That refines a sentence below rather than contradicting it. `mayCollect` does
refuse before the door is *opened*; the injected `transport` fragment's own
precondition sits ahead of it, so a slot with no door never reaches the policy
that would have refused it. The order is right — a program that cannot find its
capsule should say so before it reasons about that capsule's policy — but it
means the refusal is only demonstrable on a **running** slot, which is the
opposite of what a refusal about not collecting looks like it should need.

**And it found a third face of the store-path trap.** `capsule b collect` ran a
`capsule-collect` old enough to predate this item — its usage line has no
`--policy`. `host/cli.nix`'s `program()` picks `/run/current-system/sw/bin/<prog>`
only when *that slot's* ssh socket exists, and falls back to the bare name
otherwise, which the caller's `$PATH` then resolves. On a host login that is the
system copy and the fallback is invisible; inside this checkout the devshell's
copy shadows it, and a slot being **down** is exactly the condition that selects
the shadowed one. The two known faces of this are a wrapper read instead of the
program ([item 20](./020-which-capsule-a-program-means.md)) and a stale third
copy on an interactive `PATH`; this is a *delegation by name* rather than either,
and the reason it is worth writing down is that the fallback is load-bearing —
`program()` chooses the reachable copy on purpose — so the fix is not to hard-code
a path. Ask the installed program directly when the question is what the host
would do.

**The count is part of the evidence.** Stage 2b skips when `ALLOW` holds no plain
hostname, and a skip lands the run at 27 — the number the first two runs scored —
so 33 is what says the round ran rather than passed vacuously. A probe with a
conditional round needs its total read, not just its colour.

**How the ingestion limbs moved**, on `unit`'s precedent exactly
([item 32](./032-the-sideband-channel.md)): `capsule-collect --policy <name>`,
refusing without one, resolving both limbs from a case generated out of
`policies.nix`. A **name and not a byte count**, which is the decision worth
recording — `--policy sealed` selects from what this host declared, while
`--max-pack-bytes 10G` would let any caller author a bound, and the whole item is
about who may author a control. `mayCollect` refuses before the door opens, so a
capsule that may not send anything back is not asked to build a snapshot first —
though not before the transport's own check that there *is* a door, which is why
it takes a running slot to demonstrate (above).
The front end fills the flag from the record, falling back to the slot's declared
default — the same two steps tmpfiles takes for the allowlist link, so an
unassigned slot ingests under exactly the policy its proxy is serving.

**What the verb does to a running slot** is what the fourth slice had to decide:
it restarts that slot's proxy, so a tightening bites without a re-assign and one
slot's egress drops for the length of it. It writes the record and re-points the
symlink under the same `flock`, because a record and a symlink that disagree is a
perimeter nobody can read — and the link goes **first**, since neither order is
safe for both a tightening and a widening and only that one has a failure where
nothing moved at all. That is `host/record.nix`'s `recordAlso`, a hook rather
than an argument because `recordWrite`'s trailing arguments are jq's.

## What it is checked with, and what is still owed

`policyCases` (flake.nix) is the third kind of check's fourth instance: the front
end's own text against a declaration that is not this host's — three slots
`capsules.nix` would itself refuse, so the branches are reachable without editing
the pool or writing a live record. The second seam is `host/cli.nix`'s
`moduleState`, an argument with a default, so the record lands in the sandbox and
both shipped copies stay one store path. 28 cases, and the suite was watched
going red on two mutations: `ln -sfT` weakened to `ln -sfn`, which turns a failed
re-point into a link written *inside* a directory and reported as success, and
the hook moved to after the document, which leaves a record claiming a perimeter
that was never applied.

**What the cases cannot say** is that any of it reaches the wire. That is
`probe/netns-egress.sh`'s stage 2b — the same guest, the proxy restarted under
`sealed`, the host that was allowed refused, and allowed again when the policy is
put back, because a denial after a restart could be a proxy that simply stopped
working. **Run, 33/33.** So the selection reaches the wire, and `sealed` — a
declared policy with an empty allowlist that no slot had ever been put on — has
now served something.

**And what that probe still will not say** is that two capsules differ *at the
same time*. That needs two guests, which is `probe/two-capsules.sh`'s shape and
not this one's. Selection reaching the wire and two selections coexisting are two
claims, and only the first had an instrument.

**It has one now, and it has run: 40/42, with all fourteen of these green and
the two reds a stale assertion elsewhere in the probe**
([probes](../probes.md#run-3--two-capsules-two-policies-at-the-same-moment)).
`probe/two-capsules.sh` grew a stage 2b: both capsules leave through one aggregator, `a` on `build` and `b` on
`sealed`, and the host `build` admits is asked for by both guests at the same
moment — allowed for one, refused for the other. Fourteen assertions, and three
of them are what make it evidence rather than a coincidence:

- **the swap**. Stopping both proxies, bringing `a` up on `sealed` and `b` on
  `build`, and asking again — `200`/`403` became `403`/`200`. Without it a capsule that is simply broken — a
  fabric asymmetry, an index, the order the two booted in — reads exactly like a
  capsule the perimeter refused. After it, each capsule has been allowed in one
  half and refused in the other, so neither can be dead and neither can be lucky.
- **the refusal is an HTTP refusal**. A dead proxy and a sealed one are the same
  `deny` from a status line's point of view; the claim is that the perimeter
  answered and said no.
- **both proxies still listening either side of each pair**, since a denial
  measured against a proxy that went away mid-round is a denial of nothing.

Two proxies bound to the *same address and port* in two namespaces is the same
identical addressing that makes a sibling unaddressable in that probe's stage 2,
pointed at the perimeter: in one namespace this is EADDRINUSE and there is only
ever one policy. Building it cost [item 38](./038-a-probe-that-became-a-borrower.md),
because a second probe needing an aggregator is what exposed that the first one's
was the live one.
