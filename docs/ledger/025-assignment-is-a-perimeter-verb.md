# NOTES item 25 — assignment is a perimeter-mutating verb

*State: open — scoped in [contract-assignment.md](../contract-assignment.md),
nothing built.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Making a target run-time state makes `assign` the verb that sets the
perimeter.** [Plan D](../plan-d-fleet.md) §6 turns the target into host-side
run-time state and has the proxy select `<dir>/<target>.txt` from the assignment
record. Both halves are right on their own. Together they say: whoever may hand
slot `d` a project may hand it a different egress allowlist, because the project
*names* the allowlist. The verb Plan D's whole argument wants cheap, frequent
and delegable is the same verb that decides what a capsule may talk to.

**Why it is invisible today, and why both reasons expire at once.** There is one
allowlist for the host (L3), and it is declared in `capsules.nix` at class 3;
and `assign` does not exist. L3 is on Plan D's fix list and `assign` is D1/D2.
The gap opens on the change that closes them.

**What the exposure is not.** Not the guest widening its own egress: the record
is host-side, the guest has no route to it and no channel to ask, and none of
that changes ([item 18](./018-git-channel-direction.md), the perimeter is
host-side). The confined thing still cannot touch its own confinement. The
exposure is one level up — *authority*, not reach. On this host the assigner is
the human who owns the host, so the two authorities are the same person and the
fusion costs nothing. On a ranch, or with doctrine driving assignment
([contract-doctrine.md](../contract-doctrine.md) Role 3, and Plan D §8's last
bullet), the assigner is a program, and a program that may name a project has
been handed the perimeter as a side effect of a convenience.

**Two things got fused that have different owners.** Which project a slot holds
is *semantics* — cheap, frequent, delegable, and the thing a fleet exists to
vary. Which egress policy it runs under is a *control* — declared, rare, and not
delegable. `target.nix` holds both today because one target made them the same
question, exactly as one capsule made a socket path look like part of a program
([item 20](./020-which-capsule-a-program-means.md)). This is that bug one
altitude further up: a value that looks intrinsic because there has only ever
been one of it.

`collectMaxPackBytes` falls on the control side of the same line and currently
sits in `target.nix` beside `commands`. It is an ingestion bound
([item 18](./018-git-channel-direction.md)), which is host policy about what may
come back, not a property of the project.

**The resolution shape**, recorded here and specified in
[contract-assignment.md](../contract-assignment.md):

- an assignment names a **profile** and a **policy** as separate fields;
- the *set* of policies a slot may take is declared per slot, host-side, and
  `assign` selects within that set or is refused;
- on a dev host that set may be "any", which is Plan D §0's permissive mode
  **falling out of a declaration** rather than being baked in — which is what §0
  asks of every mechanism here.

**And the dual, which is the same split wearing a clock.** A profile is pinned
at the assignment's generation, so an edit to a project's build semantics does
not silently change what a running capsule is doing. A policy is live, because a
*tightening* has to reach a running capsule without anyone re-assigning it. Plan
D §6.3's refresh-always had one rule for both; two owners want two rules. The
generic capability is *a declaration says whether its payload is pinned or
live*, which is one field on the payload rather than two mechanisms — the same
extension the identity payload already wanted.

**What this does not change.** The perimeter stays host-side. The proxy stays in
the host's namespace. Nothing here is read out of the target repo
([item 16](./016-target-agnostic.md)). This item is about which host-side
authority holds which host-side value, and it is a design constraint on D1's
record rather than a defect in anything running.
