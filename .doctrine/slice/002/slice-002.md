# Volume verbs, and a clone that does not carry an identity

## Context

`docs/plan-d-fleet.md` D3 and D4, which `§9` step 6 puts next and `IMP-001`
carries. The case is operational: S4 (*throw one away and start clean*) and S5
(*warm start*) are the two most frequent administrative actions on this host, and
**S4 today is a hand-typed `sudo rm -rf /var/lib/microvms/<slot>` under
`/var/lib`** — no verb, no partial reset, and it destroys the checkout, `$HOME`,
the caches *and* the ssh host keys whether or not that was the intent. S7 (*reset
just `$HOME`*) is not possible at all short of that same delete, because `$HOME`
is `/work/home` on the same volume as everything else. S5 is not possible either:
nothing shares or copies a volume.

Ungated by [item 49](../../../docs/ledger/049-who-owns-a-state-directory.md) —
both reads are taken, nothing upstream reconciles a declaratively-managed VM at
this lock, and a state directory of ours owes the units `current/bin/*`, `booted/`
and its ownership and nothing else. What that read leaves is a **standing
constraint rather than a gate**: `~/flakes` declares no `microvm.vms.<slot>`,
because `install-microvm-<name>` runs on every rebuild and would re-point
`current` at the declaration. That line is load-bearing for this slice and is
asserted in `capsule-perimeter`, not assumed here.

The recovery ISS-009 recorded is this slice's absence, priced: a hermetic reset by
hand, then a cold volume — figures in [probes](../../../docs/probes.md), which owns
them.

## Scope & Objectives

**One noun, four verbs, host-side:**
`capsule <slot> volume {df,reset,reset-home,clone-from <m>}`.

- **`reset`** — discard the whole volume: checkout, `$HOME`, caches,
  `/work/baseline`, and the guest's ssh host keys with them. This is S4 without
  the hand-typed `rm -rf`. **A reset is delete-and-recreate**, because the size is
  a `truncate` the runner applies only when the image is absent (`§5`) — which is
  also why there is no `resize` here and never will be one.
- **`reset-home`** — the `/work/home` half alone: the previous agent's own state,
  which a checkout reset does not reach. Coarse by construction — the mechanism
  recreates a directory and **may not know what a `.doctrine/` is** (`POL-002`),
  which is the same reason `reset` is coarse one level up.
- **`clone-from <m>`** — S5. A sparse copy of a stopped source's volume image, so
  a new slot starts warm instead of paying a cold build.
- **`df`** — what the volume costs on this host.

**And D4's identity half, which belongs with the clone rather than after it.** A
copied volume carries the source's ssh host keys, injected credentials and `.env`.
**Scrub by default, `--identity` to keep** — the safe default is the plain one and
the convenience is one flag.

**Gates, each of which is a thing already decided elsewhere:**

- **Refuses while the VM runs**, and *running* is a question about a **namespace,
  never a process name** — every capsule is `microvm@capsule` from the same store
  path, so `vm_running`/`any_vm_running` are the shape and `pkill -f` is a power
  cut for the siblings (`mem.fact.oubliette.dead-guest-is-not-a-dead-vm`).
- **The name must be a declared slot.** Resolution is the front end's act and
  never a program's (`POL-003`), and a destructive verb is the last place to grow
  a second answer to *which capsule*.
- **The fresh host keys have a home already** — `just reset-known-hosts <slot>`
  (`mem.fact.oubliette.fresh-capsule-fresh-host-keys`). This slice points at it
  and does not copy it.
- **The image is root-owned**, so the privileged step goes through **one spelling
  of the command as `sudo` will see it**, in the shape `host/proxy-restart.nix`
  already uses, with its rule beside the others in `host/services.nix`. A rule
  that names a path while the program invokes a different string is
  `NOTES item 44`.
- **Both transports keep working.** The devshell path must need no rebuild and no
  installed rule — it prompts for a password, exactly as `capsule <slot> start`
  does today — and the module path gets the grant. They will refuse in different
  orders and that is known rather than discovered
  (`mem.fact.oubliette.two-copies-refuse-in-different-orders`).

**Verification is a suite of the third kind**, since every interesting branch is
one a live host can only reach destructively: `host/volume-cases.nix`, one file
beside the program, a function of `pkgs`, `lib` and **the store path the program
ships**, taking as an argument the one thing that ties it to this host — wired
into `just cases` **and** `just build`, because a suite left out of the build is
`NOTES item 51` step 3.

## Non-Goals

- **D4's reuse-refusal on a non-clean volume**, and with it **Q3's
  `unassigned → provisioned(sha) → baselined(sha) → dirty` predicate**. Two of its
  four signals (`$HOME` touched, an interactive session opened) exist only inside
  the guest, so a stopped slot cannot be asked — and the *policy* about what may
  be reused is the target's, not this repo's. The dev-host waiver declaration goes
  with it.
- **`ISS-009` step 2's composition.** That item's fresh-per-unit half *consumes*
  `volume reset` and `volume reset-home`; whether it is a flag or a host
  declaration is open there (`POL-003` forbids the implicit default) and is not
  decided here. This slice's job is that the verbs exist and are safe to call.
- **`resize`.** Not deferred — refused. `§5` makes it delete-and-recreate, which
  `reset` already is.
- **The residue question itself.** A repurpose still inherits the last unit's
  untracked and ignored files until something composes these verbs
  (`mem.fact.oubliette.a-provision-resets-tracked-files-only`).
- **Any `microvm.vms.<slot>` in `~/flakes`.** Named because it must stay absent,
  not because this slice touches it.

## Summary

Open questions for `/design` — each is a real fork, not a detail:

- **OQ-1: is `reset-home` host-side or guest-side?** D3 says host-side, refusing
  while the VM runs, which means loop-mounting a stopped ext4 image as root — not
  forbidden by Firecracker's floor, since that floor is about mounting a *host*
  directory *into a guest*
  (`mem.fact.oubliette.firecracker-constraints`), but it is a new capability for
  this repo. Guest-side is cheaper and uses the door that already exists, but then
  the *refuses while running* gate inverts into *requires running*, and one noun
  would carry two opposite preconditions.
- **OQ-2: what does `df` answer that `capsule all status` does not?** The status
  column is the guest's `df /work`; a host-side answer is the sparse image's
  allocated-versus-apparent size. Two different questions, and if the verb only
  restates the column it should not exist.
- **OQ-3: where does the scrub happen, and what exactly is in it?** Offline on the
  copied image (which needs OQ-1's answer) or on the clone's first boot. The
  identity set wants one authority rather than a list retyped here — `capsule
  <slot> inject` is what knows what was injected.
- **OQ-4: does `clone-from` write the target's record?** The record is
  front-end-written (`NOTES item 29`); a clone changes what is on the volume, and
  `base`/`generation` describe an assignment. Cloning bytes and then being
  `setup` is one story; a clone that also inherits an assignment is another.
- **OQ-5: how wide is the sudoers grant?** `rm` under `/var/lib/microvms/*` is a
  much broader thing to hand out than `systemctl restart <unit>`. A small root
  helper taking a slot name and validating it against the declared pool bounds it
  to what the pool contains; the alternative is a path pattern in the rule.

Risks and assumptions:

- **A destructive verb with a name argument is unrecoverable when the name is
  wrong.** The declared-slot gate and the running gate are the two cheap
  protections; whether a confirmation is a third is a design call.
- The cost the verb makes legible — a discarded cache — is priced in
  [probes](../../../docs/probes.md) and must be linked, never copied.
- Assumed: nothing else on this host writes `/var/lib/microvms/<slot>` while a
  volume verb runs, which is true only because the units are ours and the slot is
  stopped.

Closure intent: `volume-cases.nix` green inside `just build`, with each refusal
asserted **by reason** and not by exit status, and the suite checked for its
ability to fail by mutating the behaviour it pins. Plus one live exercise per
destructive verb on a finished slot — a real `reset` and a real `clone-from`,
which is the part no suite can reach, since what ties these to this host is root
and a real image.

## Follow-Ups

- `ISS-009` step 2, which is filed `after` `IMP-001` for exactly this reason.
- D4's reuse-refusal and Q3's state model, whenever a second principal makes it
  urgent.
- `CHR-002` is unrelated but adjacent: `handoff`'s own live path is still
  unexercised, and the first real `reset` of a finished slot is a chance to take
  more than one piece of evidence from one boot.
