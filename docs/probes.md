# Probes — the evidence, and its last result

`probe/` is evidence, not scaffolding: each probe answers one design question and
is kept so the answer stays checkable. This file is **the one place a probe's
figures and verdict are recorded** — everything else links here rather than
restating a number, because a figure copied into three documents is three
figures the first time one of them is edited.

All of them need root, so they are the user's to run. `just build` shellchecks
them. How to write one is in [CLAUDE.md](../CLAUDE.md).

| probe | question | run | last result |
| --- | --- | --- | --- |
| `netns.sh` | is a netns per capsule sound? | `sudo probe-netns` (`--internet` for the egress stage) | 14 assertions green, seconds. Models two capsules and a guest that already has root — no VM |
| `netns-boot.sh` | does firecracker boot with its tap inside one? | `sudo probe-netns-boot` | 9/9 green (doctrine EVD-018). The real capsule, the real image |
| `freshness.sh` | what does a fresh capsule cost, and which of REQ-450's five axes hold? | `sudo probe-freshness [REF]` | 22/22 green, twice (doctrine EVD-019) — figures below |
| `two-capsules.sh` | can two capsules run at once, are they independent, what does the pair cost? | `sudo probe-two-capsules [REF_A] [REF_B]` | 28/28 green, run 1 (doctrine EVD-020) — figures below, and it **withdrew a figure this file never had a right to** |

One figure here comes from something that is not a probe: `capsule-baseline` is a
lifecycle command a human runs on a capsule they are about to work in, and it
happens to produce [the cold build](#the-cold-build). It needs no root, and it
needs the real perimeter up — which is why it is not in `probe/`
([notes](./notes.md) item 19).

## What netns.sh established

Identical /30 and MAC in every namespace, so one guest image with no DHCP and no
boot-time step; no path from capsule A to capsule B; and `net.ipv4.ip_forward`
being per-netns means the forward control is *ours* rather than shared with
docker and tailscale. The inverted control — flip the namespace's `ip_forward`
to 1 and the guest walks straight out — is what proves the switch does the work.

Three costs it found: a guest reaches its own capsule's egress address (weak host
model, one scope down); whatever aggregates the capsules' egress forwards, so
proxy-to-proxy needs an interface-pair drop; and DNS needs
`DNSStubListenerExtra=` plus `/etc/netns/<ns>/resolv.conf`.

## What netns-boot.sh established

The VMM comes up with its tap created inside the namespace, the guest boots and
answers ssh in there, its NIC carries traffic on the namespaced tap, and the tap,
the guest and its ssh port are all unreachable from the root namespace. ssh and
git both cross a unix socket into it unprivileged. **No host config was needed**
— the boot was never systemd's question, which is what
[Plan C](./plan-c-multi-capsule.md) said otherwise until this ran.

It is the deliberate exception to the never-borrow-live-addressing rule, and its
header says why: the guest image has `net.nix` baked in, so the real capsule is
the subject. Hence its refusals — it will not start beside the devshell tap or a
running VM.

## Figures

Provenance matters here, because the two disk figures people reach for were taken
by different means and one of them is *not* what the probe measures.

Freshness has run twice. Run 2 is the current figure and run 1 is kept beside it,
because two samples say more about the noise than either says alone.

| figure | value | run 1 | source | note |
| --- | --- | --- | --- | --- |
| guest image closure | 12175 MiB (11.9 GiB), ~99% shared | 12175 | freshness, `nix path-info -S` on the runner | under netns this is **the** image, once, however many capsules run |
| store image, per instance | 3.0 GiB of erofs | — | hand-measured, [Plan C](./plan-c-multi-capsule.md#the-cost-that-shapes-everything-else) | the blob the closure names, and it does not dedupe. Only a cost under the N-closures mechanism. **The probe does not measure this** — it measures the closure above |
| guest kernel / initrd | 381 MiB / 25 MiB | — | same | shared |
| volume, after boot before provision | 260 MiB | 260 | freshness | allocated blocks (`du -B1`). Empty ext4 for a 32 GiB declaration — this much exists before any content does |
| volume, after provision | 296 MiB | 296 | freshness | so a provision costs **36 MiB** on disk, against a 32 MiB repository. The declared 32 GiB is sparse and is not a disk cost |
| volume, provisioned plus some ssh work | 385 MiB | — | hand-measured, [notes](./notes.md) item 15 | same order — a pre-build capsule is ~300-400 MiB either way |
| volume, one `just web-build test` in, **untuned** | 7.4 GiB | — | hand-measured, item 15 | 6.9 GiB of it `/work/doctrine`. Taken when the capsule had no build config at all — full debuginfo, incremental cache. **Superseded**: with `guestConfig` the same workload leaves 1.1 GiB, below. Kept because the gap is the argument for the config existing |
| `/work/doctrine`, same workload, **tuned** | **1.1 GiB** | — | hand-measured, below | `debug = 0`, `incremental = false`. A **floor**, not a plateau — no discard, and `target/` accretes |
| cold boot to ssh | 6.41 s | 6.34 | freshness | volume created, mkfs and seed all inside it |
| provision, 32 MiB of history | 1.90 s | 2.26 | freshness | the noisiest term here, ±16% |
| time to a usable fresh capsule | 8.31 s | 8.60 | freshness | boot + provision; "usable" means provisioned, not merely answering ssh — and **not interactive**. An interactive capsule is this plus setup plus a cold baseline build, both paid per fresh capsule because `/work/home` is on the volume freshness deletes. That is ~2 min, and this row is 7% of it ([the cold build](#the-cold-build)). Do not let the word widen quietly |
| warm boot to ssh | 6.34 s | 6.36 | freshness | volume already made and provisioned |
| the price of freshness | +0.07 s | −0.02 | freshness | cold minus warm **at boot**. It changed sign between runs, which is the finding: boot is free to within ~1%. The real price of freshness is the discarded cache, and that is [the cold build](#the-cold-build) — 109 s, three orders of magnitude larger than this row |
| teardown | 3.63 s | void | freshness | guest halts over ssh, then the VMM is terminated |
| git channel, both directions | ~100 MiB/s, 66.4k objects / 32 MiB | — | hand-measured, item 18 | the link is not the cost |

**Two figures from run 1 were the harness's, not the capsule's** (`572a303`), and
the corrections are the reason this file exists. Run 2 carries both, and both
resolved:

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

**28/28 green on run 1**, one runner store path serving both capsules. The four
independences below all hold, and the pair costs this:

| figure | value | note |
| --- | --- | --- |
| A answers ssh, from launch | 6.94 s | one namespace, cold volume — the freshness figure, reproduced beside a sibling |
| both answer ssh, from launch | 7.12 s | the second capsule costs **0.18 s**, not a second boot |
| declared guest RAM, per capsule | 16384 MiB | what `target.sizes.mem` said at the time of this run |
| **MemAvailable, both booted and idle** | **1488 MiB** | against 32768 MiB declared between them. See the withdrawal below |
| both provisioned, in series | 3.51 s | two 32 MiB histories, one after the other |
| volume, A / B | 295 / 295 MiB | matches the single-capsule 296 MiB. Disk behaves exactly as documented |
| teardown, one down, sibling up | 3.56 s | matches the single-capsule 3.63 s: a sibling costs the teardown nothing |
| `microvm@capsule`, host-wide / per namespace | 2 / 1, 1 | see below |

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
capsule from the one that produced it, and a verifier sharing anything load-bearing
with its subject is not a verifier:

- **addressing** — a marker file on each volume, read back through the shared
  address from each namespace. A capsule cannot reach its sibling because it
  cannot *name* it: the address it would use is its own. That is stronger than a
  dropped route, which is a control that can be misconfigured; this has nothing
  to configure.
- **storage** — two volumes, and neither marker is visible from the other side.
- **history** — provisioned from two different base commits off one image, which
  is the transport inversion's whole premise ([notes](./notes.md) item 17: the
  base commit had to leave the closure or N capsules means N images). Each is
  then collected into its own quarantine, because attribution is the other half
  of REQ-454 — a verdict that cannot be tied to the capsule that produced it is
  not evidence.
- **lifecycle** — halt one, the other keeps answering.

It forced a change in the harness, and that is a finding in itself. Two capsules
on one image are both `microvm@capsule` in the process table, so the old
`pkill -f microvm@capsule` teardown would have killed the sibling *and reported
success* — it then asks "is a microvm running?" of a host that no longer has
either. A VMM is now identified by its namespace (`ip netns pids`), never by its
name. The probe reports both counts every run, so the day they agree is visible.

The asymmetry it exposes on the way past: `capsule-collect` takes its capsule's
name as an argument, `capsule-provision` bakes its socket path into a store path.
Two capsules therefore need two provision programs. Fine for a probe, not fine
for N.

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

**The build is a spike, not a plateau** — 0 to 4 GiB in ~25 s, back under 500 MiB
within 15 s of finishing. Two capsules building *simultaneously* is therefore
still the open question the pair probe left, and it is a scheduling question, not
an arithmetic one.

**What this is not: a cold build.** The crate cache was already warm (144 MiB),
so nothing was fetched. `cargo clean` empties `target/`, not `~/.cargo`. That
figure is the next section's.

## The cold build

`capsule-baseline`, run 1 — `20260812T055327Z`, base `4662e64e`, on a volume
whose image had been deleted. Not a probe: a lifecycle command that produces a
figure ([notes](./notes.md) item 19). Its own record is the source, and the
record is on the volume — `/work/baseline/history.tsv` plus the run's log — which
is why it is copied here, since freshness deletes volumes.

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

One thing the run also confirmed in passing: `proxy : http://10.99.0.1:3128` at
the head of the log. The `bash -l` in `capsule-baseline` is load-bearing exactly
as [notes](./notes.md) item 6 says — without it nothing would have fetched, and
the failure would have looked like the network.

## What freshness.sh explicitly does not measure

The **cold build**. The namespace has no upstream at all, so nothing in the guest
can fetch a crate, and the first `cargo build` on a fresh volume is the largest
cost freshness actually imposes. Measuring it *inside the probe* still needs the
proxy joined to the namespace, i.e. the host module — but measuring it at all
needed only a fresh volume on the devshell path, and `capsule-baseline` has now
done that: **109 s**, above. So freshness's price is no longer "asserted but not
priced"; the probe's own 22 assertions simply are not where the price comes from,
and the two should not be conflated.

## Still unproven

- **Egress under netns.** `probe-netns-boot` has no upstream in its namespace on
  purpose, so it asserts nothing about it. Needs stage 2 of `probe/netns.sh` plus
  a proxy joined to the namespace.
- Throughput over the unix socket. The tap did ~100 MiB/s each way.
