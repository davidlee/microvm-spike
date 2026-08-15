# NOTES item 49 — who owns a state directory, and the read nobody has taken

*State: **both reads taken, the failure they found is not the one this item was
written about, and the constraint that replaces it is asserted rather than
asked for — built, unswitched.** Nothing reconciles, so the feared loss of a
volume does not exist in the pinned microvm.nix; what does exist is an
**overwrite at activation**, and the `toplevel` marker this item was reaching for
does not defend against it. D3 and D7 are ungated.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What was read, and it is genuinely useful

`microvm -c` is ten lines ([Plan D](../plan-d-fleet.md) §5, read from source): it
writes the flake ref to a file, builds
`…#nixosConfigurations.<name>.config.microvm.declaredRunner` into `current`, moves
the directory into `/var/lib/microvms/<name>`, and leaves two gcroot symlinks —
`current` and `booted` — **keyed on the slot's directory rather than on the flake
attribute**. So a capsule's whole binding to a nix artefact is one symlink, which
is what makes [Plan D](../plan-d-fleet.md) §6 affordable: changing what a slot
runs is a stop, a `nix build -o current`, and a start.

Upstream has a mode for exactly that situation. `build()` refuses outright when a
`toplevel` symlink is present — *"This MicroVM is managed fully declaratively and
cannot be updated manually"* — and `microvm -l` reads the same link for its
up-to-date comparison. So a program of ours that owns `current` can write
`toplevel` as well, and upstream's `-u` then **refuses** instead of silently
rebuilding `nixosConfigurations.<slot>`.

That refusal is worth having for a reason that does not exist yet.
`nixosConfigurations.<slot>` is the *right* attribute today — `capsules.nix`
declares each slot and `-u` rebuilds what the slot is
([item 21](./021-declared-capsule-flake-attribute.md)). It becomes the **wrong**
one the moment `current` is a composition somebody chose (D7), at which point a
`microvm -u` reverts a slot to its declaration with no error and no diff. That is
the failure mode the marker prevents, and it is invisible until the day it is not.

## The first read: what the declarative path writes, and it is four lines

`nixos-modules/host/default.nix`'s `install-microvm-<name>.service` — a oneshot,
`wantedBy = microvms.target`, `partOf = microvm@<name>.service`, `before` all
five siblings — is the whole of it:

    mkdir -p ${stateDir}/${name}
    ln -sTf ${runner} current
    chown -h microvm:kvm . current
    # fully-declarative:  ln -sTf ${toplevel} toplevel
    # flake-based:        echo '<flake>' > flake

**`booted` is not its business.** `microvm-set-booted@` writes it at start
(`rm -f booted; ln -s $(readlink current) booted`) and removes it at `ExecStop`.
So the demand surface of the units is exactly what this item guessed and nothing
more: `current/bin/microvm-run` and `current/bin/tap-up` as `ConditionPathExists`,
`booted/bin/microvm-shutdown` and `booted/bin/tap-down` as the two `ExecStop`s,
the directory itself as `WorkingDirectory`, and all of it traversable by
`User=microvm Group=kvm`. Nothing reads `flake`, `toplevel` or anything else from
the directory at run time — both are read only by the `microvm` command.
Confirmed against this host: `/var/lib/microvms/a` holds `current`, `flake`, the
volume image and the API socket, and it runs.

Only a correctness question, as this item expected, and it answers *yes* — a
directory of ours needs `current/bin/*`, `booted/` and the right ownership, and
owes the units nothing else.

## The second read: nothing reconciles, and that is exhaustive rather than hopeful

Three things in the host module touch `${stateDir}` at all, and none of them
removes anything:

- `systemd.tmpfiles.settings."10-microvm"` creates `${stateDir}` (`d`, `0775`,
  `microvm:kvm`) and each declared VM's share sources. `d` with no age argument
  never cleans;
- `system.activationScripts.microvm-update-check` is the **only** code that
  iterates `${stateDir}/*`, and it is read-only: it `echo`s the names of VMs
  whose `current` predates the virtiofsd/tap/macvtap/pci scheme change. Marked
  *TODO: remove in 2026*;
- `microvm -l` walks the same directory, is read-only, and is a human's to run.

`microvm.autostart` and `systemd.targets.microvms.wants` are both derived from
`builtins.attrNames config.microvm.vms` alone. `~/flakes` declares none, and this
host agrees at run time: `systemctl show microvms.target -P Wants` is **empty**,
and there is no `install-microvm-*` unit on the machine — only the six templates.

**So a `toplevel` symlink in an imperatively-created directory is inert to the
host module.** The reconciler that could lose a volume is not there to be found,
and the volume — checkout, `$HOME`, caches, `target/`, ssh host keys on one
lifetime ([Plan D](../plan-d-fleet.md) L7) — is not at risk from this direction.

## What is actually there, and it is the mirror image

Deletion was the wrong thing to be afraid of. **Overwrite at activation** is the
real one, and it is worse in the way this repo cares about: it is silent and it
fails open.

`install-microvm-<name>`'s `ConditionPathExists` guard exists **only** when
`isFlake && updateFlake != null`. For a fully-declarative VM there is no guard, so
the unit runs on **every rebuild**, and its second line is `ln -sTf ${runner}
current` — an unconditional re-point. `microvm@${name}` additionally takes
`restartTriggers = [ toplevel ]`, and `install-microvm-*` is `partOf` it. So the
day anything declares `microvm.vms.<slot>`, a host rebuild re-points a composed
`current` back to the declaration and restarts the VM, with no error and no diff
— which is this item's own fail-open shape
([item 41](./041-a-delegable-verb-that-ends-in-root.md)) arriving by activation
rather than by a human's `microvm -u`.

**And the marker does not stop it.** `[ -e toplevel ]` is tested in exactly one
place, `build()` in `pkgs/microvm-command.nix`, which is `-c` and `-u`.
`install-microvm-*` never looks. So writing `toplevel` buys a refusal against a
human typing `microvm -u` — worth having, and it is the failure this item named —
and must not be read as protection against the declarative path, which is the
larger of the two.

## The constraint that follows, and it already exists for a different reason

**`~/flakes` must keep declaring no `microvm.vms.<name>`.** It already refuses
to, and for an unrelated reason stated in `modules/nixos/capsule.nix`: declaring
one would make that config evaluate the guest closure, which is what
`target.follows` exists to prevent. Two independent supports for one line is a
good position to be in — but the second support was accidental, and until now
nothing said that removing the first would cost a slot's composition.

It used to be *asked for in a comment* two repos away, which is the shape this
repo has converted to an eval-time throw twice before (`probeFabric`'s
`borrowed`, `hostModuleUnits`' two pairings). **It is an assertion now**
(`host/services.nix`): `capsule-perimeter` refuses a config in which
`microvm.vms` is non-empty, naming the declared VMs and why sharing a state
directory cannot work. Our module and microvm.nix's host module are imported
side by side in `~/flakes`, so the two meet where it matters.

**Vacuous where the option is undefined, which is `hostModuleUnits`' standalone
eval** — that config does not import microvm.nix's host module, so the predicate
is `lib.attrByPath ["microvm" "vms"] {} config` rather than a bare selection, and
it reads `{}` there. Same shape and the same honest placement as the sudoers
precedence check beside it: a control over a config this repo does not own can
only fire at the switch.

Watched failing before it was kept, in a throwaway eval carrying **both**
modules: no VMs declared, no assertion fires and the predicate reads `[]`; one
fully-declarative VM, and exactly one assertion fires with this item's message.
One honest limit found on the way — a *malformed* declaration
(`microvm.vms.zzz = {}`, neither `config` nor `flake`) dies inside microvm.nix's
own module on a `null.config` before any assertion can be read, so what the
assertion covers is the declaration that would otherwise have worked, which is
the one that could take a slot.

## A second-order effect of writing the marker, worth knowing before it is written

With `toplevel` present, `microvm -l` takes `readlink toplevel` as the *new*
system instead of evaluating the flake, and compares it against `readlink
current/share/microvm/system` — the source's own comment says *"Should always
equal current system"*. A marker that is not the composition's
`system.build.toplevel` therefore makes every slot read permanently `outdated`
and prints the remedy `microvm -Ru <name>`, which `build()` then refuses. Cosmetic
in effect, and a status readout that recommends a command guaranteed to fail is
still a status readout nobody can trust.

## Which verb the evidence covers

**Read**, twice, plus two run-time confirmations and one **built** refusal. Read:
microvm.nix's host module and its `microvm` command, in full, at the revision this
host has locked. Confirmed on the host: `microvms.target` wants nothing, no
`install-microvm-*` unit exists, and `/var/lib/microvms/a` holds what the first
read predicts. Built and watched failing: the assertion above, green through
`just check`, `just units` and `just build` — **and unswitched**, since it lives
in a module `~/flakes` takes and only a host rebuild renders it.

**Nothing else was written**: no `toplevel` exists on this machine and no program
of ours owns a `current`. The claim about upstream is therefore about what it
*would* do, and it is bounded by the lock — a `nix flake update microvm` can put
a reconciler there, and nothing would say so.

## Considered, and why the status quo is not the answer

**Never write `toplevel`, and let `-u` keep rebuilding the declaration.** That is
today's behaviour and it is correct today, since the declaration *is* what the
slot runs. It stops being correct at the first composed `current`, and it fails
**silently and fail-open**: a slot quietly running something other than what its
record says it was assigned is the same shape as a policy narrowed in the record
while the wire stayed wide ([item 41](./041-a-delegable-verb-that-ends-in-root.md)),
which this repo has already decided it will not ship once.
