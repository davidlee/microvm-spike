# NOTES item 37 — a teardown that only unnames, and the check that could not have caught it

*State: **fixed, built, switched and instrumented**. Both netns programs roll
back an aborted `up` and delete the veth peer explicitly;
`hostModulePrograms` now builds every program the module's units reference — a
gap that had let the fix ship unchecked; and `probe/netns-restart.sh` runs the
real `capsule-netns` on nobody's addressing, **33/33**, going **30/3** against a
pre-fix program. The probe also **withdrew this item's first reading of its own
evidence**: the restart timing was never the assertion, and the two claims that
actually discriminate are the two with no race in them. What is not covered is
the same teardown driven by a **unit** rather than by the program.*
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

**The timing is not the assertion, and thinking it was is the mistake this item
made for half a day.** The reasoning was that a start that soon after a stop can
only find the peer's name free if `down` deleted the veth synchronously. The
probe's mutation run refuted it: the pre-fix program passes five up/down cycles
at ~90 ms each. The reaper is usually fast enough, which is why this bug was
intermittent enough to ship. Six clean restarts are consistent with the fix and
with luck, and cannot separate them.

What separates them is the pair of claims the race has nothing to do with — the
strand and the orphan, below.

The seventh restart failed, and **not as this bug** — systemd's own start-limit
governor. Worth knowing because the wreckage it leaves *looks* like the
original: the slot's namespace gone and the unit `failed`. It is not, and
nothing strayed; even the stop whose start was refused cleaned up completely,
which is the aborted-path claim observed for free.

## What it is checked with

`probe/netns-restart.sh`, and the seam it uses was already there:
**`capsule-netns` takes every per-capsule value from its unit's `Environment=`**
— written that way so `systemctl cat` shows a boundary's addressing rather than
a store path, and that turns out to be exactly the argument a test needs. Same
shape as `host/guard.nix`'s `tools` and `host/git-channel.nix`'s `transport`,
pointed at a probe rather than at a build. The probe supplies a whole capsule's
worth of addressing that is nobody's capsule (`cprb-*`, 10.102.0.0/30), so there
is no VM, no tap, no guest and nothing in the root namespace, and it runs in
under a second.

Stubbing `ip` would have been the wrong instrument: it would assert that the fix
issues the right commands in the right order, which is the implementation and
not the behaviour. The kernel's link and namespace tables *are* the behaviour
here.

**And the probe corrected the item.** Against a deliberately pre-fix program it
scores 30/3, and which three fail is the finding
([probes](../probes.md#what-netns-restartsh-established)): the round that most
resembles what a human does — five restarts back to back — passes every time,
while the strand and the orphan fail every time. The race is the least
instrumentable part of this bug and the smallest part of it.

**Three probe-design faults were paid for building it**, each surfaced by a
mutation run and none by reading, and all three are about set-up:

- `|| exit 1` on a set-up step killed the run with **no report at all**, at
  exactly the moment the program under test was broken.
- Tolerating a failed set-up let **residue stand in for the plant**. Residue is a
  link on its way out: it satisfied "the name is taken", was reaped before the
  next line ran, and the control passed for the wrong reason.
- A round that **inherits the previous round's wreckage** makes every later red
  name the wrong round — three of one run's six failures were downstream of one
  control that had not fired.

Which is one rule from three directions: **a probe's set-up must produce the
state it needs rather than inherit something that resembles it, and must never
ask the program under test to clean up after its own failure.** It sits beside
the rule that made this probe worth writing — assert both directions, because a
denial-only test passes for the wrong reason. Both are about the same thing: a
green that was never in danger of being red.

## What is still owed

The same teardown driven by a **unit**. The probe runs the program; systemd's
ordering, its `ExecStop` semantics and its start limit are not in it — and two
of those three are what turned this bug from a failed restart into a recovery.
That is a live-host claim and probably not a probe's shape at all.
