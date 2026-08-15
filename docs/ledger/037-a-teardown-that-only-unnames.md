# NOTES item 37 — a teardown that only unnames, and the check that could not have caught it

*State: **fixed, built, switched and witnessed at the failure it repairs**. Both
netns programs roll back an aborted `up` and delete the veth peer explicitly,
and `hostModulePrograms` now builds every program the module's units reference —
a gap that had let the fix ship unchecked, and which the mutation test confirms
was real. On this host, six consecutive `systemctl restart capsule-netns-b` at
gaps down to **1 ms** all finished, against a pre-fix failure at a **4 s** gap
(below). What is still owed is an instrument rather than a claim: the exercise
was a human at a terminal, not a probe in the tree.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What happened

`sudo systemctl restart capsule-netns-a capsule-netns-b` on a host whose
capsules were both stopped. `a` came back. `b` did not:

```
capsule-netns[879873]: Error: An interface with the same name exists in the target netns.
capsule-netns[880041]: Cannot create namespace file "/var/run/netns/cap-b": File exists
capsule-netns[880587]: Cannot create namespace file "/var/run/netns/cap-b": File exists
```

Three messages, three different wrong impressions, and none of them names the
cause. The recovery was four `ip` commands run by hand.

## Why

`host/netns.nix`'s per-capsule `down)` deleted the namespace and nothing else.
The uplink is a veth pair — `up-<n>` inside the capsule's namespace, `cap-<n>`
inside the aggregator — and deleting a namespace does **not** synchronously
delete a link that was moved out of it. The peer in `cap-egress` is reaped by
the kernel some time after the namespace goes, so a restart that beats the
reaper runs `ip link set "$peer" netns "$egress_ns"` against a name that is
still taken. That is message one.

The aggregator's own `down)` has always got this right, five lines up the same
file, with a comment saying why: it deletes the peer *first*, then the
namespace. **The per-capsule branch never received that line.** Two teardowns,
one construction's worth of reasoning, and only one of them holding it — which
is the shape CLAUDE.md already records under "anything built at two call sites
needs one construction, not two careful ones", here as a rule stated in one
branch and absent from its sibling.

Then it compounds twice, and this is the part worth keeping:

**An aborted `up` strands more than it names.** By the time the peer move
failed, `up` had already run `ip netns add`, written
`/etc/netns/cap-b/resolv.conf`, and created the veth pair. `ip link set … netns`
leaving a link *where it was* means the peer stayed in the **root** namespace —
so the recovery's obvious command, `ip netns exec cap-egress ip link del cap-b`,
answered `Cannot find device "cap-b"` and read as *nothing to clean* over a
strand that was one namespace over.

**A unit that fails in `ExecStart` never runs `ExecStop`.** So the half-built
namespace was unreachable by `systemctl stop` — which exited 0, having done
nothing — and every subsequent `start` failed on `Cannot create namespace file`,
message two, describing a leftover of the first failure rather than the race
that caused it. A stop that succeeds without stopping anything is the worst of
the three impressions, because it is the one an operator believes.

**And the names collide.** `capLink = "cap-"` makes a capsule's namespace
`cap-b` and its aggregator-side veth `cap-b` — the same string for two kinds of
thing. `An interface with the same name exists in the target netns` is then
exactly ambiguous between them. Not changed here: renaming a link is a switch's
worth of churn for a legibility gain, and the comment now carries what the name
does not. Worth knowing before reading that message again.

## The fix

**`down` is `undo_up`, and `up` uses it as its own rollback.** One function per
program, everything `up` builds in reverse:

- the peer explicitly and first, in the aggregator *and* in the root namespace,
  because an aborted `up` can leave it in either;
- then the namespace;
- then, for a capsule, `/etc/netns/<ns>/resolv.conf` and its directory.

`up` sets `built=0`, traps `EXIT`, and sets `built=1` on its last line. An
`EXIT` trap rather than `ERR`: it also covers a kill mid-`up`, and it does not
need `errtrace` to reach into a function. Every limb is `|| true`, so the trap
cannot change the exit status the unit reports — a rollback that masks the
failure it is rolling back would be the same class of defect one layer up.

`down` calls `undo_up` **unconditionally**, not only when the namespace is
present, because a peer with no namespace is precisely the wreckage a human had
to clear by hand. The VMM refusal stays in front of it and stays guarded on the
namespace existing — that check needs a namespace to ask about.

Both programs get it. Fixing only the one that failed would rebuild the
asymmetry that caused this, pointing the other way.

## What this exposed, which is the larger half

**Nothing in `just build` had ever built the module's programs.** `capsule-netns`
and `capsule-egress-ns` are only ever an `ExecStart`; they are not flake
outputs, not in `environment.systemPackages`, and `hostModuleUnits` deliberately
does not force them — its `installed` line `seq`s an outPath *without* embedding
the string, exactly so that reading the module stays an evaluation of seconds
rather than a build. Correct for what it is for. It also means shellcheck, which
runs at **build** time, had never run on either program. The rollback above was
written, formatted, `just check`ed, `just build`ed and `just units`ed — all
green, all blind to it. `capsule-perimeter-guard` was in the same position.

So `hostModulePrograms` is the exact inversion of that rule, as a second
derivation off the same evaluation: a text file whose contents are **every
`serviceConfig` literal of every capsule unit**, which makes each store path a
build input and therefore builds it. Every serviceConfig value rather than a
hand-listed set of programs, so a program added to a unit tomorrow is checked
without this line being touched. Both derivations go through the same `checked`
wrapper, so a module whose assertions fail cannot be built past by asking for
the programs instead of the units.

The pairing is the point and it is cheap: `just units` stays an eval, `just
build` gains a build it should always have had.

**Watched going red**, per CLAUDE.md's second rule for a new check: an unused
variable added to `undo_up` fails `hostModulePrograms` on SC2034 naming the
line — and `hostModuleUnits` stays green in the same breath, which is the
demonstration that the gap was real rather than an argument that it was.

## Witnessed

Switched onto this host, then six `systemctl restart capsule-netns-b` with no
guest running. Every one finished, at gaps the pre-fix code failed at by three
orders of magnitude
([probes](../probes.md#what-a-namespace-units-restart-costs-before-and-after-item-37)).

**The timing is the assertion**, and it arrives in the stronger of the two
directions this item expected to have to assert separately: a start that soon
after a stop can only find the peer's name free if `down` deleted the veth
*synchronously*. So "the peer is gone from the aggregator in between" is not
owed as a second observation.

The seventh restart failed, and **not as this bug** — systemd's own start-limit
governor. Worth knowing because the wreckage it leaves *looks* like the
original: the slot's namespace gone and the unit `failed`. It is not, and
nothing strayed; even the stop whose start was refused cleaned up completely,
which is the aborted-path claim observed for free.

## What is still owed

An instrument, not a claim. The above is a human at a terminal reading
timestamps, so it does not run again on its own and it does not run before a
switch. `guardCases` and its siblings run a program's text against a substitute
for the one thing tying it to this host, and the one thing here is the kernel's
namespace and link tables — stubbing `ip` would assert that the fix calls the
right commands in the right order, which is the implementation and not the
behaviour. The honest instrument is a probe: bring a capsule namespace up, tear
it down, bring it up again immediately, and assert both the return and the
gap it returned across. That is `probe/netns.sh`'s shape, it needs no guest, and
it now has a figure to assert against rather than a hope.
