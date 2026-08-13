# Status — where this stands, and what is next

The one place the current state lives. Read it before picking the work up cold,
and edit it when the state changes rather than adding a second account of it
somewhere. Figures belong in [probes.md](./probes.md), reasoning in
[notes.md](./notes.md); this file says what is true now and what happens next.

Last updated 2026-08-13, after secrets at start — which closes Plan C item 7 —
the `capsule` CLI, and the load figure before it,
and before that 2026-08-12,
when the units ran at N=1 and `probe-netns-egress`
re-ran 27/27 behind them — and then after the one bug that stood between N=1 and
N=2: a host program's transport is an argument now ([notes](./notes.md) item 20),
and `probe-two-capsules` re-ran 28/28 on it with one program set instead of two.
**Since then N=2 has run through the module path** — two capsules declared
([notes](./notes.md) item 21), both provisioned, injected and cold-baselined
green, the unit's `ExecStop` green on both, and the guard holding two namespaces.
**And the load figure is taken**, which closes step 6 and the last thing Plan C
owed before its CLI work: two cold builds at once cost 112 s and 121 s against a
109 ± 5% sequential control, with neither capsule reaching its memory ceiling and
neither ever reclaimed ([probes](./probes.md#two-cold-builds-at-once)).
**And now the pressure half of it too**, from a second concurrent pair that
replicated the durations — so step 6 has nothing outstanding
([notes](./notes.md) item 24).

## Where it got to

- **Contention at N=2 is measured, and it is not io.** A second concurrent pair of
  cold builds — 113 s and 118 s, replicating 112 / 121 — stalled **0.033% of its
  wall clock on cpu and 0.002% on io**, with zero reclaim on either unit
  ([probes](./probes.md#pressure-under-two-concurrent-cold-builds)). io being the
  smaller by an order of magnitude reverses what Plan C's disk table had this repo
  expecting. The figure is an upper bound, because the window is each cgroup's life
  rather than the build — at 0.03% that is enough to settle it. Two things made it
  available at all, and both are the point: cpu/io `total=` is cumulative, so it
  survived the run being unsampled, and nothing had been stopped, so the cgroups
  still held it. `just load` now reads those totals at both ends and refuses when a
  pressure file is unreadable, since PSI off would otherwise report *no contention*
  where it means *no measurement*.
- **A `set -u` script must not be the login shell, and this one was.**
  `capsule-baseline`'s runner ran as `bash -l run.sh`, and NixOS's
  `/etc/bash_logout` opens by reading an unset guard variable — fatal under `set
  -u`, which **replaced the script's exit status with 1**. So every baseline since
  the last guest rebuild reported a red build while the build itself went green:
  `start` detaches before the login shell exits, so the volume's `history.tsv` was
  right and the terminal was wrong, which is the property [notes](./notes.md) item
  19 built the program around. Fixed in-tree by making the runner a child of the
  login shell rather than its script — one process, environment still inherited
  ([notes](./notes.md) item 24). **Unshipped**: the module path runs the installed
  copy, so it needs `~/flakes` relocked and a rebuild.
- **doctrine's guest has nix-ld now, and its baseline has the sizing fix.**
  Cherry-picked off `second-target`, where they were found — [notes](./notes.md)
  item 23 came with them, so the citations in both files resolve here. Neither is
  target-shaped, which is the whole reason they belong on this branch too: every
  non-nix-native toolchain needs a `/lib64` loader and none of them supplies a
  different one, and one `du -sm` over several paths charges a hardlinked inode to
  whichever argument came first regardless of whose paths they are. cargo happens
  to show neither, so doctrine is where they are least likely to be exercised and
  most likely to rot. What did *not* come across is that branch's `status.md`:
  present tense is per-branch, and this branch's present is doctrine.
  **The guest changed**, so it wants a new image and `sudo microvm -u <name>`
  (`just refresh <name>`) before an existing capsule runs it.
- **A start now leaves a capsule you can work in, and it cost no mechanism.**
  Plan C item 7's last piece: `capsule <name> start` waits for the guest to answer
  and then pushes every payload `setup.nix` declares, so a `/work/.env` is no
  longer typed into each capsule by hand. The whole of it is a third declared
  payload — `$HOME/.config/capsule/<name>.env`, else `.../env`, to `/work/.env`,
  with `op inject` as the same interface and one line away — plus two changes
  around it: `optional`, so a host with no source for a payload skips it by name
  instead of failing, and a bounded wait in `start`, because a running VMM was the
  old promise and it left a capsule nobody can work in. Absence and emptiness
  became one fact in `capsule-inject` on the way past, which is one control flow
  per payload instead of two. Write-if-absent is what makes injecting at every
  start safe, and it is also the cost: a secret changed on this host does not
  reach a capsule that already has one without `capsule <name> inject env
  --force` ([notes](./notes.md) item 22). **Unrun** — `just build` and a host
  rebuild, since the module's copies of `capsule` and `capsule-inject` are the
  ones a start uses.
- **There is a `capsule` CLI, and the justfile got smaller rather than larger.**
  `host/cli.nix` — `capsule [<name>] <verb> [args…]`, name first, omitted meaning
  `capsules.default`: `start`, `stop`, `created`, `ssh`, `admin`, `setup`, and the
  four programs by name. The split it draws is the one that matters: `microvm -c`
  resolves an instance name as a flake attribute, so **creating** a capsule needs
  this checkout and **running** one must not — the units are on the host and a
  human logged into it has no repo. `just up` keeps the create and the tap
  refusal; `_capsule` and `_guest-ssh` are deleted rather than wrapped, and the
  recipes that remain are one-line delegations. One store path, installed by both
  paths, because unlike the four programs it carries no transport
  ([notes](./notes.md) item 20). It needs no host rebuild to be useful, since the
  devshell's copy picks the module's copy of each program; a rebuild only puts
  `capsule` itself on a host with no checkout. **Run: the door, `start` and
  `stop`.** The door proved itself against the load round's own ambiguity —
  `capsule <name> ssh 'tail -1 /work/baseline/history.tsv'` returned 112 s from one
  capsule and 121 s from the other, the two rows that were indistinguishable by
  prompt ([probes](./probes.md#two-cold-builds-at-once)) — and `just down capsule-b
  && just up capsule-b` went green through the delegations: the guest visibly
  unmounting, `Deactivated successfully` with no timeout, then the guard back at
  two namespaces. **Unrun: `setup`** (its three parts have each run separately).
- **`just status` can see every capsule now, and the way it does is the point.**
  `capsule all status` is a row per capsule — created, VM / proxy / relay unit
  state, door, whether the guest *answers*, refs collected — and a witness line for
  what no unprivileged reader can see. The namespace's own `ip_forward=0` and the
  three drops are `capsule-perimeter-guard`'s, audited every 10 s with egress bound
  to it, so the table names it rather than printing "unknown"; `ip netns exec`
  wants root and a status that needs root is a status nobody runs. `all` is a name
  rather than a flag, and it aggregates *questions* only — `branches` and `fetch`
  take it too, `start`/`stop`/`setup` refuse it, since a half-applied action across
  N capsules needs a policy nobody has decided ([notes](./notes.md) item 20).
  Run against the live pair: both rows `running`/`running`/`running`, both guests
  answering, and it correctly reports **no** collected refs for `capsule-b` while
  finding `capsule`'s one ref in the devshell path's quarantine. `_quarantine` and
  `_guest-ssh` are gone with it, and `just proxy-log` was quietly broken — it
  looked for the pre-per-capsule log path.
- **The netns boot is verified.** `sudo probe-netns-boot`, 9/9 — firecracker comes
  up with its tap created inside a namespace, the guest boots and answers ssh in
  there, and the tap, the guest and its ssh port are all unreachable from the root
  namespace. ssh and git both cross a unix socket into it unprivileged, which also
  closed item 18's unmeasured `ProxyCommand`. It needed no host config: the boot
  was never systemd's question. **Nothing in the netns shape is unverified now** —
  see [probes.md](./probes.md).
- **The perimeter survives the move into a namespace.** `sudo
  probe-netns-egress`, 27/27 on the first run — the real capsule, the real
  `capsule-proxy` joined to its namespace, the guest getting a 200 for an
  allowlisted host and a 403 for one off the list, and getting nowhere at all by
  any other route even holding the default route guest root can add. The
  ip_forward control flips it both ways, and the two drops the earlier probes
  called for (the tap's input drop, the aggregator's interface-pair drop) are
  each verified by removing them and watching the wall fall over. **This was the
  last unverified claim in the netns shape.** It also found what the plan's unit
  inventory had left out, and that this host needs a `~/flakes` DNS edit before a
  capsule can resolve through its own chain — both in
  [probes.md](./probes.md).
- **The netns shape is wired, as units.** `host/netns.nix` is
  `probe-netns-egress` translated into systemd: the aggregating namespace, a
  namespace per capsule with `ip_forward=0` in it, a veth each, the three drops,
  host NAT and forwarding, and the resolver stub — which is a module option now
  rather than a `~/flakes` edit, so that half of NOTES item 7 comes home.
  `host/services.nix` generates the per-capsule units around it: the proxy
  joined to its namespace, the ssh relay on `/run/capsule/<name>/ssh.sock` as
  the human, and drop-ins on `microvm@<name>` and `microvm-tap-interfaces@<name>`
  that put both in the namespace and fix microvm.nix's `Restart=always`. The
  guard is rewritten around the namespaces and holds all of them at once.
  **Run at N=1 and N=2 on Sleipnir.** `just units` stays the eval-level check
  this repo can do without a host, and it grew a second job on the way: it
  refuses a newline in any `serviceConfig` value, because that is what a whole
  evening went to (step 5).
- **A host program takes its capsule as an argument, and two capsules have used
  it.** `--capsule <name>`, `CAPSULE_NAME`, or `capsules.default` — one store path
  for provision, collect, inject and baseline, serving every capsule, because the
  relay socket is derived from the name rather than baked. This was the one bug
  between the units at N=1 and N=2. **`sudo probe-two-capsules` re-ran 28/28** with
  one program set instead of two, reproducing run 1's figures inside a tenth of a
  second and strengthening the withdrawn-ceiling finding on the way past
  ([probes.md](./probes.md)). [notes](./notes.md) item 20 has the decision and the
  CLI shape that follows. **The module path's copies are run too now** — they are
  what provisioned, injected and baselined both capsules — and they refuse rather
  than time out when the devshell's shadow them on `PATH`. `just provision |
  inject | baseline | collect | setup <name>` picks the copy that can reach the
  capsule named.
- **A stop is a reboot, and that makes it clean.** The thing standing between
  N=1 and two capsules building at once was that `systemctl stop microvm@<name>`
  is a power cut on a mounted volume. It is not a missing signal, it is the
  wrong one: firecracker's only shutdown signal is an i8042 keystroke and this
  guest's driver refuses its stub (`error -22`), while a guest *reboot* unmounts
  and then resets — and `reboot=k` turns that reset into `Firecracker exiting
  successfully. exit_code=0`, measured, with nothing killing it.
  `host/halt.nix` is that request, one program for both paths, and the identity
  is a host-owned stop key rather than the human's: an `ExecStop` has no ssh
  agent, and the `+` prefix that would make it root would also drop it into the
  root namespace where the guest is unroutable ([notes](./notes.md) item 11). A
  capsule with no readable stop key now refuses to start. `vm-stop` lost its
  `SendCtrlAltDel` fallback in the same change, since it was inert. **Run on
  both paths now.** The unit's `ExecStop` went green on the second rebuild —
  `capsule-halt: reboot requested`, the guest visibly unmounting on the console,
  `Deactivated successfully`, no timeout, for both capsules. The first rebuild is
  what found that the drop-in carrying it had never parsed (step 5).
- **The serial console takes TUI input now**, which reverses a gotcha that has
  stood since the beginning: `boot.kernelModules = ["i8042" "atkbd"]` makes
  Enter work in claude on the console, A/B'd both ways. No input device appears
  and i8042 does not even probe, so the mechanism is unknown and the fix is
  recorded as an observation ([notes](./notes.md) item 11). ssh stays the
  documented way to run an agent.
- **The instances are declared.** `capsules.nix` — a value, and a short one:
  which capsules exist, each one's namespace, its way in
  (`/run/capsule/<name>/ssh.sock`) and its uplink /30 to the aggregator, plus
  the aggregator itself. The index is declared rather than positional and two
  capsules cannot share one; a name over 11 characters is refused, since it is
  on the wire twice and IFNAMSIZ is 15. `net.nix` is untouched and stays flat:
  under netns every capsule has the *same* tap, /30 and MAC, which is what one
  guest image means. Nothing consumes it yet beyond the socket path `flake.nix`
  was already spelling — the units in the next step are what it is for.
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
- **Two capsules building at once is measured, and RAM is not what binds.**
  Fresh volumes, same commit both sides, so concurrency was the only variable:
  **112 s and 121 s** to green against 109 / 115 / 104 sequential — ~5% at the
  tail — with unit peaks of 7774 and 6801 MiB inside the declared 8192 and
  `memory.events` zero everywhere, so those are true high-water marks. The pair's
  own peak is a **bound**, [7774, 14575] MiB, because the slice that would have
  settled it had its peak set in an earlier session: a unit's cgroup is destroyed
  by a stop, a slice's is not. `just load` reads every peak at start as well as at
  end for that reason, and writes them beside the samples. Figures and the host's
  other load in [probes.md](./probes.md#two-cold-builds-at-once).
- **A capsule cannot say which capsule it is**, and this is where that stopped
  being theoretical: one image means every guest is `agent@capsule`, so the two
  `history.tsv` rows were indistinguishable by prompt and the differing durations
  were the evidence. The price is [notes](./notes.md) item 21's, knowingly paid.
  What was missing was a way to *ask*: `capsule <name> ssh <cmd>` and `capsule
  <name> admin <cmd>` pass a command through (`just ssh`/`just admin` delegate),
  and the door refuses instead of falling through to an unroutable `net.guest`
  when the named capsule has no relay socket but another capsule does — the timeout-that-reads-as-a-dead-guest the
  four programs were already taught to refuse ([notes](./notes.md) item 20).
- **Two capsules run at once, 28/28, twice.** One runner store path, two namespaces, two
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
  `.claude.json`'s ninety. **Run, and the agent starts signed in** — so four
  keys is enough and no capsule needs its own credential.
- **The capsule has static build config**, rendered from `target.sizes` into the
  closure and linked onto the volume by the seed (`target.nix`'s `guestConfig`).
  Until now it built with full debuginfo and an incremental cache — the untuned
  build every existing volume figure was taken against. **It cost one file and
  took `/work/doctrine` from 6.9 GiB to 1.1 GiB** for the same workload.
- **8 GiB is measured, not assumed.** Four scope runs at 4 vCPU / 8 GiB: an idle
  agent is 344 MiB and flat, a warm build peaks at 3980 MiB, the two together at
  4114, and a build from `cargo clean` at **4513 MiB** — with **zero pressure
  events** in all four, so those are true high-water marks. ~3 GiB of headroom
  stands. Figures and provenance in [probes.md](./probes.md); the sampling
  method is part of the finding, since the first run's numbers died with the
  terminal that printed them.
- **`capsule-baseline` exists and has run green, and the cold build is
  measured.** The third of the three setup problems (design.md), and the last
  step of making a capsule usable: it runs `target.nix`'s `baseline` — for
  doctrine `just web-build test` — in the guest's checkout under a login shell,
  detached, and writes its log plus one line of `/work/baseline/history.tsv`
  **on the volume as it goes**. The host attaches to watch and may leave;
  re-running attaches to the run in flight. Run 1 on a deleted volume:
  **109 s to green**, ~1.1 GiB of volume, and the record proves its own
  coldness — the caches totalled 123 MiB before and `.cargo` alone was 144 MiB
  after. Figures in [probes.md](./probes.md); [notes](./notes.md) item 19.
- **Time-to-interactive is ~2 minutes, and ~93% of it is that one build.**
  8.31 s to provisioned, seconds of `capsule-inject`, then 109 s of baseline —
  from separate runs, so it is an order of magnitude rather than a stopwatch.
  Every other figure this repo has taken is noise beside it, which is worth
  knowing before optimising any of them.
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

The round just finished was *make one capsule usable interactively, then size it
honestly*. Each step was there because the next was meaningless without it.

**It is done.** The capsule boots at 4 vCPU / 8 GiB with `guestConfig` on
its volume and a signed-in agent in it, it is sized honestly, and one command
takes a fresh one to green and says what that cost. Next is Plan C:

1. ~~`sudo probe-netns-egress`~~ **done, 27/27** — see above. The shape it proved
   is what the next two steps assemble out of units, so they are bookkeeping
   against a known-good result rather than experiments on a live host.
2. ~~`capsules.nix`~~ **written** — see above.
3. ~~Host-module netns wiring at N=1~~ **run, and it holds.** All seven units
   active on the first start after the rebuild; `capsule-perimeter-guard` reports
   `1 capsule namespace(s) verified`. Verified by hand from inside the guest,
   which is the part that could not be argued from the probe:
   - no default route, and `curl --noproxy '*'` to a raw address exits 7
     (`COULDNT_CONNECT`) — the namespace's own `ip_forward=0`, with no host
     sysctl involved.
   - allowlisted host 200 through the proxy, non-allowlisted 403 from tinyproxy,
     immediately rather than as a timeout — so the resolver stub the probe had to
     fall back from works, and a denial is a denial rather than a name that would
     not resolve.
   - `capsule-provision` and `capsule-collect` both over the relay socket, at
     [full speed](./probes.md).
   The acceptance test then re-ran with the units stopped: **27/27 again**, and
   this time without the DNS fallback — the module's stub answers, so the capsule
   keeps the host's DoT chain and the probe says so ([probes.md](./probes.md)).
   Nothing the units did invalidated a claim the probe had made by hand. Two traps
   the first start cost, both now in [CLAUDE.md](../CLAUDE.md): `microvm -c … -f`
   takes no fragment, and a missing create fails as an unrelated dependency error.
4. ~~The transport is baked into a store path~~ **fixed, and run at N=2.** All four host
   programs now take `--capsule <name>` (else `CAPSULE_NAME`, else
   `capsules.default`) and derive the relay socket from it, so one store path
   serves every capsule and `host/programs.nix` still knows no transport. The
   seam widened rather than moved: `sshArgs`, a value, became `transport`, a shell
   fragment injected at the same call sites. `capsule-collect`'s positional
   quarantine name is gone — it was the capsule's name at every call site — so the
   asymmetry closed by deleting half of it. The CLI question Plan C item 7 wanted
   is decided in [notes](./notes.md) item 20, including what a `capsule <name>
   <verb>` front end is left to do. **`sudo probe-two-capsules`, 28/28** — the
   acceptance test is the probe that exposed the bug, and it now runs one set of
   programs twice. What that run does *not* cover is the module path's copy of the
   same programs, which needs a host rebuild.
5. N=2 through the module. **Run, and it holds** — two capsules on one image
   through the units, both provisioned, injected and cold-baselined green
   (115 s and 104 s, two different base commits, [probes](./probes.md)); the
   unit's `ExecStop` green on both; the guard reporting two namespaces. What it
   cost is below and in [CLAUDE.md](../CLAUDE.md): the drop-in carrying the stop
   had never parsed. **What is left of this step is the load figure** — two cold
   baselines at once, on fresh volumes, against those three sequential runs as
   the control, with `just load` sampling the host. The first thing that sampler
   measured is already a finding: a capsule that has built once holds most of its
   ceiling until it is stopped, and the slice holding both peaked at 16305 MiB
   ([probes](./probes.md)).

   The wiring, for the record: `capsule-b` is index
   1 in `capsules.nix`, and every declared capsule is now an attribute of
   `nixosConfigurations` bound to *one* value, because `microvm -c <name>`
   resolves the instance's name as a flake attribute and the per-instance
   `mkVm` that would satisfy it is a second guest image
   ([notes](./notes.md) item 21). The same rebuild carries one small fix: the
   ssh relay declares `SuccessExitStatus=143`, since socat exits on SIGTERM
   itself and left the unit `failed` after every ordinary stop.

   **It took two rebuilds, because the first one found that the `microvm@<name>`
   drop-in had never parsed**: the stop-key `ExecStartPre` was multi-line, which
   systemd reads as unbalanced quoting, so the namespace, the `ExecStop` and
   `Restart=no` behind it were dropped and both capsules crash-looped in the root
   namespace — while both proxies, both relays, both sockets and the guard all
   reported health. That is the whole reason it cost an evening, and it is why
   `just up` now asserts the VM stayed up and `hostModuleUnits` refuses a newline
   in any `serviceConfig` value. Also closed on the way past: item 20's unrun
   half — the module's copies of all four programs are what provisioned, injected
   and baselined both capsules.

6. ~~The load figure~~ **taken, on fresh volumes, and it holds**: 112 s and 121 s
   for two concurrent cold builds against the three sequential runs as control,
   both units inside their ceiling with zero reclaim
   ([probes](./probes.md#two-cold-builds-at-once)). It cost one correction to its
   own instrument rather than to the capsules — a slice's `memory.peak` outlives
   the units in it, so the pair figure is a bound and `just load` now says which
   peaks it actually set. ~~No `.vm/load.tsv` was taken, so cpu and io pressure
   under concurrent load are still unmeasured.~~ **Measured, by a second pair the
   next morning**, and again without a sampler: the cumulative `total=` fields
   outlive the run as long as nothing is stopped, so 0.033% cpu and 0.002% io came
   out of the live cgroups afterwards
   ([probes](./probes.md#pressure-under-two-concurrent-cold-builds)). **This step
   is done.** What no run has yet is a time series — the totals say how much, never
   when.
7. **What is left of Plan C item 7** — two of three pieces done:
   - ~~the `capsule` CLI~~ **written and run** — see above and
     [notes](./notes.md) item 20.
   - ~~`status` and the aggregates~~ **written and run**, and the blindness is
     closed by naming the guard as the witness rather than by finding a way into a
     namespace.
   - ~~Per-capsule secret injection at start~~ **written, unrun.** The two shapes
     turned out to be one interface that already existed — a `produce` fragment in
     `setup.nix` — so what was built is a declaration, an `optional` field for a
     payload no host is required to have, and the wait that lets `start` push the
     list ([notes](./notes.md) item 22). Needs `just build` and a host rebuild
     before a start on this host does any of it.

   **So item 7 is closed.** Next is Plan C's
   [order of work](./plan-c-multi-capsule.md#order-of-work) item 8 — a second
   target, if it is still wanted.

Then the rest of Plan C's
[order of work](./plan-c-multi-capsule.md#order-of-work).

## Open, and nothing should claim these closed

- ~~**Egress under netns is unproven.**~~ Proven, 27/27
  ([probes.md](./probes.md)). What replaces it is narrower: the same perimeter
  built out of systemd units rather than a probe's `ip`/`nft` calls, and DNS
  through the host's own chain — the probe had to fall back to a public
  resolver, so that half is unproven until `~/flakes` grows the stub address.
- **The byte/disk bound on collect.** `ulimit -f` bounds one packfile, not the
  transfer — many small objects or a delta bomb go past it. A quota or a dedicated
  filesystem for the quarantine is the host-shaped answer.
- **Whether an injected credential survives use.** The token rotates on refresh
  and the capsule holds a copy, not the shared file — so host and capsule drift,
  and how long a capsule's copy stays good is unknown. `capsule-inject --force`
  is the answer until it is measured. (The transport half of "non-git
  provisioning inputs" is closed: `capsule-inject` uses it.)
- **A rotated secret does not reach a running capsule either**, and for the same
  reason: every payload is write-if-absent, which is what makes injecting at every
  start a no-op rather than a clobber. Editing this host's `.env` changes nothing
  until `capsule <name> inject env --force`, which discards what the guest wrote
  into that file. Refreshing at start would do that discarding silently, N times,
  so it is not policy ([notes](./notes.md) item 22).
- **Quarantine retention** (doctrine has DEC-193 proposed). Two pieces of stale
  state on this host are the near-term case for it: `/var/lib/capsule/collect/`
  holds a `faux.git` from before a capsule named its own quarantine, and
  `/var/lib/capsule/doctrine.git` is the served mirror [notes](./notes.md) item 18
  deleted the *service* for. Both are out-of-band cleanups, not flake changes.
- **Nothing outside a capsule's namespace can independently confirm its
  `ip_forward=0`.** This is what is left of `just status`'s blindness after
  `capsule all status`: the guard is the only reader of the inside of a namespace,
  so if the guard is wrong it is wrong alone. It holds egress bound to itself, which
  is why that is acceptable rather than merely unavoidable.
- ~~**Throughput over the unix socket.**~~ Measured on the first real
  provision/collect pair: **93.7 MiB/s out, 117.9 MiB/s back**
  ([probes.md](./probes.md)), against the tap's ~100 MiB/s each way. The relay is
  not a bottleneck on bulk. What the same session did find is per-packet:
  `socat` sets no `TCP_NODELAY`, so interactive echo clumped until the unit
  gained `,nodelay` — and that fix is shipped but unmeasured.
- ~~**The cold build under freshness**~~ — measured, 109 s, one run
  ([probes.md](./probes.md)). What stays open is that the *freshness probe* still
  cannot take it: its namespace has no upstream, so the price and the 22
  assertions come from different runs and should not be quoted as one result.
- ~~**What N capsules cost under load.**~~ ~~**Pressure under concurrent load is
  unmeasured.**~~ Both measured at N=2 — wall clock and memory
  ([probes](./probes.md#two-cold-builds-at-once)), then cpu and io stall from a
  second pair ([probes](./probes.md#pressure-under-two-concurrent-cold-builds)).
  Three narrower things replace them. **Nothing has a time series**: the stall
  figures are cumulative totals over each cgroup's life, so they bound how much and
  say nothing about when, and `just load` has still never sampled a build.
  **N=2 is not N.** And the **ratchet** remains the term that decides how many fit:
  a capsule holds most of its ceiling until it is stopped — measured now as 6141
  MiB of `anon` held for a guest reporting 481 MiB used, because firecracker has no
  balloon and no free-page reporting — so those peaks are not additive across a
  working day.
- **Time-to-interactive is not 8.31 s.** "Usable" in [probes.md](./probes.md)
  means *provisioned* — that is the freshness probe's own definition. An
  interactive capsule is boot + provision + setup + a cold baseline build, and
  because `/work/home` is on the volume that freshness deletes, **setup is paid
  per fresh capsule**. `capsule-inject` being fast and idempotent is a
  requirement, not a nicety.
- ~~**A relay outliving its VM is fixed in-tree and unshipped.**~~ Shipped:
  `~/flakes` has relocked since, and this host's installed relay binds the tap unit
  as well as the namespace, while its `capsule-baseline` carries `ConnectTimeout`.
  So the hand-stop of `capsule-ssh-relay-*` is no longer needed here. The reasoning
  stands in [notes](./notes.md) item 20 — a socket is the identity, and a unit bound
  only to a namespace outlives its guest.
- **`capsule-baseline`'s login-shell fix is in-tree and unshipped**, which is the
  same shape one line up: the module path runs the installed copy, so until
  `~/flakes` relocks again every `capsule <name> baseline` on this host exits 1
  after correctly starting the run ([notes](./notes.md) item 24). The workaround is
  to disbelieve the exit status and read the record — `capsule <name> ssh cat
  /work/baseline/history.tsv`, whose last line is the truth.
- **The corrected `capsule-baseline` sizing has never produced a record.** It was
  written against a diagnosis and verified by hand over ssh, and now it is on a
  branch whose target cannot exercise it: doctrine shares no inodes between
  `target/` and `.cargo`, so its split reconciles either way. The next panopticon
  baseline is the real check, and doctrine's next one only says the fix did no
  harm ([notes](./notes.md) item 23).
- **The guest's clock is UTC and this host is AEST.** A guest file mtime read
  against a host clock is ten hours out, which is enough to make tonight's run look
  like last night's and cost real time. Baseline stamps are UTC by design (they are
  the host's, and named to need no quoting); it is `ls` in the guest that misleads.
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
