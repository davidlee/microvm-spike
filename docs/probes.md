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
| `two-capsules.sh` | can two capsules run at once, are they independent, what does the pair cost? | `sudo probe-two-capsules [REF_A] [REF_B]` | **written, not yet run** (doctrine IMP-426 P1b) |

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
| volume, one `just web-build test` in | 7.4 GiB | — | hand-measured, item 15 | 6.9 GiB of it `/work/doctrine`. A **floor**, not a plateau — no discard, and `target/` accretes |
| cold boot to ssh | 6.41 s | 6.34 | freshness | volume created, mkfs and seed all inside it |
| provision, 32 MiB of history | 1.90 s | 2.26 | freshness | the noisiest term here, ±16% |
| time to a usable fresh capsule | 8.31 s | 8.60 | freshness | boot + provision; "usable" means provisioned, not merely answering ssh |
| warm boot to ssh | 6.34 s | 6.36 | freshness | volume already made and provisioned |
| the price of freshness | +0.07 s | −0.02 | freshness | cold minus warm. **It changed sign between runs**, which is the finding: freshness is free at boot to within ~1%, and its cost is the discarded cache, unmeasured |
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
| temporary | yes | `/work/tmp` is empty, and every cache in `target.caches` is empty on a fresh volume |
| process | **not rowed** | deliberately. A capsule is a separate kernel, so no delta can falsify the reading — a permanently green row is misleading evidence rather than extra assurance (doctrine DEC-189) |

Four rowed, four green. The fifth is a deliberate absence, and the reason is
worth keeping: an assertion that cannot fail is not evidence, and a checklist
that counts it as one is worse than a checklist that admits the gap.

## What two-capsules.sh asks

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

## What freshness.sh explicitly does not measure

The **cold build**. The namespace has no upstream at all, so nothing in the guest
can fetch a crate, and the first `cargo build` on a fresh volume is the largest
cost freshness actually imposes. Measuring it needs the proxy joined to the
namespace, i.e. the host module. Recorded as not-measured rather than estimated:
the discarded cache is asserted, its price is not.

## Still unproven

- **Egress under netns.** `probe-netns-boot` has no upstream in its namespace on
  purpose, so it asserts nothing about it. Needs stage 2 of `probe/netns.sh` plus
  a proxy joined to the namespace.
- Throughput over the unix socket. The tap did ~100 MiB/s each way.
