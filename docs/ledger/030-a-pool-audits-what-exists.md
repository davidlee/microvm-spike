# NOTES item 30 — a pool degrades by auditing what exists, not by excluding what is declared

*State: built and asserted, unswitched. The guard holds both limbs, eleven cases
pin them at build time (`just cases`), and the pool is still two slots —
`capsules.nix` grows to ten in its own change, once this has run. Reviewed once
before building, which cost the `wants` version and bought the argument against
the exclusion list.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

[Plan D](../plan-d-fleet.md) D2 declares ten slots instead of two, and it cannot
land alone: L12 is the reason `capsules.nix` still says `a` and `b`. This item is
the shape D2's other half takes, decided before either is written, because the
obvious version of it is a lever that switches the perimeter off.

## The chain, and why one slot is the whole host

Nothing in `host/services.nix` is `wantedBy` anything, so a ten-slot pool costs
nothing at rest — no namespace exists until some capsule starts. The cost arrives
all at once on the first start of *any* of them:

    microvm@x  ──wants──▶  capsule-proxy-x  ──BindsTo──▶  capsule-perimeter-guard
                                                                │ requires
                                                                ▼
                                            every declared capsule-netns-* unit

The guard `requires` every declared namespace unit and audits every declared
namespace every 10 s. So a namespace unit that will not come up fails the guard,
and the guard is on every proxy's `BindsTo`: **no capsule on the host can start,
not merely the broken one.** At N=2 that is indistinguishable from robust. At
N=10 the pool's weakest member gates the fleet.

## The obvious fix is an exception nobody clears, and it is refused

The shape that suggests itself is an exclusion list — a file naming slots the
guard should skip, so an operator drops the broken one and the other nine run.

The tempting argument against it is that its off switch is host state, and that
argument does not survive this repo's own authority model: **all of the perimeter
is trusted host state.** Root can edit the allowlist, stop the guard, rewrite the
units. Being editable by root is not what makes a control weak.

The real objection is narrower and stronger. An exclusion list is **persistent
mutable exception state whose meaning is "this declared perimeter need not
satisfy the invariant", with nothing mechanically tying the exception to the
condition that justified it.** So it has a stale transition, and it is the
ordinary one rather than an exotic one:

    slot breaks → operator excludes it → slot is repaired and comes back
      → the exclusion survives → a live, usable perimeter is no longer audited

The design below has no equivalent state to forget to clear, because reality is
the selector: whether the namespace exists *is* the condition. That also keeps
[item 28](./028-a-slot-has-no-default.md)'s line intact — resolving host state is
a front end's latitude, and the guard is the program those front ends are trusted
because of.

## The decision: one invariant, two limbs

The guard succeeds if and only if:

1. **every declared-and-present namespace passes its perimeter audit**; and
2. **every running capsule's VMM is inside its own declared namespace.**

Those are jointly what makes absence safe to ignore, which is why they are one
decision and not a decision plus a check. From them:

- **Declared and absent → not audited.** There is no namespace, so there is
  nothing to audit and — by limb two — nothing running in it. Say so in the
  output and move on.
- **Declared and present → audited exactly as now.** `ns_not_forwarding` and the
  tap drop, unchanged.
- **Present and wrong → refuse the whole host**, unchanged. Absence is capacity
  that does not exist; breakage is a breach; only the second is fleet-wide.
  Degrading that too would be the exclusion list with extra steps.
- **`requires` is dropped from the namespace units and not replaced with
  `wants`** — see below.
- **The aggregator stays `requires`.** One per host, and every capsule's egress
  leaves through it — there is no degraded version of the thing they all share.

**It is worth being precise that this is not a mode.** There is no boolean, no
override, no alternate path, and nothing that "knows" it is degraded. The guard
enforces one invariant over the resources that exist, and capacity is sometimes
less than declared capacity. A system with a degraded *mode* has a second code
path to get wrong; this has none.

## `after` alone, because `wants` is still a pull-in

The first version of this said `requires` → `wants`, and that is wrong in a way
worth recording: `Wants=` starts things. The guard is shared, so the first
capsule to start would have the guard pull in **all ten** namespace units — which
abolishes the state the whole design is about. Failure propagation would be gone
and the lifecycle coupling would remain, so "declared and absent" would be a
condition the guard itself made unreachable.

What is wanted is ordering with no pull-in at all:

    capsule x starts
      ├── requires cap-netns-x        ← the only thing that creates a namespace
      └── pulls the shared guard (proxy BindsTo)
             ├── after cap-netns-a … cap-netns-j   (orders, starts nothing)
             └── audits declared ∩ actually-present

`After=` on a unit nobody queued is a no-op, and a unit that *was* queued by its
own capsule and failed still has a completed job — so the guard is ordered behind
it and observes its absence rather than inheriting its failure. Ten idle
declarations therefore cost nothing at rest, which was the claim L12 made and the
`wants` version would have quietly falsified.

## Why limb two is load-bearing, and what it is not

`ip netns del` removes the *name*, not the namespace: a network namespace lives as
long as a process holds it. So this state is reachable —

| declared | named namespace present | guest still running in it |
| --- | --- | --- |
| yes | no | yes |

— and it is exactly where limb one's skip would be unsound. Limb two is what
excludes it: a slot whose `microvm@<name>.service` is active must have its
`MainPID` inside `cap-<name>`, so an unnamed namespace with a live guest is a
refusal rather than an absence.

**Per slot, not membership of the union.** `MainPID(microvm@x) ∈ netns(cap-x)` is
cheaper to reason about than "every VMM is somewhere in the audited set" and
catches something the union form calls healthy: `microvm@a` running in `cap-b` is
one slot's guest behind another slot's perimeter.

**Asked of systemd's identity, then the kernel's.** Which slots are running is a
question only systemd can answer — `microvm@x` is a unit name, and every VMM on
this host is `microvm@capsule` in the process table anyway (CLAUDE.md), so a
`pgrep` over command lines is the wrong instrument twice over. `ip netns pids`
then answers where that pid actually is, which is the same question
`/proc/<pid>/ns/net` against a bind-mount's inode would ask with more arithmetic.

**What it does not cover**, and this is the residual to keep: a VMM with no
active unit — orphaned from systemd's view — is outside both limbs. Its proxy
died with its unit, so it has no egress, and the aggregator it would have to
leave through is still audited; that is why this is recorded rather than fixed.
The devshell path's VMM and a probe's guest are outside it for the same reason and
are governed instead by the refusals that keep the two shapes apart —
`capsule-host` refusing while a proxy unit is active, and a probe refusing beside
a live capsule.

## Why intersection, and not every `cap-*` namespace

Enumerating namespaces by prefix is the tempting simplification and it is a live
hazard on this host: a probe's namespace is `cap-capsule`
([item 28](./028-a-slot-has-no-default.md)), deliberately not any slot's. A guard
that audited every `cap-*` would find a probe's namespace, find no
`capsule-guard` table in it, and tear the host's egress down — a probe that is
correct in itself killing the fleet beside it. Intersecting with the declared
names keeps the set closed under `capsules.nix`, which is the only place allowed
to say what a slot is.

Limb two is what states in the guard what CLAUDE.md already states in prose — a
VMM is identified by its namespace, never by its name — and it is asked per slot
for the reasons above rather than as a sweep over every VMM on the host. A sweep
would also have made a *correct* probe fatal to the fleet, since a probe's guest
is deliberately in nobody's namespace.

## The witness is the count line, and it has to change

`capsule-perimeter-guard: 2 capsule namespace(s) verified` is a constant
interpolated at build time. Under this design it must report **verified of
declared** — `8 of 10` — because a degraded mode nobody can see is the failure
this repo has already paid an evening for: everything reported health while the
drop-in had never parsed (CLAUDE.md). Legible degradation or none.

## What this does not decide

Which slot an assignment picks, and what "free" means. That is
[item 25](./025-assignment-is-a-perimeter-verb.md) and
[contract-assignment.md](../contract-assignment.md), and it belongs to the record
D1 built rather than to the audit. This item is only about a pool being
*declarable* without its weakest member holding the other nine hostage.

Two things it leaves measurable and unmeasured: what ten declarations cost at
eval and switch — indices, uplink /30s, four units each, one image shared, no
volume until first boot — and whether ten idle declarations change anything at
rest, which the chain above says is nothing and nothing has confirmed.

## What building it produced besides the guard

Both limbs are decided by branches a live host can only reach destructively —
unnaming a namespace under a running guest, or binding a VMM to the wrong one — so
the check for them is `guardCases` in `flake.nix`, eleven cases run at build time
against the real guard text with `ip`, `systemctl` and `sleep` stubbed. It is not
a second implementation: `host/guard.nix` takes `tools` as an argument, which it
has to, because `writeShellApplication` prepends `runtimeInputs` to `PATH` and a
stub prepended by a test would lose to the real `ip` every time. That seam is the
same one `transport` is, and CLAUDE.md now names it as the way to make any
host-side program testable.

Two of those cases exist because a *weaker* design passes without them: a live
guest in an unnamed namespace is limb one's unsoundness, and a VMM in another
slot's namespace is what union membership calls healthy. And the suite was
checked for the ability to fail — the skip was reverted to its pre-item-30 form
once, deliberately, to watch `a slot that never came up degrades` go red.
