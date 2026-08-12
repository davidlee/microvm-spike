# Status — where this stands, and what is next

The one place the current state lives. Read it before picking the work up cold,
and edit it when the state changes rather than adding a second account of it
somewhere. Figures belong in [probes.md](./probes.md), reasoning in
[notes.md](./notes.md); this file says what is true now and what happens next.

Last updated 2026-08-12, at `572a303`.

## Where it got to

- **The netns boot is verified.** `sudo probe-netns-boot`, 9/9 — firecracker comes
  up with its tap created inside a namespace, the guest boots and answers ssh in
  there, and the tap, the guest and its ssh port are all unreachable from the root
  namespace. ssh and git both cross a unix socket into it unprivileged, which also
  closed item 18's unmeasured `ProxyCommand`. It needed no host config: the boot
  was never systemd's question. **Nothing in the netns shape is unverified now** —
  see [probes.md](./probes.md).
- **Probes grew a shared harness.** `probe/harness.sh` carries check / observe /
  measure / report *and* the whole capsule-in-a-namespace boot, because
  `netns-boot.sh` asserts and `freshness.sh` measures the same shape. `flake.nix`'s
  `probe` builder concatenates harness + script and injects `net.nix`/`target.nix`
  values as a quoted prelude.
- **Freshness has run, once.** Green after two corrections, both of them the
  harness measuring itself rather than the capsule. 8.60 s to a usable fresh
  capsule, a cold boot indistinguishable from a warm one, one 12175 MiB image
  shared by every capsule, ~296 MiB of volume per instance — all in
  [probes.md](./probes.md), which is now the only copy.
- **Disk is the limit, not CPU.** The volume dominates the image, nothing reclaims
  it (no discard), so the planning number is the 32 GiB cap and freshness is a
  disk policy. [Plan C](./plan-c-multi-capsule.md#disk-is-the-practical-limit) has
  the N table.
- **A real workload found a real limit.** `bun install` hung with no error and no
  log line: tinyproxy at `MaxClients 32` against bun's default concurrency of 48,
  32 connections queued on a listener nothing would accept. Now 128 / Timeout 300
  (`49d2d2b`). General form in [notes](./notes.md) item 9 — a proxy turns any
  client's parallelism into a shared resource, and it fails as a hang, not a
  refusal.
- **`~/flakes` is switched**, not just edited: 9418 is out of the tap's firewall
  stanza and the `capsule-git` group is gone from the live system.

## Next, in order

1. **Cite the freshness figures where they are argued from.** [notes](./notes.md)
   items 15 and 17 and Plan C's disk section still reason from the hand-measured
   volume number and the 3.0 GiB image; probes.md now carries run 1. Link, don't
   copy.
2. `capsules.nix` — under netns it is a name list and little else.
   [Sketch](./plan-c-implementation.md#capsulesnix-sketch).
3. Host-module netns wiring: `capsule-netns@` (root oneshot, `ip netns add/del`,
   before `microvm-tap-interfaces@%i`), `NetworkNamespacePath` drop-ins on both
   units, the ssh relay unit, `host/perimeter-check.nix` rewritten around the
   namespace's own `ip_forward`. Bookkeeping against a known-good result now.

Then the rest of Plan C's
[order of work](./plan-c-multi-capsule.md#order-of-work).

## Open, and nothing should claim these closed

- **Egress under netns is unproven.** `probe-netns-boot` has no upstream in its
  namespace on purpose, so it asserts nothing about it; that needs stage 2 of
  `probe/netns.sh` plus a proxy joined to the namespace.
- **The byte/disk bound on collect.** `ulimit -f` bounds one packfile, not the
  transfer — many small objects or a delta bomb go past it. A quota or a dedicated
  filesystem for the quarantine is the host-shaped answer.
- **Non-git provisioning inputs** — uncommitted files, generated config, secrets.
  The transport exists and is host-initiated; no program uses it.
- **Quarantine retention** (doctrine has DEC-193 proposed).
- **Throughput over the unix socket.** The tap did ~100 MiB/s each way.
- **The cold build under freshness** is unmeasured and cannot be measured by that
  probe — see [probes.md](./probes.md).
- `vm --help` creates `.vm/--help/`. Every argument is a VM name. Papercut.

## Do not re-derive these

All of them cost time already. The long forms are in [notes.md](./notes.md),
[CLAUDE.md](../CLAUDE.md) and Plan C's
[traps](./plan-c-implementation.md#traps-already-paid-for).

- the forward drop does not stop cross-capsule reach
- a per-instance kernel cmdline does not buy one guest image
- `StrictHostKeyChecking=accept-new` does not fix a *changed* host key
- a denial-only network test passes for the wrong reason; assert both directions
- a probe that borrows the production addressing tests production
- sudo strips `SSH_AUTH_SOCK`, and the guest's key is `~/.ssh/id`, which ssh does
  not try by default — a root-side ssh gets `Permission denied` while ping keeps
  working
- devshell programs are store paths: an edited program is stale on `PATH` until it
  is rebuilt, and it will look like your fix did nothing
- firecracker EPERM on the tap means *no tap* (it tried to create one), not a
  wrong owner; EBUSY means a VMM outlived its guest
