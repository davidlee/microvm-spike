# Probes — the evidence, and its last result

`probe/` is evidence, not scaffolding: each probe answers one design question
and is kept so the answer stays checkable. This file is **the one place a
probe's figures and verdict are recorded** — everything else links here rather
than restating a number, because a figure copied into three documents is three
figures the first time one of them is edited.

All of them need root, so they are the user's to run. `just build` shellchecks
them. How to write one is in [CLAUDE.md](../CLAUDE.md).

**`CAPSULE_KEEP=1` is what a red run wants.** A probe that makes its own state
directory removes it afterwards, and the guest console log lives *inside* it — so
by the time anybody wants a console log, the ordinary run has deleted it. Every
probe used to print the log's path on the way out regardless, which named a file
that was already gone; `two-capsules.sh` named two. The message is
`probe/harness.sh`'s `release_state` now, one verb for all six, and it says which
of the two things happened rather than assuming the good one. Set `CAPSULE_KEEP`
*before* a run you might need to read, not after.

| probe | question | run | last result |
| --- | --- | --- | --- |
| `netns.sh` | is a netns per capsule sound? | `sudo probe-netns` (`--internet` for the egress stage) | 14 assertions green, seconds. Models two capsules and a guest that already has root — no VM |
| `netns-restart.sh` | does a capsule's namespace survive being torn down and rebuilt? | `sudo probe-netns-restart` | **33/33 green**, and **30/3** against a deliberately pre-fix program. Drives the real `capsule-netns` on addressing that is nobody's capsule — no VM, no tap, no guest, seconds |
| `netns-boot.sh` | does firecracker boot with its tap inside one? | `sudo probe-netns-boot` | 9/9 green (doctrine EVD-018). The real capsule, the real image |
| `netns-egress.sh` | does the *perimeter* survive the move into one? | `sudo probe-netns-egress` | **33/33 green, run 3** — 27/27 for the perimeter, plus stage 2b's six, which is the first time a *selected* policy has reached a wire. The real capsule with the real proxy joined to its namespace; allowed **and** denied both asserted, in both rounds |
| `freshness.sh` | what does a fresh capsule cost, and which of REQ-450's five axes hold? | `sudo probe-freshness [REF]` | 22/22 green, twice (doctrine EVD-019) — figures below |
| `two-capsules.sh` | can two capsules run at once, are they independent, what does the pair cost? | `sudo probe-two-capsules [REF_A] [REF_B]` | **42/42 green, run 4** — 28/28 twice before stage 2b existed (doctrine EVD-020), then 40/42 on run 3 whose two reds were the probe's own stale assertion. Two capsules on two policies at the same moment, and the answers swap when the policies do. Figures below, and it **withdrew a figure this file never had a right to** |

Two figures here come from something that is not a probe, and both say so where
they sit. `capsule-baseline` is a lifecycle command a human runs on a capsule
they are about to work in, and it happens to produce
[the cold build](#the-cold-build) — it needs no root, and it needs the real
perimeter up, which is why it is not in `probe/`
([item 19](./ledger/019-baseline-build-and-figures.md)). The
[namespace restart timings](#what-a-namespace-units-restart-costs-before-and-after-item-37)
are a human at a terminal, and unlike the baseline that one is an **instrument
still owed**, not a decision about where a figure belongs
([item 37](./ledger/037-a-teardown-that-only-unnames.md)).

## What netns.sh established

Identical /30 and MAC in every namespace, so one guest image with no DHCP and no
boot-time step; no path from capsule A to capsule B; and `net.ipv4.ip_forward`
being per-netns means the forward control is *ours* rather than shared with
docker and tailscale. The inverted control — flip the namespace's `ip_forward`
to 1 and the guest walks straight out — is what proves the switch does the work.

Three costs it found: a guest reaches its own capsule's egress address (weak
host model, one scope down); whatever aggregates the capsules' egress forwards,
so proxy-to-proxy needs an interface-pair drop; and DNS needs
`DNSStubListenerExtra=` plus `/etc/netns/<ns>/resolv.conf`.

## What netns-boot.sh established

The VMM comes up with its tap created inside the namespace, the guest boots and
answers ssh in there, its NIC carries traffic on the namespaced tap, and the
tap, the guest and its ssh port are all unreachable from the root namespace. ssh
and git both cross a unix socket into it unprivileged. **No host config was
needed** — the boot was never systemd's question, which is what
[Plan C](./plan-c-multi-capsule.md) said otherwise until this ran.

It is the deliberate exception to the never-borrow-live-addressing rule, and its
header says why: the guest image has `net.nix` baked in, so the real capsule is
the subject. Hence its refusals — it will not start beside the devshell tap or a
running VM.

## What netns-egress.sh established

The last unverified claim in the netns shape, and the only remaining one that
was security-shaped: **the perimeter survives the move into a namespace.** 27
assertions, green on the first run. `netns.sh` had modelled the confinement with
veths and `netns-boot.sh` had booted the real guest, but neither ever had a
proxy in it — netns.sh's stage 2 reached the internet with a bare connect, and
netns-boot's namespace has no upstream at all on purpose.

What is now measured rather than reasoned:

- **The allowlist still works from inside a namespace, in both directions.** The
  real `capsule-proxy`, joined to the capsule's namespace and bound to the tap
  address, gave the guest `HTTP/1.1 200 Connection established` for an
  allowlisted host and `HTTP/1.1 403 Filtered` for one off it. The client is the
  real guest over ssh, using bash's `/dev/tcp` rather than curl — the guest's
  tool set comes from the target's flake and a probe may not assume what is in
  it.
- **Guest root cannot get out any other way, and the namespace's `ip_forward` is
  what stops it.** The route the design assumes guest root can add was added,
  and the guest still reached neither the internet nor the aggregator its own
  proxy leaves through. Flip the namespace's `ip_forward` to 1 and both work;
  flip it back and both stop.
- **The weak-host-model cost netns.sh found is fixable and is fixed.** With the
  proxy's egress veth address local to the capsule namespace, a guest packet to
  it is INPUT there and no forwarding switch touches it. An input drop on the
  tap for any destination but the tap address closes it, verified by removing
  the drop, watching the guest reach it, and putting it back.
- **The aggregator is a capsule-to-capsule path, and one interface-pair rule
  closes it.** `iifname "eg-wan*" oifname "eg-wan*" drop` plus an RFC1918 drop
  from capsule sources stops a capsule reaching its sibling *or* the host's own
  networks; both come back when the table is deleted, which is what makes the
  denial evidence.
- **Nothing outside reaches the guest**, including an aggregator holding a route
  to it and a host that will masquerade for it — the most permissive upstream
  there could be, so the denials cannot be a missing return path.

Two things it settled that were not the question:

- **The unit inventory is bigger than "one oneshot unit and two drop-ins."** A
  working perimeter under netns also needs, per capsule, a veth to an
  aggregating namespace, that namespace's own forwarding and rules, NAT and
  forwarding on the host, and the two drops above. All of it is host-side and
  none of it is in the guest.
- **DNS is per-namespace, and that is the trap to design around rather than
  discover.** Loopback is per-namespace, so the host's stub on `127.0.0.53` is
  not reachable from a capsule namespace — asserted. The probe writes
  `/etc/netns/<ns>/resolv.conf` itself and detects whether the host answers on
  the capsule-facing address; when it does not, it falls back to a public
  resolver, **which loses the host's DoT hop**, and says so. The shape it wanted
  is `DNSStubListenerExtra` on that address *and* an input allow for port 53 on
  that link, since the host firewall covers every interface including one this
  repo created.
  - **Run 1 fell back; run 2 did not.** The host module now installs both
    halves,
    so the re-run after that rebuild opened with `NOTE the host's own resolver
    answers on 10.101.0.1 — the capsule keeps its DoT chain`. That closes the
    half of the perimeter the first 27/27 could not claim.

### Run 3 — a selected policy reaches the wire

**33/33**, the six new assertions being stage 2b. This is the claim
[item 36](./ledger/036-a-policy-is-selected-not-named.md) was built on and could
not make: `policyCases` proves the front end's decisions and `capsule-host`'s
refusals, and nothing anywhere proved that the allowlist a slot *resolves to* is
the one a guest actually meets. The count is itself part of the evidence — the
round skips when `ALLOW` holds no plain hostname, and a skip lands at 27, so 33
says it ran rather than passed vacuously.

The shape is the same guest, the same host, two declared policies, and the
answer changing:

```
NOTE  allowlisted host api.anthropic.com: HTTP/1.1 200 Connection established
NOTE  under sealed, api.anthropic.com:    HTTP/1.1 403 Filtered
NOTE  build again, api.anthropic.com:     HTTP/1.1 200 Connection established
```

**Both directions, because a denial after a restart is ambiguous** — a proxy
that simply stopped working denies exactly as convincingly as a sealed
allowlist, so the round only counts if the same host comes back. It goes through
a stop and a start of the real unit rather than a probe-only shortcut, which is
also what the `policy` verb costs a running capsule.

**`sealed`'s refusal is byte-identical to an off-allowlist refusal under
`build`** — `403 Filtered` either way, the same string stage 2 gets for a host
that was never on the list. That is right rather than a weakness: an empty
allowlist means every host is off it, so there is one refusal here and not two,
and a proxy that distinguished them would be leaking which policy a capsule is
under to the confined side. It is also why the round is defined by the
*restoration* rather than by the denial's text.

**`sealed` has served something now**, for the first time: it had been a
declared policy with an empty allowlist that no slot had ever been put on.

What it does **not** show, and the gap is named in the probe rather than implied:
two capsules differing *at the same time*. That needs two guests and is
`probe/two-capsules.sh`'s shape. This proves a selection reaches the wire; it
does not prove two selections coexist.

Like `netns-boot.sh` it borrows the live tap, /30 and volume, for the same
reason: the guest image has `net.nix` in it, so the real capsule is the subject.

**Everything else it adds was the live fabric too, and that was not visible from
this run.** 10.100/16, 10.101/30, `eg-up`/`eg-rt` and the namespace `cap-egress`
are all `capsules.nix`'s, because that file was written *from this probe's map*
after the probe verified the shape — so its teardown's `ip link del eg-rt`
deletes the fleet's uplink on a module-path host
([item 38](./ledger/038-a-probe-that-became-a-borrower.md)). This run predates
the fix and was taken on a host where nothing collided at the time; the fabric is
now `probe/harness.sh`'s, on `10.110/16`, `10.111/30`, `pr-up`/`pr-rt` and
`probe-egress`, refused at eval if any of it is ever a live string again.
**Re-running this probe was therefore a regression check as well as a repeat**:
the same 33 assertions on a fabric none of which is the one they were taken on.
**Run 4 came back green** on it. The count was not captured off the terminal, so
this file records the colour and not the number — which is the weaker of the two
things a run of this probe can say, since a skipped stage 2b lands at 27 and
still reads green. Worth re-taking the total the next time it runs.

## What netns-restart.sh established

**33/33 against the shipped program, 30/3 against a pre-fix one.** The instrument
[item 37](./ledger/037-a-teardown-that-only-unnames.md) owed, and it drives the
**real** `capsule-netns` rather than a copy: the program takes every per-capsule
value from its unit's `Environment=`, deliberately, so that `systemctl cat` shows
a boundary's addressing — and that is a seam a probe can supply a whole capsule's
worth of nobody's addressing through. Same shape as `guardCases`' `tools`,
pointed at a probe instead of a build. No VM, no tap, no guest, nothing in the
root namespace, seconds to run.

**Three of the five rounds discriminate, and they are not the three you would
pick.** Against the pre-fix program:

| round | assertion | pre-fix |
| --- | --- | --- |
| 2 | the peer is gone from the aggregator, with no wait | **coin flip** — passed in two mutation runs, failed in one |
| 3 | an aborted `up` stranded no peer in the root namespace | **always red** |
| 4 | five up/down cycles back to back | **always green** |
| 4 | no peer survives the cycles | **red** |
| 5 | `down` clears a peer no namespace accounts for | **always red** |

The two that never flip are the two the race has nothing to do with. A failed
`ip link set … netns` leaves the link where it was, so the **strand** is not
timing at all; and an **orphan** has no namespace whose deletion could reap it as
a side effect, so nothing but the program can remove it. Everything else here is
the kernel's reaper being fast, which is exactly why this bug was intermittent
enough to reach production — and why round 4, the round that most resembles what
a human does, is the round that proves least.

Five up/down cycles cost **0.40–0.66 s** across runs, so `up` plus `down` is
under 130 ms.

**Three probe-design faults were paid for here**, each found by a mutation run
rather than by reading, and all three are about set-up rather than assertions:

- `|| exit 1` on a set-up step made the probe die with no report at all, at
  exactly the moment the program under test was broken.
- Tolerating a failed set-up let *residue* stand in for the plant it needed.
  Residue is a link on its way out: it satisfied "the name is taken", was reaped
  before the next line, and the control then passed for the wrong reason.
- A round that inherits the previous round's wreckage makes every later red name
  the wrong round — three of one run's six failures were downstream of one
  control that had not fired.

Together: **a probe's set-up must produce the state it needs, not inherit
something that resembles it, and must not ask the program under test to clean up
after its own failure.**

## What a namespace unit's restart costs, before and after item 37

Not a probe — a human at a terminal with no guest running. `probe/netns-restart.sh`
is the instrument that followed, and it is what corrected the paragraph below
the table.

| | gap between `Stopped` and `Starting` | result |
| --- | --- | --- |
| before | **4 s** | `Error: An interface with the same name exists in the target netns.` |
| after | **1 ms**, six consecutive restarts | `Finished` every time |

Read the "before" row as *the race can be lost even at four seconds*, not as a
threshold. The probe loses it at 4 s and wins it at 90 ms in the same session.

```
15:34:02.653471  Stopped network namespace for capsule b.
15:34:02.654490  Starting network namespace for capsule b...
15:34:02.756697  Finished network namespace for capsule b.
15:34:02.769816  Stopping network namespace for capsule b...
```

**What this does not show, and the first version of this section claimed it
did.** The reasoning recorded here was: a start 1 ms after a stop can only find
the peer's name free if `down` deleted the veth synchronously, since no kernel
reaper is that fast. `probe/netns-restart.sh`'s mutation run refuted that — the
**pre-fix** program passes five up/down cycles at ~90 ms each, and passes "the
peer is gone from the aggregator, with no wait" as well. The reaper is usually
that fast on this host, which is also why the bug was intermittent enough to
reach production.

So the six clean restarts are consistent with the fix *and* with luck, and they
are kept as a cost figure rather than as evidence. What the fix actually buys is
that the outcome no longer depends on winning that race — and the claims that
**do** discriminate are the two the race has nothing to do with: an aborted `up`
must strand no peer in the root namespace, and a `down` must clear a peer that
no namespace accounts for. Both are in the probe, and both fail against the
pre-fix program every time.

`up` costs ~100 ms and `down` ~60 ms, which is what makes six restarts fit in
three seconds — and therefore what trips systemd's `StartLimitBurst=5` in
`StartLimitIntervalUSec=10s` on the seventh. That failure is the governor, not
this bug, and it leaves a state that *looks* like it: namespace gone, unit
`failed`. `reset-failed` then `start` is the whole recovery. Nothing strayed —
even the stop whose start was refused cleaned up completely.

## Figures

Provenance matters here, because the two disk figures people reach for were
taken by different means and one of them is *not* what the probe measures.

Freshness has run twice. Run 2 is the current figure and run 1 is kept beside
it, because two samples say more about the noise than either says alone.

| figure | value | run 1 | source | note |
| --- | --- | --- | --- | --- |
| guest image closure | **12.4 GiB** since the flavour composition; 12175 MiB (11.9 GiB) before it, ~99% shared | 12175 | freshness, `nix path-info -S` on the runner; the current figure hand-measured on `/var/lib/microvms/a/current`, 2026-08-13 | under netns this is **the** image, once, however many capsules run. The two values are the same measurement on either side of one change — row below |
| the flavour composition, on top of the target's floor | **+0.5 GiB** closure, **+100.9 MiB** erofs | — | hand-measured, runner closure before/after plus the switch diff, 2026-08-13 | `agents` + `dev-facilities` ([item 31](./ledger/031-the-fragment-vocabulary.md)): `claude`, `pi`, `rg`, `fd`, `tree`, `jq`, `bubblewrap`, `helix`, `tmux`, `btop`, `nushell`. The erofs delta is what every slot shares; the closure delta is what this host stores once. **No second toolchain came with `llm-agents`** — its `claude-code` landed as `2.1.224 → 2.1.229`, a version bump, so the pin dedupes against this repo's nixpkgs rather than doubling it |
| store image, per instance | 3.0 GiB of erofs | — | hand-measured, [Plan C](./plan-c-multi-capsule.md#the-cost-that-shapes-everything-else) | the blob the closure names, and it does not dedupe. Only a cost under the N-closures mechanism. **The probe does not measure this** — it measures the closure above |
| guest kernel / initrd | 381 MiB / 25 MiB | — | same | shared |
| volume, after boot before provision | 260 MiB | 260 | freshness | allocated blocks (`du -B1`). Empty ext4 for a 32 GiB declaration — this much exists before any content does |
| volume, after provision | 296 MiB | 296 | freshness | so a provision costs **36 MiB** on disk, against a 32 MiB repository. The declared 32 GiB is sparse and is not a disk cost |
| volume, provisioned plus some ssh work | 385 MiB | — | hand-measured, [item 15](./ledger/015-things-that-only-grow.md) | same order — a pre-build capsule is ~300-400 MiB either way |
| volume, one `just web-build test` in, **untuned** | 7.4 GiB | — | hand-measured, item 15 | 6.9 GiB of it `/work/doctrine`. Taken when the capsule had no build config at all — full debuginfo, incremental cache. **Superseded**: with `guestConfig` the same workload leaves 1.1 GiB, below. Kept because the gap is the argument for the config existing |
| `/work/doctrine`, same workload, **tuned** | **1.1 GiB** | — | hand-measured, below | `debug = 0`, `incremental = false`. A **floor**, not a plateau — no discard, and `target/` accretes |
| host disk available under `/var/lib` | **166 GiB** of 1.78 TiB, **91% used** | — | hand-measured, `df /var/lib`, 2026-08-13 | `/var/lib` is on the root filesystem, `/dev/nvme0n1p2`, **ext4 — so no reflink**: a cloned volume is a real copy of the source's *allocated* blocks, which is its high-water mark and not its current usage. This row is what bounds the number of capsules, and it is the only reading of it — [Plan C](./plan-c-multi-capsule.md#disk-is-the-practical-limit)'s 180 GiB is the same disk earlier and its N table is that much optimistic |
| cold boot to ssh | 6.41 s | 6.34 | freshness | volume created, mkfs and seed all inside it |
| provision, 32 MiB of history | 1.90 s | 2.26 | freshness | the noisiest term here, ±16% |
| time to a usable fresh capsule | 8.31 s | 8.60 | freshness | boot + provision; "usable" means provisioned, not merely answering ssh — and **not interactive**. An interactive capsule is this plus setup plus a cold baseline build, both paid per fresh capsule because `/work/home` is on the volume freshness deletes. That is ~2 min, and this row is 7% of it ([the cold build](#the-cold-build)). Do not let the word widen quietly |
| warm boot to ssh | 6.34 s | 6.36 | freshness | volume already made and provisioned |
| the price of freshness | +0.07 s | −0.02 | freshness | cold minus warm **at boot**. It changed sign between runs, which is the finding: boot is free to within ~1%. The real price of freshness is the discarded cache, and that is [the cold build](#the-cold-build) — 109 s, three orders of magnitude larger than this row |
| teardown | 3.63 s | void | freshness | guest halts over ssh, then the VMM is terminated |
| git channel, both directions | ~100 MiB/s, 66.4k objects / 32 MiB | — | hand-measured, item 18 | the link is not the cost |
| ssh through the relay socket | 13 ms to banner, 60-90 ms for a whole `ssh … true` | — | hand-measured, unit path, n=3 | the socket is not the cost either. Interactive prompt at 0.56 s |
| git channel over the relay socket | 93.7 MiB/s out, 117.9 MiB/s back, 66.9k objects / 32 MiB | — | hand-measured, unit path, n=1 each way | same order as the tap did directly, so the relay costs nothing on bulk. It is `socat` on both ends and a TCP hop inside the namespace, and it still beats the disk |
| keystroke echo through the relay socket | 18-20 ms a character | — | hand-measured, pty round trip, n=7 in one session | Nagle on the relay's TCP leg: socat sets no `TCP_NODELAY` and ssh cannot set it on a socket it did not open. The first character was 1 ms and the rest clumped, which is the signature. `,nodelay` is now on the unit and **the post-fix figure is unmeasured** |

**Two figures from run 1 were the harness's, not the capsule's** (`572a303`),
and the corrections are the reason this file exists. Run 2 carries both, and
both resolved:

- Teardown at 22.68 s was `halt_guest` waiting out twenty seconds for a VMM exit
  firecracker is documented never to produce on guest poweroff, then reporting
  its own patience. It now waits for the guest to stop answering: **3.63 s**.
  Discard the 22.68 s rather than comparing anything to it.
- The runtime-freshness red was a line count against `journalctl --list-boots`,
  which prints a header. Now a pair against `-b -1` — the current boot has a
  journal, and no previous boot survives in it — because a bare "no previous
  boot" passes just as well against a journalctl that cannot run. The raw count
  rides along as a figure, and run 2 printed **2**: the header theory confirmed
  by the run after the one it explains, which is why the figure stays.

## Which of REQ-450's five axes hold

Asserted on a capsule nothing has used, so a green row means the state is absent
by construction rather than cleaned up afterwards.

| axis | holds | what is asserted |
| --- | --- | --- |
| checkout | yes | the repository exists, HEAD is unborn, the worktree is empty. This is the axis item 18's inversion bought: the base commit is an argument to a host command, so a fresh capsule has no history until one is pushed |
| repository | yes | no remote to fetch from, and no alternates pointing at a shared object store — REQ-448's "no writable shared object store" holding **by absence** rather than by permission |
| runtime | yes | the current boot has a journal, and no previous boot survives in it. Asserted as a pair, because a bare "no previous boot" passes just as well against a journalctl that cannot run |
| temporary | yes | `/work/tmp` is empty, and every cache in `target.caches` holds nothing that did not come out of the closure. It asked for *empty* until `guestConfig` began linking static config into `CARGO_HOME` — a store symlink is not a previous capsule's leftovers, and "nothing from outside the closure" is the property freshness wanted all along. **Not re-run since that change** |
| process | **not rowed** | deliberately. A capsule is a separate kernel, so no delta can falsify the reading — a permanently green row is misleading evidence rather than extra assurance (doctrine DEC-189) |

Four rowed, four green. The fifth is a deliberate absence, and the reason is
worth keeping: an assertion that cannot fail is not evidence, and a checklist
that counts it as one is worse than a checklist that admits the gap.

## What two-capsules.sh established

**28/28 green, twice**, then **40/42 on run 3** — the two reds a stale assertion
in the probe rather than anything the programs did, see *Run 3* below — and
**42/42 on run 4**, which is that assertion re-run against the construction
instead of against a memory of it. One runner
store path serving both capsules throughout, and from run 2 one set of host
programs serving both as well (see the asymmetry it found, below). The four
independences hold in every run, and the pair costs this:

| figure | run 1 | run 2 | run 3 | run 4 | note |
| --- | --- | --- | --- | --- | --- |
| A answers ssh, from launch | 6.94 s | 6.92 s | 6.90 s | 6.92 s | one namespace, cold volume — the freshness figure, reproduced beside a sibling |
| both answer ssh, from launch | 7.12 s | 7.10 s | 7.10 s | 7.12 s | the second capsule costs **0.18–0.20 s** in every run, not a second boot |
| declared guest RAM, per capsule | 16384 MiB | 8192 MiB | 6144 MiB | 6144 MiB | `target.sizes.mem`, cut twice across the four runs |
| **MemAvailable, both booted and idle** | **1488 MiB** | **1393 MiB** | **1028 MiB** | **1213 MiB** | against 32768 / 16384 / 12288 / 12288 MiB declared between them. See the withdrawal below, and the spread below that |
| both provisioned, in series | 3.51 s | 3.86 s | 3.92 s | 4.55 s | two 32 MiB histories, one after the other |
| volume, A / B | 295 / 295 MiB | 295 / 295 MiB | 298 / 299 MiB | 299 / 299 MiB | matches the single-capsule 296 MiB. Disk behaves exactly as documented |
| teardown, one down, sibling up | 3.56 s | 3.56 s | **0.51 s** | **0.51 s** | see below — the stop changed, not the pair |
| `microvm@capsule`, host-wide / per namespace | 2 / 1, 1 | 2 / 1, 1 | 2 / 1, 1 | 2 / 1, 1 | see below |

**The teardown figure moved by 7×, and it is not this probe's finding.** 3.56 s
was `halt_guest` waiting out a poll for an event firecracker does not produce;
0.51 s is the reboot-not-poweroff stop the harness has carried since. Run 3 was
the first time this probe had been taken since, and run 4 reproduces it to the
centisecond. Nothing about the pair changed — a sibling still costs the teardown
nothing, which is the claim.

**MemAvailable fell again, and again by less than the ceiling did.** 12288 MiB
declared between the two capsules against 1028 MiB actually consumed, after a
6144 cut — the third point on the line the withdrawal below draws, and the same
shape: the charge tracks what the guests *touched* at idle, not what they were
offered.

**Run 4 is the first repeat at an unchanged ceiling, and that is what it is
worth.** Runs 1–3 each cut `sizes.mem`, so every difference between them had a
declared cause and this file had no measurement of its own noise. Run 4 changed
nothing, and the figures split cleanly in two:

- **The boot timings reproduce to 0.3%** — 6.90 → 6.92 s and 7.10 → 7.12 s, and
  the second capsule's cost lands inside the same 0.18–0.20 s band it has held
  across four runs at three ceilings. The teardown is identical. These are
  measurements of one thing, taken inside one namespace, and they behave like it.
- **The host-wide readings move by a sixth.** MemAvailable went 1028 → **1213
  MiB** and the serial provision 3.92 → **4.55 s**, at an identical declaration.
  So the *memory* figure carries roughly ±200 MiB of run-to-run spread — which
  is not a fault, it is the caveat this file already states arriving as a number:
  MemAvailable is host-wide, and **this host runs other agents**.

Which is the useful half. The withdrawal below rests on a **ratio** — 12288 MiB
declared against ~1 GiB consumed — and a sixth of noise does not touch a factor
of ten. But quoting `1028 MiB` as *the* idle cost of a pair would be quoting a
sample; the pair costs **~1.0–1.2 GiB at idle**, and any figure this probe
derives from MemAvailable wants that spread carried with it. The rule
generalises to every host-wide reading here: what a probe measures inside its own
namespace is a figure, and what it reads off `/proc/meminfo` is a figure plus
whatever else this host was doing.

### Run 3 — two capsules, two policies, at the same moment

**The claim [item 36](./ledger/036-a-policy-is-selected-not-named.md) does not
make**, and the last one it owed. Run 3 of `netns-egress` put *one* guest through
two policies in turn; this puts two guests on two policies at once. Fourteen
assertions, **all fourteen green**:

| | A | B |
| --- | --- | --- |
| first half | `build` → `HTTP/1.1 200 Connection established` | `sealed` → `HTTP/1.1 403 Filtered` |
| **swapped** | `sealed` → `HTTP/1.1 403 Filtered` | `build` → `HTTP/1.1 200 Connection established` |

One host — `api.anthropic.com`, taken from the allowlist rather than spelled by
the probe — asked for by both guests at the same moment, answered differently for
each, and the answers **swap when the policies swap**. That swap is what makes it
evidence: a capsule that is simply broken reads exactly like a capsule the
perimeter refused, and after the swap each capsule has been allowed in one half
and refused in the other, so neither can be dead and neither can be lucky.

Two smaller assertions carry weight out of proportion to their size. Each refusal
is checked to be an **HTTP** refusal, because a dead proxy and a sealed one are
the same `deny` from a status line's point of view — the claim is that the
perimeter answered and said no, and `403 Filtered` is it saying so. And **both
proxies are checked to still be listening either side of each pair**, since a
denial measured against a proxy that went away mid-round is a denial of nothing.

Two proxies bound to the **same address and port** in two namespaces is stage 2's
identical addressing pointed at the perimeter: in one namespace this is
EADDRINUSE and there is only ever one policy.

**The count is part of the evidence**, as it is for netns-egress's stage 2b: the
round is skipped when the allowlist holds no plain hostname, and a skip lands
fourteen short. 42 is what says it ran rather than passed vacuously.

**The two reds are the probe, not the programs.** `capsule A collects into its
own quarantine` passed for both; `what came out of A is what went into A` failed
for both. The probe looked for `refs/capsule/<name>/<branch>` and
`capsule-collect` has fetched into `refs/capsule/<name>/heads/<branch>` since
[item 32](./ledger/032-the-sideband-channel.md) split the code half from the
state half — so the assertion has been wrong since that change and nothing
noticed, because nothing *runs* a probe. Same family as
[item 38](./ledger/038-a-probe-that-became-a-borrower.md) one level up: an
assertion written against a convention that later moved. Fixed by injecting
`quarantine.codeRefsOf` rather than spelling it a second time.

### Run 4 — the fix, run

**42/42.** Same probe, same host, the injected `codeRefsOf` in place of the
spelled convention: *what came out of A is what went into A* passes for both
capsules, and nothing else moved. It is a re-take of run 3's round rather than a
new one — the fourteen policy assertions were already green, and both halves of
the swap answered as before, `200` for `build` against `403 Filtered` for
`sealed` at the same moment and the answers exchanging when the policies did.

Its second use is the one it was not run for: **an unchanged declaration twice in
a row is this probe's first measurement of its own spread**, which is in the
table above and is worth reading before quoting any figure here.

Worth naming, because it is the only thing run 4 adds beyond a colour: **42 is
still what says it ran**. A skipped stage 2b lands at 28, which is exactly the
figure runs 1 and 2 reported as fully green, so a two-capsules run that skipped
its policy round would agree with two years of this file's history and read as a
regression to nothing. The total is the discriminator, and the reason to keep
reading it is sharper here than for netns-egress, whose skip lands on 27 and
means nothing else: this probe's vacuous total is a total this file already
records twice as a full pass.

**And the fabric move cost the host's resolver.** The run reports `no host
resolver on 10.111.0.1 — fell back to 1.1.1.1, which LOSES the host's DoT hop`.
That is correct and expected: `~/flakes`'s `DNSStubListenerExtra` names
`10.101.0.1`, the *live* capsule-facing address, and item 38 moved every probe's
fabric to `10.111.0.1`. So probes now resolve through a public resolver unless
the host config gains the second stub address. It does not weaken any assertion
here — the allowlist is matched on the name before anything resolves — but it is
a host-config edit the fix created, and it is recorded rather than defaulted to
for exactly the reason that fallback prints a NOTE.

**Run 2 is the stronger version of the withdrawal below.** The declared ceiling
was halved between the runs and the measured charge moved 95 MiB — 6% — which is
what "a ceiling, not a charge" predicts and what a per-capsule charge could not
produce. Everything else reproduced inside a tenth of a second, including the
0.18 s cost of the second capsule to three significant figures.

Provenance, since limits travel with claims: run 2 was taken on Sleipnir from
the working tree, *before* the commit that carries the one-program change — the
runner and the host programs were both built from a dirty tree, which the
probe's own output says. Same host and same target as run 1.

**A figure was withdrawn, and it is the more useful artefact.** Both this file
and doctrine's EVD-019 carried "16 GiB per capsule" as the term that binds at N.
It was never measured — it was read off `target.nix` — and it travelled as a
finding anyway, into a status doc and into this probe's own design. Measured:
firecracker does not preallocate and the guest's root is tmpfs, so **the
declaration is a ceiling on what a capsule may reach, not a charge levied at
boot**. Two idle capsules are cheap.

What replaces it is worse-behaved and honest: the binding term at N is what the
capsules *touch*, which is workload-dependent and unmeasured. Two concurrent
`cargo build`s against their ceilings is the open question — and the ceiling
still matters, because there is no balloon, so a capsule is charged its
high-water mark and never returns it. The corollary, next to doctrine's DEC-189
(a row needs a falsifying delta): **a number needs one too, and one read off a
config file has none.**

Four independences, because REQ-454 wants a candidate verified in a *separate*
capsule from the one that produced it, and a verifier sharing anything
load-bearing with its subject is not a verifier:

- **addressing** — a marker file on each volume, read back through the shared
  address from each namespace. A capsule cannot reach its sibling because it
  cannot *name* it: the address it would use is its own. That is stronger than a
  dropped route, which is a control that can be misconfigured; this has nothing
  to configure.
- **storage** — two volumes, and neither marker is visible from the other side.
- **history** — provisioned from two different base commits off one image, which
  is the transport inversion's whole premise
  ([item 17](./ledger/017-more-than-one-capsule.md): the base commit had to
  leave the closure or N capsules means N images). Each is then collected into
  its own quarantine, because attribution is the other half of REQ-454 — a
  verdict that cannot be tied to the capsule that produced it is not evidence.
- **lifecycle** — halt one, the other keeps answering.

It forced a change in the harness, and that is a finding in itself. Two capsules
on one image are both `microvm@capsule` in the process table, so the old
`pkill -f microvm@capsule` teardown would have killed the sibling *and reported
success* — it then asks "is a microvm running?" of a host that no longer has
either. A VMM is now identified by its namespace (`ip netns pids`), never by its
name. The probe reports both counts every run, so the day they agree is visible.

The asymmetry it exposed on the way past: `capsule-collect` took its capsule's
name as an argument, `capsule-provision` baked its socket path into a store
path. Two capsules therefore needed two provision programs — fine for a probe,
not fine for N, and it was the finding that made the transport a run-time
argument (`--capsule <name>`,
[item 20](./ledger/020-which-capsule-a-program-means.md)). **Run 2 is that fix
under its own probe**: one program set, `--capsule` per call, and the four
assertions that depend on it — each capsule provisioning over its own socket,
each collecting into its own quarantine — green with the 28 unchanged.

## What a capsule costs to work in

Hand-measured in the guest, not by a probe: a transient `systemd-run --scope`
with `MemoryAccounting=yes` and `MemoryMax=7G` (7, not 8 — the kernel, systemd,
sshd and the RAM-backed journal live outside the scope and inside the VM's
budget), sampling `memory.peak` / `memory.current` / `memory.events` into
`/work` every 5 s. The sampling is not incidental: the first attempt printed its
figures after the agent exited, the agent was exited with Ctrl-C, and SIGINT
killed the shell that was going to print them. **A figure whose only copy is
terminal scrollback is not a figure.**

Four runs, one each, at 4 vCPU / 8 GiB with `guestConfig` in place — so every
number here is the `debug = 0`, `incremental = false`, `jobs = 4` build.

| figure | value | note |
| --- | --- | --- |
| agent resident, no build | 344 MiB peak, ~230 MiB steady | flat: an idle agent is not a memory problem |
| `just web-build test`, warm, alone | 3980 MiB | |
| the same, agent resident | 4114 MiB | |
| the same, after `cargo clean` | **4513 MiB** | the number the declaration has to cover |
| sum of the parts vs measured together | 4324 vs 4114 MiB | they do not peak together — the agent is flat while the build spikes. Summing separate ceilings **overstates by ~5%**, which is at least the safe direction |
| pressure events | **0**, all four runs | `low/high/max/oom/oom_kill` all zero against a 7 GiB ceiling, so every peak above is a true high-water mark and not a reclaim-suppressed one |
| build duration, warm / from clean | ~35 s / ~50 s | warm crate cache both times |
| `/work/doctrine` after a build | **1.1 GiB** | against **6.9 GiB** for the same workload before `guestConfig` existed |
| `/work/.cargo` | 144 MiB | |

**8 GiB holds.** Worst measured workload is 4513 MiB plus ~230 MiB of resident
agent, leaving ~3 GiB for the guest's own overhead and for a build heavier than
this one. Not cut to 6 GiB on n = 1: the peak depends on which crates codegen
together, and memory is a ceiling rather than a charge (see the withdrawal
above), so a generous declaration costs nothing until something touches it. That
is the whole argument for declaring headroom instead of measuring it away.

**The build is a spike, not a plateau** — 0 to 4 GiB in ~25 s, back under 500
MiB within 15 s of finishing. Two capsules building *simultaneously* is
therefore still the open question the pair probe left, and it is a scheduling
question, not an arithmetic one.

**What this is not: a cold build.** The crate cache was already warm (144 MiB),
so nothing was fetched. `cargo clean` empties `target/`, not `~/.cargo`. That
figure is the next section's.

## The cold build

`capsule-baseline`, run 1 — `20260812T055327Z`, base `4662e64e`, on a volume
whose image had been deleted. Not a probe: a lifecycle command that produces a
figure ([item 19](./ledger/019-baseline-build-and-figures.md)). Its own record
is the source, and the record is on the volume — `/work/baseline/history.tsv`
plus the run's log — which is why it is copied here, since freshness deletes
volumes.

| figure | value | note |
| --- | --- | --- |
| **`just web-build test`, cold, to green** | **109 s**, exit 0 | fresh volume, empty caches, everything fetched through the proxy |
| the same, warm cache after `cargo clean` | ~50 s | previous section. **So the cold crate fetch costs ~59 s** — about as much again as the build |
| the same, fully warm | ~35 s | previous section |
| `/work/doctrine`, before / after | 121 → 1104 MiB | before is the provisioned checkout alone; after matches the 1.1 GiB tuned figure above, taken by hand |
| `/work/.cargo`, before / after | 1 → **144 MiB** | and 144 MiB is exactly what the warm runs above had. Two measurements of the crate cache, taken months and methods apart, that agree |
| `/work/.bun-cache`, before / after | 1 → 5 MiB | |
| all three, before / after | 123 → 1253 MiB | **one baseline costs ~1.1 GiB of volume** |

**The record proves its own coldness, without trusting the operator.** The
caches totalled 123 MiB before and `.cargo` alone was 144 MiB after; 144 > 123,
so the crate cache cannot have been warm at the start. That is the reason the
sizes are in the record and not only in the log: a duration is only a cold-build
figure if something in the same row says the caches were empty. The 1 MiB
readings before are `du` rounding on directories holding nothing but
`guestConfig`'s symlink — the same "nothing from outside the closure" the
freshness axis asserts.

**Time-to-interactive is ~2 minutes, and it is nearly all this.** 8.31 s to a
provisioned capsule, `capsule-inject` (unmeasured, seconds), then 109 s of
baseline. The terms come from different runs rather than one timed sequence, so
read it as an order of magnitude — but the shape is not in doubt: **the cold
build is ~93% of it**, and every other figure in this file is noise beside it.
It is paid per *fresh* capsule, because `/work/home` and the caches are on the
volume freshness deletes.

**That 93% is this target's, not the capsule's** — the next section takes the
same figure on a second target and gets 3 s, where the boot dominates instead.

One thing the run also confirmed in passing: `proxy : http://10.99.0.1:3128` at
the head of the log. The `bash -l` in `capsule-baseline` is load-bearing exactly
as [item 6](./ledger/006-proxy-env-login-shell-scope.md) says — without it
nothing would have fetched, and the failure would have looked like the network.

**It is three runs now, on two capsules, through the module path.** Runs 2 and 3
came out of the N=2 bring-up: each capsule provisioned to a *different* base
commit and baselined cold on its own fresh volume, one after the other, both
`status 0`. Read from each volume's own `history.tsv`, which is the only copy.

| run | capsule | commit | seconds | MiB before → after |
| --- | --- | --- | --- | --- |
| 1 | devshell, `20260812T055327Z` | `4662e64e` | 109 | 123 → 1253 |
| 2 | `capsule` | `ebb555fb0` | 115 | 124 → 1254 |
| 3 | `capsule-b` | `ccc6ddc64` | 104 | 124 → 1253 |

So the cold build is **109 s ± ~5%** rather than one reading, and the ~1.1 GiB
of volume it costs reproduced twice to within a MiB. Each of the three proves
its own coldness by the same arithmetic — `.cargo` after exceeds all three
caches before. What is still n = 1 is *sequential*: nothing here says what two
of these cost run at once, which is the [open](./status.md) load question and
the reason these three are the control for it.

## The cold build, on a second target

The same command on a different repo, which is what makes it worth a section:
`capsule-baseline` against panopticon (branch `second-target`,
[item 23](./ledger/023-second-target.md)), devshell path, fresh volume, base
`2c4b024`. Its own `/work/baseline/history.tsv` is the source.

| figure | value | note |
| --- | --- | --- |
| **`just check`, cold, to green** | **3 s**, exit 0 | `ruff check` then `pytest`: 327 passed, 3 skipped |
| what it fetched | 31 packages, ~27 MiB | resolved from pypi through the proxy on a new allowlist file, first try |
| interpreter fetched | **none** | `guestConfig`'s `uv.toml` set `python-downloads = "never"`; uv used the tool set's own 3.14.6 |
| all measured paths, before → after | 4 → 109 MiB | **one baseline costs ~105 MiB of volume**, against doctrine's ~1.1 GiB |
| `/work/.uv-cache`, after | 97 MiB | measured on its own — see the correction below |
| `/work/panopticon/.venv`, after | 7.8 MiB | almost all of it hardlinks into that cache |

**The interesting figure is the ratio, not the number.** 3 s against doctrine's
109 s is ~36×, and the volume 105 MiB against ~1.1 GiB is ~12×. So the claim
above that *the cold build is ~93% of time-to-interactive* is **doctrine's, not
the capsule's**: on this target the 8.31 s boot is the largest term and the
build is a rounding error on it. The largest term in time-to-interactive is
target-shaped. Nothing generic should be optimised against either number.

**One run cost a fix, and it was the guest rather than the port.** The first
attempt is in the same record — `status 127` in 1 s — and it had done everything
right up to the last step: interpreter found, 31 packages resolved, project
built, and then it could not *exec* the `ruff` it had installed, because NixOS
ships no `/lib64` loader and a pypi wheel is built for generic linux.
`vm/capsule.nix` grew `programs.nix-ld` for it, which is the one thing outside
`target.nix` and the allowlist that this port changed
([item 23](./ledger/023-second-target.md)).

**And one correction to the instrument, in the same family as the slice's
`memory.peak`.** `capsule-baseline` measured every path in a single `du -sm`,
and `du` charges a hardlinked inode to whichever argument came first. uv
hardlinks its `.venv` out of its cache, so the record read **checkout 105 MiB,
cache 4 MiB** when the trees are **8 and 97** — the checkout was being charged
for the cache's blocks. The total, 109 MiB, was right throughout: that is what
the volume actually pays, because the volume pays for an inode once.

This mattered beyond tidiness, and it is why the fix is worth its lines. The
coldness proof in the previous section is *arithmetic on the recorded split* —
cache-after must exceed all-caches-before — and with the buggy split this run
reported 4 MiB after against 4 MiB before, so **it could not have proven its own
coldness**. `sizes()` now asks each path on its own and `total()` keeps the
single invocation, so the two answer their own questions: what each tree holds,
and what the volume pays. Those may no longer sum, deliberately. doctrine never
exposed this because cargo shares no inodes between `target/` and `.cargo`,
which is the general shape of the thing — a second target is where an instrument
calibrated on one gets read against something else.

## What a capsule holds after it has built

The ratchet the pair probe predicted — no balloon, so a capsule is charged its
high-water mark and never returns it — measured for the first time, and it is
large. `just load`, reading each unit's **cgroup** rather than its process, with
both capsules **idle**, no agent running, hours after their cold baselines
above.

| figure | value | note |
| --- | --- | --- |
| `microvm@capsule`, idle after one baseline | 7844 MiB current, **7845 peak** | against a declared guest ceiling of 8192 |
| `microvm@capsule-b`, same | 6941 MiB current, **8365 peak** | *above* the declared 8192, see below |
| **`system-microvm.slice`, both capsules** | **14816 MiB current** | the answer to "what do two cost" at that moment, with nothing double-counted. Its *peak* read 16305 and **that figure is not attributable to this session** — see [the concurrent build](#two-cold-builds-at-once) for why a slice's peak is not a session's |
| `memory.events`, every cgroup | `low/high/max/oom/oom_kill` all **0** | no reclaim, so each peak is a true high-water mark |
| the capsules' own `io.pressure` | **0.00** at `avg10/60/300`, 544 µs total for a whole lifetime | and see the host-wide reading below |
| host memory available | 13.1 GiB of 60.4 | both capsules idle, other work running |

**A capsule's host charge can exceed the RAM it was given**, and `capsule-b`'s
8365 against a declared 8192 is that: the cgroup carries the guest's touched
pages *and* the host page cache for the image and volume reads the VMM did,
which is real memory the host is holding on that capsule's behalf. The
declaration bounds what the guest can address, not what the unit costs.

The instrument matters as much as the number. Per-process RSS says 6033 and 6908
MiB for the same two capsules — lower, and not comparable between them, because
it double-counts the one read-only image both have mapped (12175 MiB,
[freshness](#freshness)) while missing page cache charged to neither. PSS would
settle that and `smaps_rollup` is unreadable for another uid's process by the
human, which everything host-side here is by design
([item 11](./ledger/011-host-side-runs-as-you.md)). The cgroup has neither
problem: shared pages are charged once, the slice total is the aggregate, and
**`memory.peak` comes from the kernel, so the peak does not depend on a
sampler's interval.**

Two consequences, both of which shape the load question rather than answering
it:

- **A slice's peak is not a session's peak, and nothing in the reading says
  so.** `systemctl stop` destroys a unit's cgroup, so a unit's `memory.peak`
  resets when it restarts — but the slice above it **stays active with no
  members**, measured: `system-microvm.slice` reported `ActiveEnterTimestamp` of
  18:31, hours before the units that were in it at 01:06, with both capsules
  stopped in between and the cgroup never garbage-collected. So the slice's peak
  spans every capsule that has run since the slice went active, and re-reading
  it later re-reads the *first* session that set it. 16305 was read twice,
  sessions apart, identical to the MiB; that was the tell. `just load` now reads
  every peak at start as well as at end and marks an unmoved one as not set by
  this run.
- **A capsule that has built once holds most of its ceiling until it is
  stopped.** Freshness returns it; nothing else does. So "what N capsules cost"
  has two different answers — at peak, and afterwards — and the second one is
  the one that decides how many fit. Note what the arithmetic does *not* do:
  16305 MiB for two is not a rehabilitation of the withdrawn 16 GiB per capsule.
  Same order, wrong shape, and it was reasoned from a config file.
- **What a built capsule holds is guest RAM the VMM cannot hand back, and the
  guest's own view disagrees by 5.7 GiB.** The 7168 MiB an idle built capsule
  charges its cgroup splits into `anon` **6141 MiB**, page cache 965 MiB and 29
  MiB of slab; inside that same guest, `free -m` reports **481 MiB used**, 2383
  buff/cache and 5373 free of 7943. Neither reading is wrong. A page the guest
  has ever touched is faulted into the VMM's mapping, and firecracker has no
  balloon and no free-page reporting (CLAUDE.md), so a guest-side free is
  invisible from the host. The ratchet above *is* that gap, which is why only a
  stop closes it — and why a run whose peaks must mean something starts from
  freshly started units.
- **The concurrency figure has to be taken on fresh volumes**, with three cold
  builds as its control, and not on capsules that have already built. Measuring
  two warm builds on ratcheted units would price a state nobody starts from.

**Host-wide PSI is the wrong instrument on this host, and it says so loudly.**
`/proc/pressure/io` read `some avg10=93.6 full avg10=89.6`, sustained across
`avg300`, while the machine felt perfectly responsive — that was other agents on
the same host grepping and running a large JS harness, not the capsules: inside
their own cgroups io pressure was `0.00` and 544 µs total for their whole
lifetimes. A host-wide figure on a shared machine is not a capsule figure, which
is why `just load` reads per-unit pressure and keeps `MemAvailable` as context
rather than as evidence.

## Two cold builds at once

The load figure Plan C had owed since the withdrawn ceiling: **what two capsules
cost when both are doing the expensive thing at the same time.** Not a probe —
two `capsule-baseline` runs through the module path, on fresh volumes, both
provisioned to the *same* commit so concurrency is the only variable.
`20260812T150641Z`, both stamps in the same second because both were launched
from one `;`-separated line. The control is the three sequential cold runs
above.

| figure | `capsule` | `capsule-b` | sequential control |
| --- | --- | --- | --- |
| `just web-build test`, cold, to green | **112 s**, exit 0 | **121 s**, exit 0 | 109 / 115 / 104 |
| MiB of volume, before → after | 124 → 1253 | 124 → 1253 | 123 → 1253, 124 → 1254, 124 → 1253 |
| `memory.peak` of the unit | **7774 MiB** | **6801 MiB** | against a declared ceiling of 8192 |
| `memory.events`, every field | all **0** | all **0** | so both peaks are true high-water marks |

**Concurrency at N=2 is close to free.** The slower of the pair is 121 s against
a control whose own spread is 104–115; the pair costs ~5% at the tail and
nothing collapses. Neither unit reached its 8192 ceiling and neither was
reclaimed even once, so **RAM is not what binds at N=2** — which is what
[Plan C](./plan-c-multi-capsule.md) assumed from the disk table and had never
measured. The four-run agreement on 1253 MiB of volume, now across two capsules
and two concurrency regimes, is the stronger claim in the table: the cost of a
cold build is a disk cost, and it is stable.

**The pair's peak is a bound, not a figure: [7774, 14575] MiB.** The lower bound
is the larger unit, the upper their sum, and the truth is between because two
peaks need not have coincided in time. The slice would have settled it and could
not — its own peak had been set in an earlier session (above), which is the
finding this run produced about its instrument rather than about the capsules.
Fixed forward, not backfilled: no slice figure is quoted for this run.

**A second instrument agrees, and the ratchet is what it agrees about.**
Stopping `capsule-b` the next evening printed systemd's own accounting line for
the unit: `6.6G memory peak` over `52min` of wall clock. That is 6801 MiB read a
different way, by a different mechanism, at the end of a unit's life rather than
by sampling it — and it was still 6801 MiB *52 minutes after the build
finished*, with an idle guest in between. So the peak is held until the cgroup
is destroyed, which is exactly the ratchet above and the reason a stop is what
resets it.

**What else was running, because on this host that is part of the reading.** One
other agent actively working, noctalia's indexer visible in `iotop`, niri plus
idle terminals and Firefox. No `.vm/load.tsv` was taken, so this section claims
**nothing about cpu or io pressure** — the durations and the kernel's peaks are
the whole of it, and both are per-cgroup. The next section is where that gap
closed.

## Pressure under two concurrent cold builds

The same shape run again the next morning, and this time the pressure question
is answered: `20260813T013622Z` and `20260813T013623Z` (the **guest's clock is
UTC** and this host is AEST, so those stamps are 11:36 the same morning — a
thing worth knowing before reading any file mtime in a guest against a host
clock). Fresh volumes both sides, both `mib_before` 124, both provisioned to the
same commit `46507a9e0`, stamps one second apart from one launch line. So it is
a replication of the section above with one instrument added.

| figure | `capsule` | `capsule-b` | the run above |
| --- | --- | --- | --- |
| `just web-build test`, cold, to green | **113 s**, exit 0 | **118 s**, exit 0 | 112 / 121 |
| MiB of volume, before → after | 124 → 1254 | 124 → 1254 | 124 → 1253 |
| `memory.peak` of the unit | **7169 MiB** | **7510 MiB** | 7774 / 6801 |
| `memory.events`, every field | all **0** | all **0** | all 0 |
| cpu stall, `some` / `full` | **37.2 / 36.2 ms** | **39.2 / 37.8 ms** | not measured |
| io stall, `some` / `full` | **2.30 / 2.29 ms** | **2.96 / 2.96 ms** | not measured |

**Neither cpu nor io contention is anywhere near binding at N=2, and io is the
smaller of the two by an order of magnitude.** As a share of each capsule's own
build, cpu stall is **0.033%** on both and io stall is **0.002%**. That reverses
what [Plan C](./plan-c-multi-capsule.md)'s disk table led this repo to expect —
io was the term predicted to show first, and it is the one that barely
registers. `full` sits within a few percent of `some` in every column, so what
little stalling happened stalled everything in the cgroup at once; at these
magnitudes that is a remark about shape, not a cost.

**The stall figures are `total=` deltas, not samples, and their window is each
cgroup's whole life** — boot, the build, and about fifteen minutes of idle after
it. They are therefore an **upper bound** on what the builds themselves paid,
and the bound is what makes them usable: even if every microsecond fell inside
the build, it is 0.03%. What they cannot say is *when*, because **no sampler
ran** — these came out of the live cgroups afterwards, which was only possible
because nothing had been stopped in between. `just load` reads cpu and io
`total=` at start as well as at end now, for the same reason it reads the memory
peaks twice, so the next run gets the window as well as the integral.

**The durations replicate and the peaks do not.** 113 / 118 against 112 / 121,
with a sequential control of 109 / 115 / 104 — the concurrency claim holds and
the spread narrowed. The peaks moved the other way round between capsules (7169
/ 7510 against 7774 / 6801), which is what the ratchet predicts: a peak is
whatever that guest happened to touch, not a property of the workload, and the
pair bound is again a bound — **[7510, 14679] MiB**. The slice read 16305 MiB
peak, unchanged, still the figure an earlier session set.

**What else was running:** an interactive agent session on this host, ssh'ing
into both guests throughout the window the totals cover. The rest of the host's
load was not recorded for this run, which is a real limit on the io figure
specifically — a quiet host is the easy case for io.

## The first cold build at a 6144 ceiling

The measurement [plan-d](./plan-d-fleet.md) §0 owed once it cut `sizes.mem` from
8192 to 6144 by arithmetic: slot `a`, freshly created after the rename, fresh
volume, `20260813T080959Z`, `capsule a setup edge` resolving to commit
`c5f7ca7f2` — one command from created to green, and the first run of `setup` as
a verb rather than as its three parts. The live
`firecracker-capsule.json` reads `mem_size_mib` **6144** and `vcpu_count` 4, so
the cut is in the closure the guest booted — and one config path serves both
slots, which is why both are `microvm@capsule` in the process table.

The control is [what a capsule holds after it has built](#what-a-capsule-holds-after-it-has-built),
the same reading at the old ceiling. Both are one capsule, idle, after one cold
baseline.

| figure | 8192 ceiling | **6144 ceiling** |
| --- | --- | --- |
| `just web-build test`, cold, to green | 109 / 115 / 104 s sequential | **110 s**, exit 0 |
| MiB of volume, before → after | 124 → 1253 | 124 → **1254** |
| unit `memory.peak` | 7168 MiB | **7664 MiB** |
| `anon` | 6141 MiB | **6095 MiB** |
| page cache (`file`) | 965 MiB | 1493 MiB, of which 1491 `inactive_file` |
| slab | 29 MiB | 43 MiB |
| `memory.events`, every field | all 0 | all **0** |
| guest `free -m`, used / buff-cache / free | 481 / 2383 / 5373 of 7943 | **539 / 2325 / 3419** of 5927 |
| guest `/proc/pressure/memory` total, whole life | not read | **7.2 ms** `some`, 5.6 ms `full` |
| unit cpu stall total, whole life | not read at N=1 | 31.8 ms `some`, 31.1 ms `full` |
| unit io stall total, whole life | 544 µs | 4.4 ms both |

**Lowering the ceiling did not lower the charge, and that is the finding.**
`anon` moved 46 MiB against a 2048 MiB cut. A slot still costs ~7.5 GiB
ratcheted after one build, so **four hot slots cost what four would have cost at
8192** — ~30 GiB, not 4 × 6. §0's four-hot recommendation was per-unit peak
scaled by the ceiling, and the ceiling is not the term the peak follows.

**What `anon` 6095 of 6144 is not is a working set.** 99.2% of the guest's RAM
reads like saturation, but the same workload touched 6141 MiB when it had 8192 —
75% — so ~6.1 GiB is the *cumulative distinct pages the build ever touched*,
independent of the ceiling in both runs (n=1 each). A page the guest has once
touched is faulted into the VMM's mapping and firecracker has no balloon, so
the guest freeing it changes nothing host-side. The gap is visible in the same
row of the table: the guest reports 539 MiB used and 3419 free while its unit
holds 6095 MiB of anon.

**The guest was not squeezed, and host `memory.events` is not what says so.**
No `MemoryMax` is set on the unit, so all-zero events mean nothing was ever
*forced* to reclaim — not that anything had headroom. The guest-side readings
are what settle it: demand is unchanged from the 8192 run (539 against 481 used,
2325 against 2383 buff/cache), 7.2 ms of guest memory pressure over the whole
lifetime, no swap. The cut removed free pages the workload never asked for.

So the cut is **free but not a saving**: no wall-clock cost, no guest pressure,
3.4 GiB still free — worth keeping for the reason §0 also gave, that it lowers
the ceiling a runaway build converges on, and worth quoting for nothing else.
**A stop is still the only thing that returns memory** (freshness), which is
[item 12](./ledger/012-no-resource-ceiling.md)'s ratchet unchanged.

Two rows are weaker than they look. The page-cache comparison is **not** clean:
this reading is minutes after the build and the control is hours after, which is
exactly where `inactive_file` would differ, and 1491 of the 1493 MiB here is
inactive. And the stall totals span each cgroup's whole life rather than the
build, so they are upper bounds in the same way as
[the concurrent pair's](#pressure-under-two-concurrent-cold-builds).

**Slot `b`, created in the same sequence and never built in, is 722 MiB peak /
675 MiB anon / 31 MiB cache** — booted-idle, consistent with the ~1.5 GiB two
booted capsules cost at the old ceiling, and confirming that the ratchet is what
a build does and not what a boot does.

**`system-microvm.slice` read 16305 MiB peak again**, to the MiB, and this time
across a host rebuild, two renamed slots and two freshly created state
directories. Third identical reading, sessions apart. A slice's peak is not
attributable to any session that reads it, and nothing in the reading says so.

## The first exhibit, adopted — and what it costs to over-collect

`capsule-adopt` run against the tree it was written from
([item 34](./ledger/034-adopting-a-guest-authored-tree.md)): slot `a`'s
`refs/capsule/a/state/implementation` at `44f4d3005`, the state half of the
single collect [item 32](./ledger/032-the-sideband-channel.md) took while the
guest was still working. `--list` first, which writes nothing, then a real
layout into an empty directory. Both green, no refusal, on the in-tree copy
rather than the host's — `CAPSULE_STATE=/var/lib/capsule` against the module
path's quarantine, because the installed copy predates item 35.

| figure | value |
| --- | --- |
| entries in the state tree | 1886 — 1633 files, **253 symlinks** |
| bytes, as git counts them | 18 647 563 (18.6 MiB) |
| filesystem entries written | 2171 (directories are the difference) |
| on disk after layout | 23 MiB |
| broken symlinks after layout | **0** — every target resolves inside the root |
| gitlinks | none, so the mode class went untested by this tree |
| `code-oid` in the commit message | `3aee9dc7d`, `dirty: 1` |

The 253 symlinks are the point: they are what made *resolution within the root*
the rule rather than a `..` ban, and a real tree exercising 253 of them is the
first evidence that the rule admits the trees it has to admit. It is not
evidence the refusals fire — those are asserted against hand-built hostile trees,
by hand, in [item 34](./ledger/034-adopting-a-guest-authored-tree.md).

**And the exhibit measures its own over-collection**, which is
[item 32](./ledger/032-the-sideband-channel.md)'s open invariant — *bring back
the out-of-band state of the work the capsule was assigned, and none that is
not* — failing by declaration rather than by accident:

| slice of the exhibit | entries | bytes |
| --- | --- | --- |
| whole tree | 1886 | 18.6 MiB |
| `.doctrine/slice` (all slices) | 2127 of 2171 written | ~23 MiB of 23 |
| `.doctrine/slice/254` — the assigned unit | 17 | ~448 KiB |
| any path naming 254 | **41** | — |
| `.doctrine/dispatch` | 15 | <1 MiB |
| `.doctrine/state/slice` | holds `254` only | <1 MiB |

So **41 of 1886 entries are the unit the capsule was driving**, and the largest
declared path is the one that scales with the project's whole history: three
unrelated slices (`233`, `248`, `228`) are each larger than `254`. A unit-scoped
collect is ~40 entries against 1886 — a 45× cut in entries and ~40× in bytes at
the one choke point both `capsule-adopt` and `capsule-brief` read through.
`.doctrine/state/slice` is already narrow, but by accident of what that checkout
held rather than by declaration.

## What ten declared slots cost

[Item 30](./ledger/030-a-pool-audits-what-exists.md) left two things measurable
and unmeasured before the pool could be declared: what ten declarations cost at
eval and switch, and whether ten idle ones cost anything at rest. This is the
first half. It is a *host-side eval* figure, taken here rather than on a rebuild,
because `hostModuleUnits` evaluates the whole module — assertions, unit graph,
`serviceConfig` strings and every program on `environment.systemPackages` — which
is the same evaluation a switch does and none of the build a switch does.

Both runs are `nix eval --no-eval-cache` of `hostModuleUnits.drvPath` with
`NIX_SHOW_STATS`, on one checkout differing only in `capsules.nix`'s `declared`.

| counter | 2 slots | 10 slots | change |
| --- | --- | --- | --- |
| thunks forced | 4 366 084 | 4 495 452 | **+3.0%** |
| function calls | 2 684 244 | 2 783 020 | **+3.7%** |
| primop calls | 1 356 785 | 1 406 097 | **+3.6%** |
| heap allocated | 540.4 MB | 549.7 MB | **+1.7%** |
| `cpuTime` | 1.606 s | 1.578 s | — |

**Eight extra slots are 3% of an eval that is 97% not about slots**, which is the
finding: the module's cost is dominated by the fixed part — the guest image's
config, the programs, nixpkgs itself — and the per-slot part is five units and an
uplink /30. `cpuTime` came out *lower* at ten, which is the honest way of saying
wall clock cannot resolve a 3% arithmetic difference at this scale; the counters
can, and are deterministic. Three wall-clock runs each spanned 1.66–1.72 s at two
and 1.69–1.79 s at ten, i.e. overlapping.

### At rest, after the switch

The second half, and the reason it was worth measuring rather than deriving:
**the arithmetic predicted from this repo's own units was wrong by 4× on the
count that matters.** Taken on this host either side of the switch, with slots
`a` and `b` running throughout and nothing else changed.

| figure | 2 slots | 10 slots | change |
| --- | --- | --- | --- |
| systemd unit **files** | 398 | 422 | +24 = **3 per slot** |
| **loaded** unit instances | 517 | 589 | +72 = **9 per slot** |
| PID 1 `MemoryCurrent` | 88 068 096 | 88 072 192 | **+4096 B — one page** |
| named network namespaces | 3 | 3 | — |
| taps, volumes, VMMs | — | — | unchanged |

**Three unit files per slot and nine loaded instances**, because six of the nine
are microvm.nix's templates instantiated per declared instance —
`microvm@`, `microvm-tap-interfaces@`, `microvm-set-booted@`, and the three that
are inert under firecracker anyway (`microvm-macvtap-interfaces@`,
`microvm-pci-devices@`, `microvm-virtiofsd@`). A template is one *file* whatever
its instance count, which is why the two rows move at different rates. So the
pool's unit cost is mostly upstream's and not this repo's, and the earlier
"five per slot, 50 in total" figure — read off `just units`, which lists what the
module *generates* — undercounted what systemd actually loads.

**One page of PID 1 for seventy-two units** is the at-rest answer, and the rest of
the answer is the rows that did not move: eight declared slots exist as names, an
index and a unit definition each, with no namespace, tap, volume or VMM anywhere.
Host-wide `free` moved 160 MiB across the switch and **none of that is
attributable** — this host runs other agents, so nothing host-wide is a capsule
figure. PID 1's own RSS is the measurement that is.

**The guard reports `2 of 10 declared`**, and both running slots survived the
switch untouched: same VMM pids either side, no restart, no guest disturbed. That
is item 30's degradation reading correctly at a size it had never been asked
about — eight slots absent is a smaller fleet, not a refusal.

## The same exhibit, scoped — what the prediction was worth

The narrowing built ([item 32](./ledger/032-the-sideband-channel.md)), against
the same slot, the same guest and the same code commit, on the module path after
a switch. `capsule a collect` with the record's `unit: 254` filling the hole in
`statePaths`, then `capsule a adopt` into an empty directory. Both green, no
refusal. The predicted figure was "~40 entries against 1886".

| figure | unscoped | scoped | ratio |
| --- | --- | --- | --- |
| entries in the state tree | 1886 | **36** | 52× |
| bytes, as git counts them | 18 646 642 | **511 275** | 36× |
| filesystem entries after layout | 2171 | **46** | 47× |
| on disk after layout | 23 MiB | **628 KiB** | 37× |
| symlinks | 253 | **1** | — |
| broken symlinks | 0 | **0** | — |
| `capsule-collect` wall clock | 0.48 s (warm) | **0.227 s** | — |
| `capsule-adopt` wall clock | — | **0.043 s** | — |

Three things beyond the ratio, and each is a claim that could have gone the other
way.

**The one surviving symlink is the load-bearing one.**
`.doctrine/slice/254/phases -> ../../state/slice/254/phases` is what made
*resolution within the extraction root* the rule instead of a `..` ban, and it
still resolves after scoping — because the *other* declared path is what its
target lives under, so narrowing both together keeps the pair whole. Narrowing
either alone would have left a broken link and no error. The 252 that went are
doctrine's title-slug aliases for other units, which sit one directory above the
hole and are therefore out of scope by construction rather than by a rule about
symlinks.

**The chain is intact across the change.** The scoped commit's parent is
`933d99234`, the broad exhibit, so the over-collected tree is still reachable and
the narrowing reads as an event in the capsule's provenance rather than as a
rewrite of it. Nothing was deleted to get this figure.

**36 rather than the predicted ~41.** The five are the title-slug alias for 254
itself, which the earlier count reached by grepping for the string and the scoped
collect cannot reach at all, plus the untracked-but-not-ignored files this run
did not have. The prediction was made by grep over a tree; the difference is the
distance between *paths that mention the unit* and *paths under the unit*, and it
is the smaller of the two by design — a slug alias is a convenience of the
project's, not evidence of a run.

**Both host-side refusals fired for the first time outside a build sandbox**, on
the live pair: `capsule b collect` refused because `b`'s record carries no unit,
naming both remedies, and `capsule b collect --unit ..` refused on the token
bound. Neither reached the guest.

## What the sideband arc costs, end to end

The first run of items 33, 34 and 35 against live capsules, on the module path
with the host switched to the checkout that built them. Slot `a` holds the
finished SL-254 work; slot `b` is the audit capsule, empty. Every figure below is
n=1 and none of them is a bottleneck — the arc is cheaper than the ssh handshakes
in it, which is the useful shape rather than any single number.

| step | command | wall | what it moved |
| --- | --- | --- | --- |
| provision, plain | `just provision b audit/SL-254` | **2.38 s** | push + `doctrine boot` — the first run of `capsule-refresh` inside a provision |
| refresh, standalone | `just refresh b` | **0.22 s** | `Unchanged` — idempotent on a checkout already booted |
| collect, second ever | `just collect a` | **0.48 s** | `44f4d3005..933d99234`, 1885 files / 18.6 MB of state |
| fetch | `just fetch a` | **0.14 s** | both refs, quarantine → `~/dev/doctrine` |
| provision + brief + refresh | `just provision b <oid> --state a --force` | **1.14 s** | push, 1884 files laid into `b`, then `doctrine boot` |

**A second collect is nearly free, and that is the object store rather than the
program.** 0.48 s for a state half of the same size as the first, because the
1885 blobs are already in the quarantine and only the new commit and tree cross
the wire. The quarantine holds **3 packs / 42.33 MiB** for two state commits and
one code branch. The code half did not move between the two collects, so this
prices *re-collecting state that has barely changed*, which is the case a
long-running capsule generates most of.

**The three-step provision is one motion.** `--state` pushed the code, laid
capsule `a`'s collected `implementation` state into `b`'s checkout, and
regenerated `b`'s derived state, in 1.14 s — with 2127 entries under
`.doctrine/slice` and 2833 symlinks present in `b` afterwards, and no `.capsule/`,
which is item 35's drop-at-layout doing its job.

**A repeat brief into a destination that already holds every object is 0.63 s**,
so most of that 1.14 s was not the state transfer. There is no *colder* case to
measure than the first one: a brief refuses unless the destination is at the
state's `code-oid`, so the destination always holds the code history, and what
varies is only whether it has seen a `capsule state:` commit before. `b` had not,
which is why the pair above is the interesting one — cold and warm, 1.14 s and
0.63 s, for the same 18.6 MB.

**And a brief carried nothing of the other agent's *tracked* work, by
construction.** `b`'s `git status --porcelain` is **empty** after the brief, and
`capsule-brief` said so itself: `differs from its HEAD in 0 paths`. Slot `a` is
dirty — one modified tracked file, `skills-lock.json` — and that edit exists in
the exhibit only as `.capsule/dirty.diff`, which a brief drops. So for doctrine
the message's gloss (*that difference is the other agent's uncommitted work*)
describes a case this target does not produce: every declared `statePath` is
gitignored, so the state tree and HEAD cannot differ unless a project declares a
path holding tracked content. Not a defect — `dirty.diff` is dropped for the
reason item 35 gives, and the count is truthful — but **an audit capsule reading
a brief is reading the runtime tier, not the other agent's working copy**, and
nothing in the arc says so out loud.

Two refusals fired on the way, both correctly and for the reason they name. The
first `--state` provision was rejected non-fast-forward — `b` was at
`audit/SL-254`'s tip and the code-oid is behind it — and named both causes (a
dirty guest worktree, or discarding guest commits) before suggesting `--force`.
`--force` is right here only because `b` is a scratch audit slot; the ordering
that refusal enforces is the whole reason collect precedes fetch precedes
provision.

## What freshness.sh explicitly does not measure

The **cold build**. The namespace has no upstream at all, so nothing in the
guest can fetch a crate, and the first `cargo build` on a fresh volume is the
largest cost freshness actually imposes. Measuring it *inside the probe* still
needs the proxy joined to the namespace, i.e. the host module — but measuring it
at all needed only a fresh volume on the devshell path, and `capsule-baseline`
has now done that: **109 s**, above. So freshness's price is no longer "asserted
but not priced"; the probe's own 22 assertions simply are not where the price
comes from, and the two should not be conflated.

## What a fleet status costs

Not a probe — `time` around the front end on this host, before and after
[item 40](./ledger/040-no-doors-is-not-the-other-shape.md). Kept because the
figure *is* the finding: a status row was 27 ms of work behind ten seconds of
one `ConnectTimeout`, and that was invisible in output that was correct.

| | before | after |
| --- | --- | --- |
| `capsule c status` (one slot, never created) | 10.061 s | — |
| `capsule all status` (ten slots, all stopped) | ~10 s × 10 | **0.375 s** |
| `capsule c ssh true` (stopped slot) | 10 s, then a timeout error | **0.004 s**, a refusal |

The ten-row before-figure is the user's observation of the live program and one
timed row, not a timed fleet run; the after-figure is measured. Everything but
the ssh is the 0.375 s — ten rows of `systemctl show`, the record, the
quarantine's refs and the guard's last journal line — so the per-row cost of
everything this table is about is under 40 ms.

Both arms of `door` are host state, so no case suite reaches this: the fix is
evidenced by these timings and by the output being unchanged row for row, and
the two devshell rows of item 40's table are reasoned rather than re-run.

## Still unproven

- ~~**Egress under netns.**~~ Proven: `probe-netns-egress`, above. ~~What is
  *not* proven is the same perimeter assembled out of systemd units rather than
  out of a probe's `ip` and `nft` commands — the shape is settled, the wiring is
  not.~~ The units are wired (`host/netns.nix`, `host/services.nix`) and have run
  at N=1 and N=2 on this host, and the guard has held two namespaces across a
  pool widened to ten.
- ~~**Two policies at once.**~~ Proven: `probe-two-capsules` run 3, above.
  `netns-egress` run 3 had put one guest through two policies in sequence
  (33/33); this puts `build` and `sealed` on two guests at the same moment,
  answers the same host `200` for one and `403` for the other, and **swaps them**
  so neither capsule can be merely dead. Fourteen assertions, all green. What
  remains is that no *declared slot* has been put on `sealed` — both runs sealed
  a probe's capsule.
- ~~**DNS through the host's own chain, under netns.**~~ Proven from run 2 on,
  once the host module grew both halves — the stub on the capsule-facing address
  and the input allow for port 53 on that link. Runs 2 and 3 both open with
  `NOTE the host's own resolver answers on 10.101.0.1 — the capsule keeps its DoT
  chain`, which is the probe reporting that it did *not* need its public-resolver
  fallback. The fallback stays, because it is what makes the difference legible
  rather than silent — **and item 38 has since made it fire.** The probe fabric
  moved to `10.111.0.1` and `~/flakes` stubs `10.101.0.1`, so every probe now
  falls back to `1.1.1.1` until the host config names the second address.
  Proven once, and currently not in force: exactly what a NOTE is for.
- ~~**A namespace unit's restart, by anything that runs again.**~~ Instrumented:
  `probe/netns-restart.sh`, 33/33, above. It also **withdrew the reasoning** the
  hand-run timings were recorded under — the gap was never the assertion, and
  the two claims that discriminate turned out to be the two with no race in
  them ([item 37](./ledger/037-a-teardown-that-only-unnames.md)). What is *not*
  covered is the same teardown under a **unit**: the probe runs the program, and
  systemd's ordering, `ExecStop` semantics and start limit are not in it.
- Throughput over the unix socket. The tap did ~100 MiB/s each way.
