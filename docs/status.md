# Status — where this stands, and what is next

The one place the current state lives. Read it before picking the work up cold,
and edit it when the state changes rather than adding a second account of it
somewhere. Figures belong in [probes.md](./probes.md), reasoning in
[notes.md](./notes.md); this file says what is true now and what happens next.

Last updated 2026-08-12, after the pair probe's first run and the static-config
change.

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
- **Freshness has run twice, 22/22 both times.** Run 1 needed two corrections,
  both of them the harness measuring itself rather than the capsule; run 2 is
  clean and carries a valid teardown. 8.31 s to a usable fresh capsule, a cold
  boot indistinguishable from a warm one — the difference *changed sign* between
  runs, which is the strongest form that claim can take at n = 2 — one 12175 MiB
  image shared by every capsule, and ~296 MiB of volume per instance of which
  260 MiB is empty filesystem. All in [probes.md](./probes.md), the only copy.
- **Two capsules run at once, 28/28.** One runner store path, two namespaces, two
  volumes, two base commits; all four independences hold and the second capsule
  costs 0.18 s of boot. Figures in [probes.md](./probes.md).
- **It withdrew a number this repo had been quoting.** "16 GiB per capsule is
  what binds at N" was read off `target.nix`, never measured, and travelled as a
  finding into three documents and into that probe's own design. Measured: the
  declaration is a **ceiling**, not a charge — two booted capsules cost ~1.5 GiB
  between them. What binds at N is what capsules *touch*, which is unmeasured.
  Struck in place in [notes](./notes.md) item 12, because the way it spread is
  the more useful artefact.
- **A capsule is 4 vCPU / 8 GiB now**, down from 8/16 (`target.sizes`). Not a
  consequence of the correction — it is the interactive-capsule target, and the
  correction cuts the other way — but the ceiling is what a runaway build
  converges on, so it is the number that bounds one.
- **`capsule-inject` exists** — the non-git half of provisioning, host-initiated
  over the same ssh channel, as the human. `setup.nix` declares what leaves this
  host; the program knows no filename, format or key name. Two payloads: the
  token whole (`.credentials.json` is nothing else), and four keys of
  `.claude.json`'s ninety. Built and shellchecked, **not yet run**.
- **The capsule has static build config**, rendered from `target.sizes` into the
  closure and linked onto the volume by the seed (`target.nix`'s `guestConfig`).
  Until now it built with full debuginfo and an incremental cache — the untuned
  build every existing volume figure was taken against.
- **Four of REQ-450's five axes are green; the fifth is not a row.** Checkout,
  repository and temporary state hold on a capsule nothing has used, and runtime
  now holds too. Process is deliberately unrowed: a capsule is a separate kernel,
  so no delta can falsify the reading, and a permanently green row is misleading
  evidence rather than extra assurance (doctrine DEC-189).
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

The round in progress is *make one capsule usable interactively, then size it
honestly*. Each step is there because the next is meaningless without it.

1. **Rebuild and boot at 4 vCPU / 8 GiB**, which is also what puts the new
   `guestConfig` on the volume. A sizing run before this measures an untuned
   build on a machine the capsule is not.
2. **Measure the high-water mark**, harness and build resident together in one
   `systemd-run --scope` (`MemoryMax=7G`, `AllowedCPUs=0-3`, `--uid=agent`,
   `bash -lc` — proxy vars are login-shell scope) and read `memory.peak` plus
   `memory.events`. Three outcomes, not two: `oom_kill 0` with a large `max`
   count means it survived by thrashing reclaim. This is the figure that says
   whether 8 GiB is the right declaration — and, per the withdrawal above, the
   first memory number here that will have been measured at all.
3. **Run `capsule-inject`** — built (below), never run. It is what makes step 2
   possible at all: the measurement needs a signed-in agent, and this capsule
   has no `~/.claude`.
4. **`capsule-baseline`** — host-initiated `just web-build test` to green, which
   seeds the caches and yields the **cold build** figure. That figure is
   unmeasurable *by the freshness probe*, whose namespace has no upstream — not
   unmeasurable in general, and this is where it comes from.

Then Plan C:

5. `capsules.nix` — under netns it is a name list and little else.
   [Sketch](./plan-c-implementation.md#capsulesnix-sketch).
6. Host-module netns wiring: `capsule-netns@` (root oneshot, `ip netns add/del`,
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
- **Whether an injected credential survives use.** The token rotates on refresh
  and the capsule holds a copy, not the shared file — so host and capsule drift,
  and how long a capsule's copy stays good is unknown. `capsule-inject --force`
  is the answer until it is measured. (The transport half of "non-git
  provisioning inputs" is closed: `capsule-inject` uses it.)
- **Quarantine retention** (doctrine has DEC-193 proposed).
- **Throughput over the unix socket.** The tap did ~100 MiB/s each way.
- **The cold build under freshness** is unmeasured and cannot be measured by that
  probe — see [probes.md](./probes.md). Step 4 above is where it comes from.
- **What N capsules cost under load.** The pair probe priced two *idle* capsules
  and that is cheap; two concurrent builds against their ceilings is the question
  it did not ask, and it is what replaced the withdrawn 16 GiB figure.
- **Time-to-interactive is not 8.31 s.** "Usable" in [probes.md](./probes.md)
  means *provisioned* — that is the freshness probe's own definition. An
  interactive capsule is boot + provision + setup + a cold baseline build, and
  because `/work/home` is on the volume that freshness deletes, **setup is paid
  per fresh capsule**. `capsule-inject` being fast and idempotent is a
  requirement, not a nicety.
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
