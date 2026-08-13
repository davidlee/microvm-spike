# Spike — cloud-hypervisor as a second VMM

**Scoping, not a commitment, and nothing here has been built or run.**
[status.md](./status.md) owns the present tense and
[probes.md](./probes.md) owns every figure — this file is what the swap would
touch, what it would buy, and what order to find out in. It resolves nothing in
[item 14](./ledger/014-hypervisor-choice.md), which has said "worth a branch"
since before there was a fleet; what it adds is the coupling, the price and a
first step that costs nothing.

## Why this, and why now

**Not shares.** [item 14](./ledger/014-hypervisor-choice.md) and
[eval-hypervisors.md](./eval-hypervisors.md) both frame cloud-hypervisor (CH) as
the escape from firecracker's no-shares floor, and that framing is now the
weaker half of the case — the bootstrap tarball is gone, secrets ride ssh
([item 22](./ledger/022-secrets-at-start.md)), and the git channel is
host-initiated in both directions ([item 18](./ledger/018-git-channel-direction.md)).
The problems shares would have solved have been solved without them.

**Memory is the case.** A built slot holds ~6.1 GiB of `anon` until it is
stopped, at *either* ceiling, because the VMM keeps every page the build ever
touched and firecracker has neither a balloon nor free-page reporting
([item 12](./ledger/012-no-resource-ceiling.md),
[probes](./probes.md#the-first-cold-build-at-a-6144-ceiling)). That ratchet is
what decides how many hot slots fit, which is the open question standing in front
of the pool ([plan-d](./plan-d-fleet.md) §0, D2). firecracker's runner *throws*
on `balloon`, `initialBalloonMem`, `hotplugMem` and `hotpluggedMem`
(`lib/runners/firecracker.nix:91-98`); CH's passes a balloon with
`free_page_reporting = "on"` and optional `deflate_on_oom`, plus virtio-mem
hotplug (`lib/runners/cloud-hypervisor.nix:94-108`, `:59-92`). So CH is the only
lever in reach that could make a stop stop being the only thing that returns
memory.

Two lesser prizes, both untested here: `mergeable = "on"` — KSM, which CH sets
whenever no virtiofs share is configured (`cloud-hypervisor.nix:79-81`) — is
cross-slot page dedup, and one guest image makes the pages plausibly identical;
and a real ACPI shutdown, which would delete a whole class of firecracker
workaround (below).

**And a hazard, which is the thing to write down before anything is built.**
Half this repo's rationale rests on *no host directory can ever be mounted into
the guest* being a **constraint** (CLAUDE.md, "Firecracker constraints"). Under
CH it becomes a **policy**, because `--fs` exists. Nothing dangles if the
refusal is written down and kept; everything dangles quietly if it is not. A CH
capsule declares no shares, and that is a decision this repo owns, not an
absence it inherits.

## What is actually coupled to firecracker

Evidence first: this is a read of `host/`, `probe/`, `vm/` and microvm.nix's own
source, not a guess. microvm.nix paths below are its store checkout
(`lib/runners/*.nix`, `nixos-modules/microvm/*.nix`).

| thing | coupled? | why |
| --- | --- | --- |
| `perimeter/` | no | knows no hypervisor by construction (CLAUDE.md invariant) |
| `host/netns.nix`, guard, `guardCases` | no | namespaces and nft; a VMM is a pid in a namespace either way |
| ssh relay, git channel, record, `host/cli.nix` | no | sockets and `transport`, no VMM anywhere in them |
| `host/programs.nix`'s four programs | no | ssh over the relay |
| [item 11](./ledger/011-host-side-runs-as-you.md) (runs as you) | no | CH also `throw`s on `user != null` (`cloud-hypervisor.nix:204`) |
| identity by namespace | no | runner is `exec -a "microvm@${hostName}"` for every VMM (`lib/runner.nix:29`) |
| `vm/common.nix:3` | **yes** | the one word |
| the guest image | **no, at the price of one initrd module** — measured, below | microvm.nix adds initrd `i8042` only for firecracker (`nixos-modules/microvm/system.nix:19-24`) |
| `host/halt.nix` | **yes, entirely** | it exists because firecracker has no ACPI |
| `probe/harness.sh`'s teardown | **yes** | `halt_guest` encodes the same dance (`:316-353`) |
| a hand-made tap's flags | **yes** — found by run 1 | CH wants `multi_queue` at `vcpu > 1`; microvm.nix's own `tap-up` already reads that off the runner, so only probes are affected |
| `flake.nix:1048`, doc strings | cosmetic | `pkgs.firecracker` in the devshell |

Three of those want spelling out.

### The guest image does not change, once one initrd module is unconditional

microvm.nix puts `i8042` in `boot.initrd.kernelModules` for firecracker only
(`nixos-modules/microvm/system.nix:19-24`), so the initrd — and therefore
`toplevel`, and therefore the erofs — differs by that one module. **That is the
whole guest-side coupling**: `just hypervisor-delta` (Phase 0, run below) says
image-affecting as committed and runner-only with the module forced on both
sides. So a CH slot is `mem`-shaped rather than `vcpu`-shaped
([item 27](./ledger/027-a-class-is-not-always-a-kilobyte.md)) — but on a
precondition, not for free: `i8042` has to be in the initrd unconditionally,
which is a line in `vm/common.nix` and a claim that wants restating whenever the
lock moves.

### The stop path inverts, and mostly by deletion

`host/halt.nix` is a monument to one firecracker fact: its only shutdown signal
is `SendCtrlAltDel` into an i8042 stub whose driver refuses to attach, so a stop
has to be an ssh **reboot** with `reboot=k` turning the guest's reset into a VMM
exit (CLAUDE.md; `firecracker.nix:28` is where `reboot=k` and the `i8042.*`
params come from). CH's runner sets `reboot=t panic=-1`
(`cloud-hypervisor.nix:39`) and its `shutdownCommand` is a real ACPI power
button plus `waitpid $MAINPID` (`:300-312`). So on a CH slot, microvm.nix's own
shutdown should work, and with it the host-owned stop key, `host/services.nix`'s
`stopKeyCheck`, the `ExecStop` override and the refusal-to-start-without-a-stop-key
all become firecracker-specific baggage.

**Should. Unverified, and it is the first thing Phase 1 asks**, because the
failure mode is quiet: what a guest `reboot` does to CH — exit, or reset in
place and boot again — decides whether `capsule-halt` is safe to point at a CH
slot at all.

If both hypervisors are to be supported, the shape is the one this repo already
uses twice: the stop becomes a **fragment injected at the call site**, like
`transport` in the four host programs
([item 20](./ledger/020-which-capsule-a-program-means.md)) and `tools` in the
guard. One program, two instantiations. What must not happen is a program that
probes which VMM it is talking to — that bakes both in, which is exactly the
mistake item 20 records.

### The console observation may not survive

`boot.kernelModules = ["i8042" "atkbd"]` (`vm/common.nix:32`) is what makes
Enter work in a TUI on the serial console, A/B'd, with **no known mechanism**
(CLAUDE.md). CH emulates no i8042 at all. So the fix may simply not apply, and
since nobody knows why it works there is nothing to reason from. ssh is the
documented way to run an agent, so this is a papercut and not a blocker — but it
is a regression to expect rather than to be surprised by.

## How much slot `a` gets in the way

`a` is production ([status.md](./status.md)), so this is a constraint on the
order of work rather than a footnote.

- **Phase 0: not at all.** Eval only. Working-tree edits reach the host through
  neither channel: `~/flakes` overrides this input at *committed* HEAD
  ([plan-d](./plan-d-fleet.md) §9 step 1), and a running slot tracks
  `/var/lib/microvms/<name>/current`, which moves only on `microvm -u`.
- **Phases 1-2: one refusal stands in the way, and it is stale.**
  `any_vm_running` is `pgrep -f "microvm@$1"` (`probe/harness.sh:249`), called by
  `netns-boot.sh:77` and three siblings — and one image means `a` *is*
  `microvm@capsule` in the process table. What that check guards is "the devshell
  shape and a probe's shape must never be up at once", which the two checks
  bracketing it ask better and more narrowly: a root-namespace tap
  (`netns-boot.sh:72`) and a leftover probe namespace (`:81`). Every other
  question the harness asks is already namespace-scoped (`vm_pids`, `vm_running`,
  `kill_vm`). Narrowing it is the same correction as the `pkill -f` one and wants
  its own ledger item — it is a safety refusal, so it is a decision, not a tidy-up.
- **The guard cannot be tripped by a probe**, which was the risk worth checking:
  limb one iterates *declared* slots (`host/guard.nix:88`) and limb two keys on
  `microvm@<declared>.service` (`host/netns.nix:275-278`), so a hand-started VMM
  in `cap-capsule` is invisible to both and cannot take `proxy-a`'s egress down
  with it.
- **Phases 1-2 still cost `a` something**: build contention against its workload,
  and RAM. State the memory cap Phase 2 will churn before running it, and take
  the host's free figure at both ends.
- **Phase 3 blocks on a window.** Declaring a CH slot changes the guard's
  `declared` array, so the guard gets a new store path, so a switch restarts it —
  and every proxy `BindsTo` the guard, so `proxy-a` restarts and `a`'s egress
  blips mid-session. The devshell path is not an escape: `capsule-host` refuses
  while a `capsule-proxy-*` unit is active, deliberately (CLAUDE.md).
- **Branch, don't commit to `main`.** `git+file:` at committed HEAD means
  anything on `main` ships at the next unrelated `system-switch`. Same reason
  `second-target` is a branch.

## Staged plan

Each phase answers one question and is priced by what it can break. Stop after
any of them: the value is front-loaded, since Phase 0 gates the cost model and
Phase 2 holds the finding.

**Phase 0 — is hypervisor runner-only? ~~Eval, no build, no host contact.~~
Run: yes, once `i8042` is unconditional.** Detail and result below. It gated
everything: a second image would have made a CH slot per-slot divergence rather
than a runner swap, which is a Plan D question
([item 21](./ledger/021-declared-capsule-flake-attribute.md)) and not a spike's
to settle. It is a runner swap, so the rest of this plan is cheap.

**Phase 1 — does it boot, and how does it stop?** A probe in the harness's own
namespace (`cap-capsule`), shaped like `probe/netns-boot.sh`: firecracker's
assertions with the VMM swapped — guest answers ssh inside the namespace, tap and
guest unreachable from the root namespace — plus the stop question asked three
ways (guest `reboot`, guest `poweroff`, `vm.power-button` over the API socket),
recording for each whether the VMM exits and whether the volume was unmounted
first. Needs the refusal above narrowed. Touches no declared slot, no unit, no
perimeter.

### Run 1 — 2026-08-14, and it died before the guest printed a line

`probe-ch-boot`, 6 passed / 6 failed, and the failure is a finding rather than a
setback: cloud-hypervisor exited 2.9 ms in with
`OpenTap(MultiQueueNoTapSupport)`. Its runner sets `tapMultiQueue = vcpu > 1`
(`lib/runners/cloud-hypervisor.nix:103`) and opens the tap with one queue per
vCPU; the harness creates taps single-queue, because that is all firecracker has
ever wanted — and CLAUDE.md's own EBUSY note is the same fact from the other
side. **microvm.nix already handles this**, reading it off
`declaredRunner.passthru.tapMultiQueue` in its `tap-up`
(`nixos-modules/microvm/interfaces.nix:11-13`), so the module path would create
the right tap and it is only a probe making taps by hand that has to be told.
`ns_up` takes the flags as an argument now, for the reason every seam here is an
argument rather than a lookup (NOTES item 20).

**The more useful half is what the dead VMM did to the probe.** With nothing
running, `vmm_gone` answered instantly, so *the power-button check passed*, the
reboot observation reported an exit, and three figures timed an absence —
including "boot to ssh: 38.56 s", which was the wait's own patience wearing a
boot's name, the exact mistake `halt_guest` was written to stop making. A stage
whose subject is missing agrees with whatever it is asked. Stage 3 now asserts a
live VMM before it asks anything, skips the rest when there is none, and records
a never-answered boot as a wait rather than as a figure.

Nothing about the two claims under test survived run 1: the image is unproven
under CH, and so is every stop. Run 2 is the first that can say.

**Phase 2 — does the ratchet break?** The finding this spike is for. Balloon on
with `free_page_reporting`, a guest that touches N GiB and frees it, and the
VMM's `anon` read before, during and after — against
[item 12](./ledger/012-no-resource-ceiling.md)'s firecracker figure. It needs no
target workload, so no proxy, no provision, no egress and no git channel: a
synthetic allocation is a *better* instrument here, because the question is about
the VMM and not about a build. Assert both directions, as a probe must: memory
that never grows is a broken instrument, not a thrifty VMM.

**Phase 3 — a comparable real run.** `capsule <slot> setup <ref>` on a CH slot
against `a`'s 110 s / ~6.1 GiB
([probes](./probes.md#the-first-cold-build-at-a-6144-ceiling)). This is the only
phase that needs a host rebuild, a declared slot and therefore a window, and the
only one whose answer is directly comparable to what this repo already quotes.
Do not start it until Phase 0 has said what a CH slot costs to declare.

**If it graduates from spike to supported option**, the work beyond Phase 3 is:
hypervisor becomes a declared value rather than a constant in `vm/common.nix`;
the stop becomes an injected fragment with two instantiations; `stopKeyCheck` and
the start-time stop-key refusal become conditional on the firecracker path;
`hostModuleUnits` gains the pairing assertion for whichever new
program/permission pair appears; the harness takes its teardown as an argument
the way the guard takes `tools`; `docs/threat-model.md` gains CH's device model
and the **explicit** shares refusal; and item 14 stops saying "open option".

## Phase 0 in detail

Everything below is an eval or a grep. Nothing builds, nothing needs root,
nothing touches a running slot. Expect under an hour.

### The question, stated so it can fail

*Does swapping `microvm.hypervisor` to `cloud-hypervisor` change the guest
image?* Two acceptable answers and one trap:

- **Runner-only** — `toplevel` and the store disk are the same derivation, so a
  CH slot costs a runner (~KB, like `mem`) and Phase 3 is cheap.
- **Image-affecting** — a second erofs, a `microvm -u` per slot, and a per-slot
  divergence from the one-image design that Plan D has to want, not a spike.
- **The trap** ([item 27](./ledger/027-a-class-is-not-always-a-kilobyte.md)):
  identical drvPaths prove the *forced* option did not reach the closure, not
  that the hypervisor cannot. The eval is paired with a grep over guest-side
  consumers, and the grep is what would have caught `vcpu`.

### Steps 1 and 2 — the drvPath A/B, and the neutralised repeat

**Built as `just hypervisor-delta`**, because this is a question that takes more
than one command to answer, which is what the justfile is for. It evaluates four
derivations either side of `microvm.hypervisor` — `toplevel`, `initialRamdisk`,
`microvm.storeDisk`, `microvm.declaredRunner` — twice: as committed, and again
with `boot.initrd.kernelModules = [ "i8042" ]` forced on both sides. `mkForce`,
since `vm/common.nix` already defines the hypervisor and two ordinary
definitions are a conflict rather than an override; `extendModules` on **both**
sides, so the extension itself cannot be the difference; one eval per side
rather than one per attribute, because each is a whole system evaluation and
this host has a capsule working in it.

### Result — run 2026-08-13, ~17 s, nothing built

```
== as committed                     toplevel/initrd/store/runner all differ  → image-affecting
== with initrd i8042 forced         toplevel/initrd/store same, runner differs → runner-only
```

And the follow-up that prices the precondition: forcing `i8042` into the
*firecracker* side returns `hsfr1q3…-microvm-store-disk.erofs.drv`, **the same
store disk as committed**. The list merges and the duplicate collapses.

Three things follow.

- **The one initrd module is the entire guest-side coupling.** Nothing else in
  the guest closure reads the hypervisor, which is what step 3's grep predicted
  and is now measured rather than argued.
- **Making it unconditional is free for firecracker** — same erofs, so no
  rebuild, no `microvm -u`, and nothing to do to a running slot. That was the
  open risk in the precondition and it is closed.
- **A CH slot would share the exact image `a` runs.** The swap costs one runner
  derivation. So the fleet's one-image property
  ([item 21](./ledger/021-declared-capsule-flake-attribute.md)) survives a second
  hypervisor, which is the opposite of what `vcpu` did to per-slot sizing
  ([item 27](./ledger/027-a-class-is-not-always-a-kilobyte.md)).

Not proven by this, and worth being explicit: **that the image boots under CH**.
Identical bytes and a bootable guest are different claims — the initrd carries
no `i8042` driver that CH can bind, and nothing here has started a VMM. That is
Phase 1's first assertion.

### Step 3 — the grep the drvPaths cannot replace *(done, and it agrees)*

```
grep -rn 'hypervisor' <microvm.nix source>/nixos-modules/microvm/
```

Known guest-side consumers as of the pinned revision
(`71beea0076cd46dafcee97a5a2e7d00cbba5bd2f`), all read while writing this file:
`system.nix:19-24` (the initrd `i8042`), `optimization.nix:25-31` (systemd
initrd — lists both hypervisors, so no delta), `asserts.nix:129-133` (CH-only
assertion, no closure effect), `rosetta.nix` (vfkit), `vsock-ssh.nix` (docs).
Re-run the grep rather than trusting this list: it is true of one revision, and
the lock moves.

### Step 4 — three cheap facts to have before Phase 1 *(outstanding — this is what is left of Phase 0)*

- **CH's version and whether it is cached**, since a from-source VMM build
  competes with `a`:
  `nix eval --raw .#nixosConfigurations.capsule --apply 'c: (c.extendModules { modules = [{ microvm.hypervisor = "cloud-hypervisor"; }]; }).config.microvm.cloud-hypervisor.package.version'`,
  then `nix path-info --store https://cache.nixos.org <drv>^out` on the package
  to see whether the binary cache has it. microvm.nix's own cache is already a
  substituter here (`flake.nix:4`).
- **Whether the guest kernel has the balloon**, because Phase 2 is worthless
  without it: `CONFIG_VIRTIO_BALLOON` and `CONFIG_PAGE_REPORTING` in the kernel
  the capsule already runs. Read the config out of the kernel derivation, not out
  of a running guest — `a` is not to be logged into for this.
- **What `--seccomp true` and `--watchdog` mean for the threat model.** Both are
  passed unconditionally by the runner (`cloud-hypervisor.nix:211-213`). Note
  them; do not credit them until something reads what the seccomp profile
  actually allows.

### What Phase 0 produced

- [item 14](./ledger/014-hypervisor-choice.md) amended: "a one-word switch" is
  confirmed *with a precondition*, which is a better sentence than the one it
  replaces.
- No row in [probes.md](./probes.md). Two equal drvPaths are a finding for the
  ledger, not a measurement — nothing was built and nothing was timed.
- Go for Phase 1, and a price for Phase 3: one runner, no image.

Nothing in [status.md](./status.md) yet — an eval is not a state this repo is
in. Phase 1 is the first thing that would change that.

### Traps carried in from elsewhere

- **Do not embed a store path in an eval's output.** `builtins.seq` on an
  outPath evaluates the derivation; the string *of* one turns an eval into a
  build (CLAUDE.md, and the reason `hostModuleUnits` prints names).
- **`nix eval` is lazy.** A comparison that never forces both sides compares
  nothing. `--raw` on a drvPath forces it; anything cleverer needs care.
- **An edited program on `PATH` is the old store path** — irrelevant to a pure
  eval, but it is the first thing to suspect the moment Phase 1 starts running
  built things (CLAUDE.md).
- **`just check` does not evaluate** and `just units` evaluates only the host
  module. Neither of them will notice anything this phase does; that is exactly
  why the answer has to be written down rather than left to a check.
