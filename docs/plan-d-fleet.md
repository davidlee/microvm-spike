# Plan D — the fleet: capsules across projects, refs and slices

Scoping, not commitment, and the second of the two things the work is now
directed by. The first is doctrine's needs for capsule-based execution
([contract-doctrine.md](./contract-doctrine.md)); this file is the other one —
*what it is like to run several capsules, across more than one project, on one
host*, and which of that the current design makes cheap, dear or impossible.

Plan C asked whether N capsules can run at once and priced the mechanism. They
can, and it holds at N=2 ([status](./status.md)). This asks the question that
follows and that Plan C left out: **N capsules are an inventory, and an
inventory has to be administered** — assigned, re-assigned, inspected, recycled,
thrown away.

Limitations here are structural: consequences of where a value lives, not of
what has been built yet. Where something is merely unrun, this says so and links
to [status.md](./status.md), which owns the present tense.

## 0. Settled

Decided in conversation, so the rest of the file can lean on it. Not built.

- **Slots are abstract and pre-declared.** `a`…`j`, roughly ten, four to six hot
  at once. A slot's name carries no meaning, which is what makes an assignment
  record necessary rather than nice.
- **`sizes.mem` drops to 6144, and the reason is the fleet rather than the
  measurement.** [probes](./probes.md#what-a-capsule-costs-to-work-in) argued
  the other way at N=1 — *"Not cut to 6 GiB on n = 1… a generous declaration
  costs nothing until something touches it"* — and that argument is sound and
  expires here: a ceiling is free per capsule and a reservation per fleet,
  because nothing hands it back until a stop. What the cut is **not** justified
  by is 4513 MiB. That is a guest-side peak inside a `MemoryMax=7G` scope, which
  excludes the guest kernel, sshd, the RAM-backed journal and the tmpfs root — a
  scope figure read against a VM ceiling. The term the fleet is arithmetic on is
  the *unit's* cgroup peak: 7169 / 7510 / 7774 / 6801 / 7845 MiB across five
  cold builds, and once **8365 against a declared 8192**, where the +173 MiB is
  host page cache for the VMM's image and volume reads — charged to the unit,
  reclaimable, with `memory.events` zero throughout. ~~So a slot costs `mem` plus
  ~0.2 GiB observed, and six at 6144 is ~36-37 GiB.~~

  **Struck — the cut is free but it is not a saving, and the arithmetic above is
  the part that was wrong.** A built slot holds ~6.1 GiB of `anon` at *either*
  ceiling (6141 of 8192, 6095 of 6144), because the VMM holds every distinct page
  the build ever touched rather than a share of what the guest was offered
  ([probes](./probes.md#the-first-cold-build-at-a-6144-ceiling)). Two things
  follow. **`mem` is not a term in what a slot costs** until it drops below the
  workload's touched footprint, at which point it stops being free and starts
  squeezing the guest — 6144 did not, and nothing says where that boundary is.
  And **`+0.2 GiB` was one instance, not a constant**: the page-cache half has
  read 173, 965 and 1493 MiB, so the honest form is ~6.1 GiB of hard `anon` plus
  0.2-1.5 GiB of reclaimable cache. Six hot is therefore ~45 GiB by the same
  addition, worse than the 36-37 it replaces — **but that addition is itself
  suspect**, because one guest image means the cache pages are largely the *same*
  pages, charged to whichever slot faulted them first, and summing them per slot
  double-counts. That is the measurement N=2-at-6144 would settle and no run has.
- **Four hot is the recommendation, and now for a different reason.** Not
  because six fits the arithmetic — the arithmetic above is withdrawn — but
  because the term that binds was never `mem`: this host had **13.1 GiB available
  with both capsules idle** and ordinary work running, and an idle built capsule
  holds ~6.1 GiB of `anon` while the guest inside it reports a few hundred MiB
  used ([probes](./probes.md#what-a-capsule-holds-after-it-has-built)) — the
  ratchet, which only a stop closes and which a smaller ceiling does not shorten.
  Four is the number with evidence under it; what would move it is a hot-slot
  count measured directly, not a per-slot figure multiplied.
- **`~/flakes` takes this repo locally.** The `github:davidlee/oubliette` input
  exists so darwin can evaluate the flake, not because the host wants a round
  trip; Sleipnir overrides it with `git+file:///home/david/dev/microvm-spike` at
  rebuild time. Not `path:`, which copies the working tree unfiltered and would
  drag `.vm/`'s volume images into the store. Class 3 below becomes commit →
  switch.
- **The existing capsules are expendable.** `capsule` and `capsule-b` get
  renamed into slots rather than special-cased.
- **Two modes, one mechanism.** This host is a dev machine and can be
  permissive; a future agent-ranch cannot. Nothing here may bake the permissive
  answer in as the architecture — it has to fall out as a declaration.
- **Longer term, a slot has a class**, EC2-shaped: `small`, `high-cpu`, and
  perhaps a role (`worker`, `auditor`). Noted as a goal, deliberately not chased
  here — but see §6 for the two ways to get it wrong.

## 1. What varies per capsule, and what cannot

| axis | where it lives | cost to change it |
| --- | --- | --- |
| name, index, namespace, socket, uplink /30 | `capsules.nix` | host rebuild (class 3) |
| base commit | argument to `capsule-provision` | seconds, no rebuild |
| everything on the volume — checkout, `$HOME`, caches, `target/`, ssh host keys, `.env`, baseline record | per instance, created by microvm.nix | no verb at all (L4) |
| secret payload *content* | `~/.config/capsule/<name>.env`, per capsule by filename | `capsule <n> inject env --force` |
| secret payload *declaration* | `setup.nix` | host rebuild |
| **target repo** | `inputs.target.url` + `target.nix`, **global** | one image at a time, and switching is a branch (L1) |
| tool set | the target's own flake | guest rebuild + `microvm -u` per capsule |
| `defaultBranch` | interpolated into `capsule-provision` and into the guest's seed | host rebuild, and **no run-time override exists** (L13) |
| sizes (vcpu, mem, volume) | `target.nix`, **global** | class 2 — but they are in the runner, not the image; §5 (L2) |
| allowlist *content* | a plain file | edit + `systemctl restart capsule-proxy-<n>` |
| allowlist *file* (a different one per capsule) | `services.capsule-perimeter.allowlist`, one for the host | host rebuild (L3) |
| what the capsule is *for* | nowhere (L5) | — |

The pattern: **the base commit is the only axis deliberately made a run-time
value** (NOTES item 18, Plan C item 2), and it is the only one that moves
without a rebuild. Everything else about a capsule's identity is declared in
this repo or baked into the guest closure. Right for one capsule; it is what the
fleet runs into.

## 2. The rebuild classes

Five, and knowing which one a change lands in is most of the administrative
cost:

0. **Run time, no build.** `provision`, `inject`, `collect`, `fetch`, `start`,
   `stop`, `ssh`, `admin`, `baseline`; editing `perimeter/egress-allow.txt` plus
   a proxy restart. Seconds.
1. **Local `just build`.** The devshell's copies of the host programs.
2. **Guest image.** `nix build .#capsule`, then `sudo microvm -u <name>` for
   *each* capsule and a restart, because a created VM tracks its state directory
   and not the flake (CLAUDE.md). Triggered by `vm/*`, by `target.nix`'s `sizes`
   / `caches` / `guestConfig` / `extraTools` — `sizes` **perhaps** only
   rebuilding the runner rather than the image, which is §5's inference and §9's
   step 2 — and by `nix flake update target` — which needs a *commit in the
   target repo* first (`git+file:` reads committed HEAD).
3. **Host rebuild.** Anything in `host/`, `setup.nix` declarations, and
   `capsules.nix`. Until the §0 override, also a push: `~/flakes` took the
   module from GitHub, so declaring a capsule meant commit → push → `nix flake
   update oubliette` → `nixos-rebuild switch`.
4. **Create / update the instance.** `just up <name>` (`microvm -c`) needs *this
   checkout*, because the instance name resolves as a flake attribute (NOTES
   item 21); `microvm -u <name>` after every class-2 change.

The two heaviest are the two the fleet leans on hardest: **declaring a capsule
is class 3**, and **pointing a capsule at a different project is class 2 + 4** —
and class 3 too, if it is also a new instance. The cheapest axis, base commit,
is the one that already got the treatment. §5 and §6 are about giving the others
the same treatment, and §5 is why that is affordable.

## 3. User stories

Each is a thing a human wants to do on a Tuesday. `today:` is what happens now.

**S1 — a new project arrives.** A capsule confining `~/dev/otherthing`,
alongside the doctrine ones. *today:* **alongside, no; instead of, yes and it
has been done.** panopticon is confined on branch `second-target` — cold-green
on a brand-new allowlist, 3 s and 105 MiB of volume
([item 23](./ledger/023-second-target.md),
[probes](./probes.md#the-cold-build-on-a-second-target)) — so the port is priced
rather than hypothetical. What is not possible is *both at once*: one
`inputs.target.url` literal, one `target.nix`, one `capsuleVm`, and every
declared capsule bound to that same value, so the switch is a branch and a
class-2/3 chain. (L1)

**S2 — two slices of one project at once.** Two capsules on doctrine, different
base commits, different slices. *today:* works, and is measured — two capsules,
two base commits, both cold-baselined green
([probes](./probes.md#two-cold-builds-at-once)). Collected refs are namespaced
`refs/capsule/<name>/*`, so `capsule all fetch` lands both in one repo without
collision. The gaps are elsewhere: nothing records which slice a capsule holds
(L5), and neither prompt nor motd can say which capsule you are in (NOTES item
21).

**S3 — rebase a capsule onto a newer base.** The branch moved; move the capsule
without losing its work. *today:* `capsule <n> collect` then `capsule <n>
provision <ref>`. Refused if the guest's worktree is dirty (`updateInstead`),
refused if it would discard guest commits; `--force` insists and discards them.
Right defaults. Missing: anything that shows the divergence before you decide
(L6), so the safe sequence is two commands and a habit.

**S4 — throw one away and start clean.** This capsule is wedged; a fresh one
under the same name.
*today:* stop it, `sudo rm -rf /var/lib/microvms/<n>` out of band — destroying
the volume, checkout, `$HOME`, caches *and* ssh host keys — then `just up <n>`,
`just reset-known-hosts <n>`, `capsule <n> setup <ref>`, and pay ~109 s of cold
build. No verb, no partial reset, and the destructive step is a hand-typed
`rm -rf` under `/var/lib`. (L4, L7)

**S5 — warm start.** A new capsule already built, in seconds rather than two
minutes.
*today:* not possible, and how much it costs is target-shaped. On doctrine the
cold build is ~93% of time-to-interactive ([status](./status.md)); on panopticon
it is 3 s against an 8.31 s boot, so there the *boot* is the largest term
([probes](./probes.md#the-cold-build-on-a-second-target)). Nothing shares or
copies a volume either way. (L8)

**S6 — what is running?** Which capsules are up, what each is working on, is
anything stuck.
*today:* `capsule all status` answers created / VM / proxy / relay / door /
answers / collected refs, plus the guard as the witness for what is inside a
namespace. It does not answer *what commit*, *dirty or not*, *how full the
volume is* — the binding constraint — *did the baseline pass*, or *is an agent
running in there*. Each needs an ssh round trip and none is a column. (L6)

**S7 — reset just `$HOME`.** The agent's own state is confused; keep the
checkout and the caches. *today:* not possible short of destroying the volume.
`$HOME` is `/work/home` on the same volume as everything else, so the axes
cannot be separated. (L7)

**S8 — leave an agent running and come back.** Start an agent in slot C, close
the laptop, reattach later; do that for three capsules. *today:* an agent runs
in an interactive ssh session the human holds, and dies with the terminal.
`capsule-baseline` already solves this shape for a *build* — setsid, a record on
the volume, re-running attaches to the run in flight — but nothing generalises
it and an interactive agent needs a pty that pattern does not give. (L9)

**S9 — look at what it built.** The project has a dev server; put a browser on
it.
*today:* ad hoc, and it works — the door is ssh with a ProxyCommand, so
`ssh -L 3000:10.99.0.2:3000 …` forwards a port through the relay socket. But it
cannot be said through the CLI: `capsule <n> ssh` passes trailing arguments as
the *remote command*, so the ProxyCommand has to be reconstructed by hand. No
verb, no record of which capsule owns which host port, nothing stopping two
capsules from claiming the same one. (L10)

**S10 — retire a capsule.** Done with it; give the host its resources back.
*today:* stop, delete the state dir by hand, remove the name from
`capsules.nix`, take the class-3 chain to make the units go away. Its quarantine
at `/var/lib/capsule/collect/<n>.git` is left behind and nothing reaps it
(retention is open — [status](./status.md)). Deleting the *name* is at least
safe by design: indices are declared, so neighbours do not renumber.

**S11 — a secret rotated.** The token on this host changed; running capsules
hold stale copies. *today:* `capsule <n> inject <payload> --force` per capsule,
and the force discards whatever the guest wrote there. Deliberate (NOTES item
22) — but an N-times ritual with no way to ask which capsules are stale.
Injection *at start* would make the ritual a restart, and it is written but
**unshipped on this host** until `~/flakes` relocks ([status](./status.md)).

**S12 — two projects with different dependency hosts.** One needs crates.io, the
other npm.
*today:* one allowlist for every capsule on the host, so the union — a real
widening of each capsule's perimeter for the other's benefit. Cheap to fix (L3).

## 4. Limitations

Structural, numbered for citation. None is a bug; each is a place the design
bought something else.

- **L1 — one target per *image*, so one at a time on this host.** The target
  reaches the guest as a flake input literal, which cannot be computed, and
  every declared capsule is bound to one `capsuleVm` value so that "one image, N
  capsules" is structural rather than a promise (`flake.nix`, NOTES item 21). A
  second target is a second image: +3.0 GiB of erofs, its own tool set, its own
  allowlist, its own `target.nix`. Priced in
  [plan-c](./plan-c-multi-capsule.md#mixed-targets-defer-but-keep-it-possible);
  the cheap insurance it recommended — a `target` field on the instance record —
  **was not taken**: `declared` carries `index` and nothing else.

  What is no longer speculative is the *port*. panopticon is a second target on
  branch `second-target`, and it cost `target.nix` wholesale, one allowlist
  file, `inputs.target.url`, and **one guest capability** — nix-ld, which is now
  on this branch too because every non-nix-native toolchain needs it and none
  supplies a different value for it (NOTES item 23). Nothing generic changed. So
  the limitation is concurrency and the class-2/3 chain, not parameterisation:
  two targets on one host is `git switch` plus a rebuild, and two targets *at
  once* is D7.
- **L2 — sizes are global, and needn't be, but they are not uniformly cheap.**
  vcpu, mem and volume come from `target.nix` for every capsule alike. `mem`
  lives in the runner rather than the erofs, so per-slot memory costs a kilobyte
  — settled by eval in §5. `vcpu` does not: this target renders it into
  `guestConfig`, so per-slot vCPU is a 3.0 GiB image and a `microvm -u` per slot
  ([item 27](./ledger/027-a-class-is-not-always-a-kilobyte.md)). Volume size is
  fixed at first boot and is the volume's, not a class's.
- **L3 — one allowlist per host, not per capsule.** The proxy already takes
  `CAPSULE_ALLOWLIST` per unit and the units are already per capsule; only the
  module option is singular. A per-capsule allowlist is a field and a bind
  mount, not a mechanism. The *naming* half is already decided and in use:
  `perimeter/egress-allow-<target>.txt`, one file per target, with doctrine's
  plain `egress-allow.txt` grandfathered (NOTES item 23).
- **L4 — the volume has no verbs.** Created by microvm.nix, destroyed by
  `rm -rf`. Reset, clone, snapshot and size are all out-of-band operations on a
  path under `/var/lib/microvms`, where a typo is expensive.
- **L5 — a capsule has no purpose, and cannot say its own name.** Nothing
  records what a capsule was assigned to, and one image means every guest greets
  you as `agent@capsule` (NOTES item 21, knowingly paid). At N=2 that was
  already why two probe results were indistinguishable by prompt.
- **L6 — status stops at the door.** Every column is a host-side fact or a
  liveness ping. The facts a human steers by — commit, dirty, disk, baseline
  verdict, is an agent running — live inside the guest and are reachable only by
  hand.
- **L7 — the volume's contents are one axis.** Checkout, `$HOME`, caches and
  `target/` share a lifetime because they share a disk, so freshness is
  all-or-nothing and "reset the agent's state" and "start over" are one
  operation.
- **L8 — every capsule pays the cold build.** On doctrine that is ~109 s and
  ~93% of time-to-interactive, per fresh volume, and nothing reuses another
  capsule's work — but the term is target-shaped, not the capsule's:
  panopticon's is 3 s against an 8.31 s boot, so nothing generic should be tuned
  against either ([probes](./probes.md#the-cold-build-on-a-second-target)). Two
  host constraints on any fix. `/var/lib` is **ext4, so there is no reflink** —
  a cloned volume is a real copy, against the host's own headroom, which
  [probes](./probes.md#figures) owns and no plan should spell twice. And because
  nothing discards, **a volume's allocation is its high-water mark, not its
  current usage** — an image that once held a 6.9 GiB untuned build still copies
  6.9 GiB after it is cleaned. So clone cost is a function of the source's
  *history*, which is a second argument for cloning from a base that was never
  worked in (D4) rather than from a peer. The host-level lever, if clones become
  routine: a btrfs subvolume for `/var/lib/microvms`, which makes them near-free
  — the runner already tries `chattr +C` for exactly that world, and it is a
  no-op on ext4.
- **L9 — no detached session.** An agent's life is an ssh session's life. The
  detach pattern exists (`host/baseline.nix`) but only for a non-interactive
  command.
- **L10 — no port forwarding as a first-class thing.** Possible by hand through
  the existing door; unmanaged, so nothing allocates or records host ports.
- **L11 — declaring a capsule is a git push.** Class 3, plus the GitHub round
  trip. Fixed by §0's local input, which is why that is step one.
- ~~**L12 — one broken slot denies the whole host, and the chain that does it is
  not obvious.**~~ **Closed** ([item
  30](./ledger/030-a-pool-audits-what-exists.md)), which leaves the pool itself as
  D2's only remaining content. The chain was: nothing in `host/services.nix` is
  `wantedBy` anything, so a start of `microvm@<name>` wants its proxy, the proxy
  `BindsTo` the guard — and the guard used to `requires` **every** declared
  namespace unit while auditing all of them every 10 s. A ten-slot pool therefore
  cost nothing at rest and all ten at once on the first start, and the failure
  that mattered was not an idle slot but a *broken* one: a namespace unit that
  refused took the guard with it, and through the guard's `BindsTo` **no capsule
  on the host could start** — not merely the broken one. Correct for a perimeter,
  and at N=2 indistinguishable from robust.

  What replaced it is not the exclusion list this item originally asked for. The
  guard `requires` only the aggregator, orders itself after the namespace units
  without pulling them in, and audits declared ∩ present — with a second limb
  saying every running capsule's VMM is inside its own namespace, which is what
  makes skipping an absent one sound. No new state, no mode, and a *broken*
  namespace is still fleet-wide.
- **L13 — `defaultBranch` has no run-time override, and it is the odd one out.**
  Every other host-side target value either belongs to the guest (`sizes`,
  `caches`, `guestConfig`) or has one — `path` has `CAPSULE_REPO` and the
  module's `repo` option, `allowlist` has `CAPSULE_ALLOWLIST` and its own
  option. `defaultBranch` is interpolated straight into `capsule-provision`, so
  a target switch is a rebuild for that field alone, and
  until it is one the module path's copy refuses a provision of the new
  target's branch — correctly, and with a clear message (NOTES item 23).
  Recorded rather than fixed at the time, because switching targets was a
  rebuild anyway. §6.2 is where it stops being harmless: target as run-time
  state cannot ship while a program spells the branch.

  **Decided: deletion, and nothing replaces it.** The guest's branch becomes the
  constant `work`. Two consumers allow it — the guest's seed, and
  `capsule-provision`'s symref check and push refspec; `capsule-collect` never
  read it (`+refs/heads/*`), so half the problem was never there. An interim
  draft kept an optional profile field for a project that cares what its work is
  called, and **two slices of one project at once refutes that**: if a branch
  name identifies the work it is not project state, and collect already lands
  everything as `refs/capsule/<slot>/*` where whatever names the work outside
  this repo can name it. So L13 closes in the strongest available form — not a
  fifth override, not a defaulted field, no field. Written up in
  [contract-target.md](./contract-target.md), including the separation it turns
  on: `capsule-provision <ref>` is a ref in the *target repo* and is untouched.

## 5. Read from source: where a capsule's identity actually lives

The affordability of everything in §6 rests on three facts about microvm.nix,
read from its own source and from this host's store rather than assumed. Same
move as Plan C's
[host-module question](./plan-c-multi-capsule.md#the-host-module-question-answered-from-source).

**`microvm -c` is ten lines.** In a temp dir: write the flake ref to a file,
`nix build -o current
"$FLAKE"#nixosConfigurations."$NAME".config.microvm.declaredRunner`, `mv` the
dir to `/var/lib/microvms/$NAME`, `chown :kvm -R`, `chmod -R a+rX`, `chmod g+w`,
and two gcroot symlinks — `current` and `booted` — keyed on the *slot's*
directory, not on the attribute. `-u` is the same build in place. So a capsule's
whole binding to a nix artefact is **one symlink in its state directory**, and
the gcroots follow the slot rather than the flavour.

**The machine config is not in the image.** `declaredRunner` is a shell script
plus a ~1 KB JSON:

```json
"machine-config": { "mem_size_mib": 8192, "smt": true, "vcpu_count": 4 },
"drives": [ { "drive_id": "store", "path_on_host": "/nix/store/…-microvm-store-disk.erofs" } ]
```

and the volume's size is a `truncate -s 32768M` in the script, applied only when
the image file does not yet exist (`microvm-run`, lines 13-14 on this host,
right after a `chattr +C` that is a no-op on ext4). So the *hypervisor*
configuration is a kilobyte beside a 3.0 GiB erofs that the runner merely
references — and a volume's declared size is fixed at first boot, so D3's
`resize` is delete and recreate rather than a verb of its own.

**`mem` is runner-only — settled, and it settled less than it was asked to.**
This was the one inferred claim in this file. The check was an eval comparing
`system.build.toplevel.drvPath` with and without a forced `microvm.mem`
(`lib.mkForce`, since `vm/capsule.nix` sets it from `target.sizes.mem` at normal
priority and a bare value conflicts). **Identical paths.** So two capsules
declared at 6144 and 8192 share one erofs, §9 step 3's drop is free of the image,
and a class varying only `mem` costs the ~1 KB of JSON above.

**What that does not settle is `vcpu`, and the eval could not have told you.**
Read from source instead: `vm/capsule.nix` does `inherit (target.sizes) vcpu
mem`; `mem` reaches `microvm.mem` and stops, but `target.nix` renders
`jobs = ${toString sizes.vcpu}` into `guestConfig`'s cargo config, which is a
store file **in the closure**. So for this target a vCPU change is class 2 and a
`microvm -u` per slot. Forcing the *option* `microvm.vcpu` leaves
`target.sizes.vcpu` untouched, so that guest config never moves and the same eval
returns identical paths for a coupling that is real — the probe confirming the
claim it was meant to falsify ([item 27](./ledger/027-a-class-is-not-always-a-kilobyte.md)).

So the rule is narrower than "classes cost a kilobyte": **a class is a kilobyte
only over reservations the assigned profile derives nothing from**, which is a
predicate over a *(class, profile)* pair rather than a global fact. The coupling
itself is the guinea-pig capability working — *render static guest config from
the declared reservation* — not a leak, so the fix is the cost model rather than
the derivation.

**Upstream has a mode for "someone else owns this state directory".** Read from
source: `build()` refuses outright when a `toplevel` symlink is present — *"This
MicroVM is managed fully declaratively and cannot be updated manually"* — and
`microvm -l` reads that same link for its up-to-date comparison. So a program of
ours owning `current` can write `toplevel` too, and upstream's `-u` then refuses
rather than silently rebuilding `nixosConfigurations.<slot>`, which by that
point would be the wrong attribute.

Two things to check before leaning on that, and the second is the one that could
bite hard:

- what the declarative path actually writes into the directory, and whether the
  `microvm@` unit or its tap sibling needs anything from it beyond
  `current/bin/*` and `booted/`;
- **whether anything reconciles declaratively-managed VMs.** `toplevel` is how
  microvm.nix marks a VM as owned by `microvm.vms.<name>`, and `~/flakes`
  declares none — so a host-side reconciler that sees a marked state directory
  with no matching declaration is a plausible way to lose a volume. Read the
  host module's units before writing that symlink, not after.

## 6. The shape this suggests

Five nouns, each with one home. The point of the split is that only one of them
is a nix artefact.

| noun | what it is | lives | cost to change |
| --- | --- | --- | --- |
| **slot** | index → namespace, uplink /30, socket, units | `capsules.nix` | class 3, once |
| **flavour** | a tool set — the only irreducible per-target closure content | **composed**, not declared: the profile's floor plus the assignment's extras | class 2 to *add a fragment*; a symlink to *re-point* |
| **class** | machine config: mem, vcpu | the runner's JSON | ~1 KB per combination over `mem`; a 3.0 GiB image over `vcpu`, because this profile derives guest config from it (item 27) |
| **source** | where this host keeps the profile's repo | a host declaration, keyed by profile | class 3 — and never an assigner's to set |
| **assignment** | profile, policy, class, extras, base commit, purpose | `/var/lib/capsule/slot/<slot>/assignment.json` | run time, free unless the composition is unbuilt |
| **volume** | checkout, `$HOME`, caches, `target/`, **and its own size** | `/var/lib/microvms/<slot>` | verbs (D3); size fixed at creation |

Seven nouns, not five, and the two extra ones both came out of "target".
**Policy** — allowlist and ingestion bounds — has a different owner from a
project's
semantics and is what
[item 25](./ledger/025-assignment-is-a-perimeter-verb.md) is about. **Source** —
where this host keeps the repo — is not project state either: `/home/…/doctrine`
describes a host, and `path` already half-admits it by carrying two host-side
overrides where no other field has one. It is also the field an assigner must
never spell, since `capsule-provision` reads that repo as the human. Volume
size has come out of `class` on the same principle: §5 read it as a `truncate`
applied only at first boot, so a class carrying it could let an assignment
claim a size its disk was never created with. `class` is `mem` and `vcpu`;
storage is the volume's — and what a *project* needs, as against what a host
grants it, is a reservation rather than a deletion
([contract-assignment.md](./contract-assignment.md)).

The field-by-field version of all of this, and the ownership rule it rests on,
is [contract-assignment.md](./contract-assignment.md); where a flavour's tools
come from and how they compose is
[contract-flavour.md](./contract-flavour.md). Both are unbuilt and both were
written before D1, deliberately — see §9.

**Only the tool set has to be in the image.** Decomposing what is target-shaped
in the closure today: `toolsPackage` and `extraTools` are genuinely closure
inputs; the checkout directory name, `defaultBranch`, the `caches` environment,
`guestConfig`'s content, the motd, `commands`, `baseline` and `path` are all
*values the seed happens to read from the closure instead of from a file*; and
sizes are in the runner rather than the image, which is §5's one inferred claim
and §9's step 2. So the axis worth naming is not the
target but the **flavour**, and a target becomes host-side run-time state.

Two things a flavour must not inherit from today's single-target shape, both in
[contract-flavour.md](./contract-flavour.md). Its tools **need not come from the
repo being confined** — a shared tool repo serving a class of projects is one
input, one closure and one image for eight repos that export nothing, and
requiring each of them to grow a flake is requiring the wrong repo to change.
And a flavour is **not declared and selected at all — it is composed**, from a
floor the project states and extras the assigner adds, out of a fragment
vocabulary the host declares:

    flavour = compose(profile.floor, assignment.extras)

so the identity is the composition rather than a name someone typed. The extras
are the cross-project half and are expected to be broad and few — `agents`
(`claude`, `pi`, `rg`, `tree`, fileutils, shell) and `dev-facilities` (`neovim`,
`nushell`, `btop`) are the worked pair, wanted by nearly every slot and
therefore costing one image between them. The arithmetic runs the other way for
a fragment only one slot uses: distinct composition, its own 3.0 GiB. Collisions
are a build failure with an explicit `lib.hiPrio` override, which is nix's
answer rather than a new one — a silently shadowed toolchain is what exit 127 in
a guest looks like (NOTES item 23). And a composition nobody has built is a
build, so **whether `assign` may wait for one or must refuse is a per-host
declaration** — the dev/ranch split falling out of §0 again rather than being
chosen here.

That gives both modes from one mechanism, which is what §0 requires:

- **dev host** — a broad vocabulary, and a novel composition builds on demand
  with `assign` waiting for it. In practice nearly every slot lands on the same
  composition, so assignment is fully run time: doctrine can hand slot `d` a
  repo and a sha with no build at all.
- **ranch** — a narrow vocabulary per slot, and an unbuilt composition refused
  rather than built. Assignment is then *guaranteed* cheap, and pre-building the
  allowed compositions is a job upstream. Same mechanism, different declaration.

Changing what a slot runs is then a stop, a `nix build -o current`, and a start
— no `capsules.nix` edit, no host rebuild, no push. Adding a *fragment to the
vocabulary* is a rebuild, which is the right way round: rare and declared versus
frequent and cheap.

Three consequences to accept before any of it is built:

1. **`target.nix` splits into a profile and a policy, one of each per project,
   host-side.** The contract is unchanged — still nothing read *out of* the
   confined repo, still host-side and keyed by name (NOTES item 16) — but it
   becomes two documents with two owners rather than one file with fifteen
   fields (NOTES item 25). The profile is project semantics and is what an
   assigner may name freely; the policy is a control and is selected from a set
   the slot declares.

   **And the run-time interface is a validated document, not a nix file.**
   Authoring in nix and rendering to JSON in a directory is what this host will
   do, because nix is what it has and the profile is checked at build time for
   free. But a program reads the rendered document at run time, so a controller
   that never runs `nixos-rebuild` stays possible — which is the whole point of
   making a target run-time state. `perimeter/egress-allow.txt` is the precedent
   already in the tree: a plain file rather than a store path, for exactly this
   reason.
2. **The seed becomes assignment-driven.** An unassigned slot boots empty with
   no checkout, which is more honest than one hardcoded to doctrine. `capsule
   <slot> assign <target> [ref]` writes the record, pushes it, provisions,
   injects, baselines. The seed's remaining job is the generic part — the
   volume's skeleton and its ownership — and the target-shaped part (checkout
   directory, cache directories, `guestConfig` links) should be done **by the
   host over the channel that already exists**, not by a guest-side applier
   reading a pushed file. Same reasoning as everywhere else here: the host
   initiates, the guest stays dumb, and there is no new guest program to keep in
   step.
3. **The config payload must be refresh-always — but "always" means the pinned
   generation, not the latest document.** `guestConfig` is currently a *symlink
   into the store*, precisely so a stale copy cannot outlive the sizes it was
   rendered from (`vm/capsule.nix`). As a pushed payload it loses that unless
   the host re-pushes at every start — which restores the property and keeps the
   host the source. Payloads are write-if-absent by deliberate decision (NOTES
   item 22); this is a *derived* payload, and the distinction wants a field on
   the declaration rather than a change of policy. The identity payload below
   needs the same field, so it is one extension, not two.

   What the first draft got wrong is *which document* gets re-read. A
   **profile** is pinned at the assignment's generation, so editing a project's
   caches or its baseline does not silently change what a running capsule is
   doing with no verb run against it. A **policy** is live, because a tightening
   has to reach a running capsule without a re-assign. Two owners, two clocks;
   one field on the payload declaration says which
   ([contract-assignment.md](./contract-assignment.md), NOTES item 25).

4. **The four host programs bake the target into their store paths, and this is
   NOTES item 20 one level up.** `host/programs.nix` derives `guestRepo` from
   `target.guestPath`, and hands `baseline` its `command`, `workdir`,
   `recordDir` and `measure` from `target.nix`; `git-channel.nix` takes
   `defaultBranch` and `collectMaxPackBytes` the same way. One target makes that
   invisible. Two targets make it four programs per target — the exact shape of
   the bug that stood between N=1 and N=2, where a socket path baked into a
   store path meant a program per capsule. The fix rhymes too: those values
   arrive at run time from the assignment record, the way `--capsule` already
   does, and one store path goes on serving everything. **This is D7's first
   task, not a detail of it** — and it is worth doing even if flavours never
   happen, because it is the same coupling the repo has already decided against
   once.

**Identity falls out of the same payload.** A refresh-always `/work/.capsule`,
sourced by the guest's `interactiveShellInit` exactly as `.env` already is, lets
the prompt read `agent@delta:doctrine@a1b2c3`. Per-slot identity, one image,
nothing in the closure — L5 and NOTES item 21 without touching what makes one
image structural. It is not quite free: the sourcing line is a guest change
(class 2, once), and whether a `PS1` set there survives NixOS's own prompt
initialisation depends on ordering in `/etc/bashrc`, which wants checking rather
than assuming — the motd and a login banner are the fallback if it does not.

**The allowlist stays host-side.** Since target is now run time, the proxy
cannot read it from the guest's copy. Q1's answer: bind-mount a *directory* of
allowlists read-only into the proxy's namespace and have it select
`<dir>/<policy>.txt` at start, from the host's assignment record. Re-assigning a
slot is then a proxy restart, and L3 falls out for free.

**But that makes `assign` a perimeter-mutating verb, and the fix is the sixth
noun.** If the *project* names the allowlist, then whoever may hand a slot a
project may hand it a wider perimeter — the exposure is authority rather than
reach, since the guest still cannot see or touch the record. So the assignment
names a **policy** separately from a **profile**, and the set of policies a slot
may take is declared host-side per slot; `assign` selects within it or is
refused. A dev host declaring that set as "any" is §0's permissive mode falling
out of a declaration, which is what §0 requires of every mechanism here. NOTES
item 25, and `collectMaxPackBytes` is on the same side of that line as the
allowlist.

**Where classes must not go.** Class is machine config and belongs in the
runner. A *role* — worker, auditor: which allowlist, whether it may collect,
what it may be assigned — is policy and belongs in the record. A label like
`worker-highcpu-A` is one string over two axes; keep them separate underneath or
the runner starts carrying policy. And the slot id itself stays short: it is on
the wire as `cap-<id>` and IFNAMSIZ is 15, so `capsules.nix` refuses anything
over 11 characters. The id is `a`…`j`; the composite is a rendered label in
status and in the prompt, never a namespace name.

**What stays unavoidable:** one flake input literal per repo whose packages a
flavour composes. An input url cannot be computed (NOTES item 16). The count
follows the number of *tool sources* rather than the number of projects, which
is the point: eight projects on one shared base are one input, and it is the
only place a repo name appears.

## 7. Directions

- **D1 — the assignment record. Built and run** ([status](./status.md),
  [item 29](./ledger/029-the-record-is-front-end-written.md)) — at
  `/var/lib/capsule/slot/<slot>/`, and the field list
  is [contract-assignment.md](./contract-assignment.md)'s rather than this
  file's. Written by `capsule`, read by status, pushed to the guest as identity.
  It is what makes an abstract slot legible, and every other direction here
  either writes to it or reads from it. Four properties that are cheap now and
  expensive to retrofit, so they are part of D1 and not a later tidy:

  - **desired state and observations are separate objects** — otherwise nothing
    can answer *is this slot doing what it was told*;
  - **every reference is a name plus a resolved identity**, and the resolved one
    is what is used: `base.ref`/`base.oid`, the profile name beside the profile
    *bytes*, the fragment names beside the resolved *store path*. A digest is
    verification; **pinning also requires retention**, so the record keeps the
    profile snapshot and a gcroot keeps the image. Otherwise "reapply the pinned
    generation" is really "re-resolve these names and hope";
  - each slot carries a **generation** integer, which is what makes a late
    answer refusable once anything detached exists (D6);
  - the serialization carries a **`schema` discriminator**, even though the
    design is deliberately unversioned — persistent state outlives the binary
    that wrote it, and a number on the bytes promises nothing about the
    contract.
- **D2 — the pool.** Declare `a`…`j` once, and make assignment run-time state.
  Turns S1, S4 and S10 from rebuilds into commands. The cost is not idle
  namespaces — nothing starts at boot, so an unassigned slot is a declaration
  and nothing else — it is L12: on the first start of *any* capsule the guard
  pulled in all ten, and any one of them that would not come up denied the whole
  host. That was L12, and it is closed
  ([item 30](./ledger/030-a-pool-audits-what-exists.md)) — so what is left of D2
  is the declaration and the run-time assignment, with nothing standing in front
  of them. **The declaration has landed**: `capsules.nix` says `a`…`j`, the eval
  cost of it is 3% of a module eval
  ([probes](./probes.md#what-ten-declared-slots-cost)), and the at-rest cost
  needs a switch. What is left of D2 is the run-time half — `policy` as a field
  an assignment selects from a declared set, rather than one allowlist for the
  fleet.
- **D3 — volume verbs.** `capsule <slot> volume {df,reset,reset-home,clone-from
  <m>}`, host-side, refusing while the VM runs. `reset` is S4 without the `rm
  -rf`; `clone-from` is S5, and on ext4 it is a sparse copy of ~1.1 GiB —
  seconds against doctrine's 109 s, and worth much less on a target whose
  baseline is 3 s (L8). No `resize`: the size is set at first boot (§5). Also
  the guard on a flavour swap: a volume carrying one flavour's caches is silent
  garbage under another, so `assign` refuses a flavour change on a non-clean
  volume and offers `--reset`.
- **D4 — clone semantics, decided rather than inherited.** A cloned volume
  carries the source's ssh host keys, injected credentials and `.env`. Scrub by
  default, `--identity` to keep — dev convenience is one flag, the ranch default
  is the safe one.

  **The rule underneath is a trust boundary, not a cache-compatibility
  problem.** A volume also carries the previous assignment's caches and build
  tree, and under a new project, flavour or policy those are not stale garbage —
  they are *input supplied by a different principal*, and a build that reads
  them is a build the new owner did not specify. So reuse across a change of
  project, flavour or policy ownership is refused on a non-clean volume, with
  `--reset` as the answer, and a dev host may waive that by declaration. Stating
  it this way rather than as "the caches would be useless" is what makes the
  ranch default fall out instead of being argued for twice.

  And clone from a *base* rather than from a worked-in capsule:
  a slot is a valid clone source while it is `baselined` and not yet `dirty`,
  which is Q3's state model — `unassigned → provisioned(sha) → baselined(sha) →
  dirty`. The mechanism belongs here (worktree dirty, `HEAD != base sha`,
  `$HOME` touched since baseline, or an interactive session opened); the
  *policy* about what may be reused is doctrine's.
- **D5 — status answers the steering questions. Built and run**, and built
  *before* D1 because the guest round trip is what settles where `base.oid` comes
  from. Add columns fed by the ssh
  round trip `answers` already pays for: base sha, dirty/ahead, `df /work`, last
  baseline verdict and age, current-versus-peak memory — the last because the
  ratchet means a capsule holds its high-water until stopped, so `stop` is a
  resource verb and a human needs to know which idle slot to reap. Keep the
  existing discipline — no root, bounded, a dead guest is a row and not a hang —
  which argues for one guest-side script returning one line rather than five ssh
  calls per capsule. One caveat on the baseline column: read the *record*, never
  the exit status. The reason is no longer a live bug — item 24's login-shell fix
  has shipped — but it is the same reason: the record on the volume was right
  throughout the period the exit status was wrong, because `capsule-baseline`
  writes it before the shell that runs it can lose the status
  ([status](./status.md), NOTES item 24). That is the property the column should
  inherit, and it does not depend on the bug still existing.
- **D6 — detached agent sessions.** Generalise `host/baseline.nix`'s pattern
  with a pty: a multiplexer in the guest closure and `capsule <slot> attach`.
  What makes N > 2 workable for a human, and independent of everything above.
- **D7 — flavours.** §6's split. A second target *is* real (L1), so what this
  now waits on is wanting two of them **at once**; a switch is already a branch.
  Its first task is §6's consequence 4 — the four programs' target-shaped
  values, of which L13 is the one with no override at all — and nothing above
  forecloses it.

  **The four programs are the start of the inventory, not the whole of it.** The
  guest image also knows the project's name, its checkout path, its branch, its
  cache directories, its `guestConfig`, its motd and `commands`, its sizes and
  its tool set — and only the last is irreducibly a flavour's. Three
  generalisations make most of the rest disappear rather than become
  parameters, which is the cheaper move and is worth doing even before flavours:

  - **the checkout goes at a generic path**, not `<volumePath>/<name>` —
    `target.guestPath`'s derivation from `name` is a courtesy that costs a
    project name in the closure, and the display name belongs in the identity
    payload where the prompt already wants it;
  - **caches go at a derived path keyed by the env var**, so `caches` becomes a
    list of names rather than a map to directories. Strictly fewer degrees of
    freedom for the same capability, and `cachePaths` still derives;
  - **run records go beside them under a generic directory**, which is what
    `capsule-baseline`'s `recordDir` already is in spirit — beside the checkout,
    never inside it.

  What is left after that is a tool closure and a handful of values, which is
  what §6 claims and this is the check on the claim.

## 8. Questions a second project will raise

Not answerable from doctrine, and worth asking before the first one arrives:

- **Does it need a service to test against?** A database or a queue must be in
  the guest closure or nowhere ([item 4](./ledger/004-live-postgres.md), open) —
  and the guest closure is this repo's, so a target has no way to declare "run
  postgres". The generic capability would be *target-declared guest services*,
  and it does not exist. Under §6 it would be a property of a flavour.
- **Does it have a flake at all?** `toolsPackage = null` degrades to
  `extraTools` from this repo's nixpkgs and loses the no-drift property — and
  the second target found that for many repos that path is **structurally
  unavailable**, not merely worse: `extraTools` is bare nixpkgs attr names, so a
  tool set containing a `python3.withPackages (…)` has no name to give it. A
  target exports a package or it is not a target; `extraTools` is a supplement,
  never a substitute (NOTES item 23). A non-nix project is still the real test
  of the degraded path — and the answer it wants is not a better absent path but
  a tool set from somewhere other than the project
  ([contract-flavour.md](./contract-flavour.md)), which is the case that makes
  composition load-bearing rather than convenient.
- **What does its dev loop look like from outside?** S9 stops being a nicety for
  anything web-shaped, and doctrine — with `just web-build` — is already that
  shape.
- **How big is its checkout and its build tree?** No reflink, a 32 GiB volume
  declared per slot, and the host's remaining headroom in
  [probes](./probes.md#figures). Disk is the fleet's real ceiling — and the
  spread is wide enough to matter: doctrine's baseline leaves ~1.1 GiB on the
  volume and panopticon's ~105 MiB, a factor of twelve for the same verb.
- **Where do its secrets come from?** `setup.nix` is a host-wide declaration,
  not a per-target one. Two projects with different API keys share one payload
  list.
- **Does it tolerate N concurrent sessions on one credential?** NOTES item 2,
  still open, and the fleet is what makes it literal.
- **Who may assign which repo to which slot?** Trivial on a dev machine, where
  every repo is the human's. On a ranch it is the whole question, and it lands
  on the assignment record — which is the argument for that record being
  host-side and authoritative rather than a convenience. The half of it that is
  answerable now, because it is a design constraint rather than a policy: an
  assigner is free in profile, base and purpose, and confined to a declared set
  in policy, flavour and class (NOTES item 25,
  [contract-assignment.md](./contract-assignment.md)).

## 9. Order of work

1. **§0's local flake input.** One line at the rebuild, and it takes the push
   out of class 3 — which every step below churns.
2. **Settle §5's inference, before anything is built on it.** One eval, already
   written out in §5, comparing `toplevel.drvPath` with and without a changed
   `microvm.mem`. Identical paths means the mem drop below is free of the image
   and a class costs a kilobyte; different paths means the drop is a 3.0 GiB
   rebuild plus `microvm -u` per slot, and §6's table is wrong about where
   `class` lives. It is the cheapest step here and the one the two after it
   depend on.
3. **Rename to slots**, and drop `sizes.mem` to 6144 in the same breath, since
   both need the same rebuild. The two existing capsules are expendable, so
   recreate rather than migrate — a `mv` of the state directory would also want
   its two gcroot symlinks re-pointed, and the volumes are worth less than the
   care. Take a per-unit `memory.peak` off the first cold build afterwards,
   because §0's arithmetic is the old ceiling's figures reasoned forward — and
   that peak is now taken, and it withdrew the arithmetic rather than confirming
   it (§0, [probes](./probes.md#the-first-cold-build-at-a-6144-ceiling)). What the
   rename actually touches,
   beyond `capsules.nix`:
   - **the devshell path's assumptions.** `vm <name>` resolves a flake
     attribute,
     and `vm-stop` asks the guest to halt only when the name is literally
     `capsule` — one link, one guest, so any other name is reaped rather than
     asked. Both need to follow the rename or the devshell shape quietly becomes
     a power cut.
   - **every `just` recipe's default**, which is the literal string `capsule` in
     fifteen places rather than `capsules.default`. That duplication is invisible
     while the default capsule is named `capsule`, and wrong the moment it is
     not. Thread the value.
   - **`capsules.default` itself**, which stops meaning much once slots are
     abstract: defaulting to slot `a` is a habit, not a choice. Worth deciding
     whether the default becomes "the only running capsule, else refuse" —
     better for a fleet, but it makes a program's target depend on host state,
     which is the kind of thing this repo has refused before (NOTES item 20).
4. **Fix the contracts, before D1 writes a record.** The artifacts are
   [contract-assignment.md](./contract-assignment.md) and
   [contract-flavour.md](./contract-flavour.md), plus the ownership column in
   [contract-target.md](./contract-target.md). The reason for the ordering is
   narrow and worth stating: a persistent record is the most likely place for
   today's single-target assumptions to survive a transition meant to remove
   them, and the assumption that matters most is the one that fuses a project
   with its perimeter (NOTES item 25). Design cost only — no build, no
   mechanism, and it deliberately stops short of an execution contract, which is
   [contract-doctrine.md](./contract-doctrine.md) Role 3's to say why.
5. **D1 + D5, the record and the columns.** Cheapest useful pair, and a fleet
   has to be legible before it can be administered.
6. **D3 + D4, volume verbs and clone semantics.** S4 and S5 are the two most
   frequent administrative actions and one of them is currently a hand-typed
   `rm -rf`.
7. **D6, detached sessions.** When N > 2 stops being a probe and starts being a
   Tuesday.
8. **D7 + D2's dynamic half, flavours and targets as data.** Once two projects
   are wanted **at once** — one at a time already works, and the port cost is a
   diff rather than an argument (L1, NOTES item 23). It starts with the four
   programs' target-shaped values (§6.4) and L13, since neither flavours nor
   run-time assignment can ship while a program spells the branch.
