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
| `freshness.sh` | what does a fresh capsule cost, and which of REQ-450's five axes hold? | `sudo probe-freshness [REF]` | run 1 green after two corrections — figures below |

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

Sources: the guest image and volume numbers are `probe-freshness` run 1
(`572a303`); the volume-under-load number is a hand-measured `just web-build
test` ([notes](./notes.md) item 15); the git-channel throughput is item 18.

| figure | value | note |
| --- | --- | --- |
| guest image closure | 12175 MiB (11.9 GiB), ~99% shared | one image, however many capsules run under netns |
| guest image, per instance | 3.0 GiB of erofs | only under the N-closures mechanism |
| volume, fresh | ~296 MiB | actual blocks; the declared 32 GiB is not a disk cost |
| volume, one `just web-build test` in | 7.4 GiB | 6.9 GiB of it `/work/doctrine`. A **floor**, not a plateau — no discard, and `target/` accretes |
| time to a usable fresh capsule | 8.60 s | boot + provision; "usable" means provisioned, not merely answering ssh |
| cold versus warm boot | indistinguishable | so freshness costs nothing at boot — the cost is the discarded cache, unmeasured |
| git channel, both directions | ~100 MiB/s, 66.4k objects / 32 MiB | the link is not the cost |

**Two figures from run 1 were the harness's, not the capsule's** (`572a303`), and
the corrections are the reason this file exists:

- Teardown at 22.68 s was `halt_guest` waiting out twenty seconds for a VMM exit
  firecracker is documented never to produce on guest poweroff, then reporting
  its own patience. It now waits for the guest to stop answering. **Discard the
  22.68 s** rather than comparing anything to it.
- The runtime-freshness red was a line count against `journalctl --list-boots`,
  which prints a header. Now a pair against `-b -1` — the current boot has a
  journal, and no previous boot survives in it — because a bare "no previous
  boot" passes just as well against a journalctl that cannot run. The raw count
  rides along as a figure so the next run explains the last one.

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
