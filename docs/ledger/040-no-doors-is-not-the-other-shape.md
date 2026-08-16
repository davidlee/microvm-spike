# NOTES item 40 — no doors is not the other shape

*State: **fixed and run**. `capsule all status` cost ten seconds a row on a
ten-slot pool, all of it one `ConnectTimeout`. `host/cli.nix`'s `door` decided
which transport reaches a capsule by asking whether any *other* capsule's relay
socket is open, and answered "none, so this is the devshell path" for a
module-path host with everything stopped, which is what a module-path host looks
like at rest. Every row then ssh'd straight at `net.guest` — an address whose
packets leave by the default route and are never answered. It now asks the
precondition the direct transport actually has, a tap in this namespace, and a
full-fleet status is **0.375 s**. The refusal that was supposed to fire instead had
never fired once.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What happened

A fleet status was unusably slow, and one row is the whole of it:

```
$ time capsule c status
…one correct row…
real    0m10.061s
user    0m0.027s
```

27 ms of work and ten seconds of waiting, on a slot that has never been created.
`statusRow` costs one ssh — deliberately, so a row is one round trip rather than
one per column. `observed` calls `door "$n" probe`, and `door` ended:

```bash
if [ -S "$sock" ]; then
  ssh_argv+=(-o "ProxyCommand=socat - UNIX-CONNECT:$sock")
  return 0
fi
doorsOpen
[ ${#doors[@]} -eq 0 ]
```

Return 0 means *go direct*. So: this capsule has no relay socket, and neither
does any other, therefore the module path is not what owns this host, therefore
`net.guest` is routable. The first two are facts and the conclusion does not
follow — every slot being stopped is the ordinary resting state of a module-path
host, and it is indistinguishable by this test from a host that has no module on
it at all.

Direct then fails the expensive way rather than the cheap one. There is no tap in
the root namespace, but there is a default route, so the SYN leaves the machine
and nothing ever comes back: `ConnectTimeout=10` (host/guest-ssh.nix), in full,
once per row.

## Why nobody noticed for so long

Three reasons, and the third is the one worth keeping.

**It looked like work.** Ten capsules, a hundred seconds, and a table that is
entirely correct at the end of it. Nothing in the output says the time went on
ten identical timeouts against an address no row mentions.

**The cost is linear in a number that had just changed.** The bug predates
[item 30](./030-a-pool-audits-what-exists.md); with two declared slots it is
twenty seconds, which reads as a slow command rather than a broken one. Declaring
a pool of ten multiplied it by five without touching the line responsible.

**The refusal this fallback exists to reach had never been reached.** `capsule
<n> ssh` on a stopped slot is the same code path, and its message has always
said the right thing:

```
no relay socket for 'c', and the module path owns this host.
```

That sentence is what `door` returning 1 prints. It could only print when some
*other* capsule was up — precisely the case where the question rarely gets asked
— so the common case, nothing running, silently took the branch that says the
module path does not own this host, and spent ten seconds proving otherwise.
The session's handover note had guessed the next finding would be *a refusal
nothing has ever triggered*. This is one, and the ladder it belongs on is
[item 1](./001-what-has-been-run.md).

## The fix

Ask the thing the direct transport actually needs:

```bash
doorsOpen
[ -e /sys/class/net/vm-capsule ]   # net.tap, interpolated
```

The devshell shape puts a tap in this namespace; the module path puts every tap
inside a capsule's own. So the tap's presence is not a proxy for which shape owns
the host — it *is* the precondition for `net.guest` being routable from here, and
a test of the precondition cannot be wrong about the case it was inferred from.

`/sys/class/net` rather than `ip link`: sysfs's net directory is per-namespace,
so it is the same answer with no fork and no `iproute2` in `runtimeInputs`.

Both live shapes keep their behaviour and gain nothing they did not have:

| | socket | tap | before | after |
|---|---|---|---|---|
| module path, slot up | yes | — | via the socket | via the socket |
| module path, at rest | no | no | direct, 10 s per row | refuse, instantly |
| devshell path | no | yes | direct | direct |
| devshell shape on a module-installed host | no | yes | direct | direct |

The last row is why this is not a check for whether the module is *installed*,
which was the first fix written and is wrong: a host can have the module and be
running the other shape, and relay units exist there whether or not anything is
using them.

## What it changed

`capsule all status`, ten slots, all stopped: **0.375 s**, against 10.06 s for a
single row before, and the output is unchanged row for row. `capsule c ssh` on a
stopped slot: a ten-second timeout that reads as a dead guest becomes the refusal
above, in 4 ms.

The refusal's second line was written for a case it can no longer only be in.
`capsules with a door: ` printed an empty list whenever nothing was up — which
is now its common case — so it says `no capsule has a door: none of them are up`
instead.

## The shape

`answers` has a stated discipline, in a comment above `statusRow`: *a dead guest
is a row of `-` and never a hang*. That was true of the output and false of the
clock, and no assertion anywhere is about how long a correct answer took.

The general one: **a fallback selected by absence tests the wrong thing whenever
absence is also the resting state of the shape it is already in.** `door` asked
"is anything else running?" to decide "which shape is this?", and the answer at
rest is the same for both. The repair is not a better inference — it is to ask
the precondition of the branch being taken, which is a fact about this host's
configuration and not about what happens to be up.

Same family as [item 39](./039-a-bind-is-not-a-traversal.md), pointed at
liveness rather than privilege: there, a declaration was checked and the access
it implied was not; here, a branch was reachable and the condition selecting it
was never true when it mattered. Both are things this repo declares twice and
checks never.

## What is not asserted

Nothing runs `door`. There is no case suite for `host/cli.nix`'s transport
selection, because both of its arms are host state — a socket that only root can
create, and a tap that only root can create — and a stubbed case has neither.
The evidence here is a measurement on this host, both before and after, plus the
table above reasoned. That is weaker than the four case suites and it is the
honest description of it: the timings are in
[probes.md](../probes.md#what-a-fleet-status-costs), and the two devshell rows
have not been re-run since the change.
