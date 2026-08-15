# NOTES item 51 — the four programs still spell the target, and it is item 20 one level up

*State: **planned, nothing built.** [Plan D](../plan-d-fleet.md) §6.4, which that
file names as **D7's first task rather than a detail of it** and says is worth
doing even if flavours never happen. Written up here rather than left as a
paragraph in a plan because the implementation will not fit one session, and a
plan is not a thing anyone hands over.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## The coupling, in one sentence

`host/programs.nix` builds every host-side program with `target.nix`'s values
**interpolated into their text**, so each program's store path is a function of
which project this host confines. One target makes that invisible. Two targets
make it four programs per target — which is exactly the bug that stood between
N=1 and N=2, where a socket path baked into a store path meant a program per
*capsule* ([item 20](./020-which-capsule-a-program-means.md)). The fix rhymes:
the values arrive at run time, the way `--capsule` already does, and one store
path goes on serving everything.

## What is baked, read from source

| value | source | store paths carrying it |
| --- | --- | --- |
| `guestPath` (`/work/doctrine`) | `name` + `volumePath` | `guestRepo` — so `capsule-provision` and `capsule-collect` — plus `observe`'s workdir, `capsule-baseline`'s workdir and `measure[0]`, `refresh`'s workdir, `brief`'s workdir, `snapshotFor`'s workdir |
| `path` (the host checkout) | `target.path` | `capsule-provision`'s `src` (`host/git-channel.nix:110`), `brief`'s `hostCheckout`, the front end's fetch (`host/cli.nix:797`) |
| `baseline`, `refresh` | command lines | `host/baseline.nix`, `host/refresh.nix` |
| `statePaths`, `stateMaxBytes` | `target` | `host/state-snapshot.nix` — **a script pushed into the guest**, so the text is the interface |
| `cachePaths`, `volumePath` | `caches`, `volumePath` | `capsule-baseline`'s `measure`, `observe`, `inject`'s payload destinations |
| `name`, `sizes` | `target` | the record's `profile` and `class` (`host/cli.nix:591`), the motd, `services.nix`'s `repo` default |

`programVerbs` is the same coupling in its other form: which verbs exist at all
is decided at build time by which `target.nix` fields are non-null.

## The finding that changes the scope

**Detargeting subsumes [Plan D](../plan-d-fleet.md) D7's "the checkout goes at a
generic path" generalisation, and at none of its cost.** That bullet exists to get
a project's name out of the closure. A path that *arrives at run time* is not in
the closure either — so the relocation buys nothing the detargeting has not
already bought, while costing every existing volume its checkout, on a host where
a slot is holding live work. Do the values; leave `/work/<name>` where it is.

**The honest limit, so nobody reads this item as more than it is:** the guest
*image* still knows the project's name, because `vm/capsule.nix`'s seed creates
that directory. Getting it out of there is §6.2 — the seed becoming
assignment-driven — and is a different consequence with a different rebuild
class. This item is **the host programs only**, and finishing it does not make
two targets concurrent.

## What is already in place, so this is a refactor and not a design

Three things, and they are why the shape is obvious rather than inventive:

- **The record already carries the fields.** `host/cli.nix:591` writes `profile`
  (the target's name) and `class` (`mem`/`vcpu`) at every provision. They are
  written and read by nothing — inert fields waiting for this.
- **`CAPSULE_REPO` is the precedent, already shipped.** `host/git-channel.nix:110`
  is `src="''${CAPSULE_REPO:-${target.path}}"`: a run-time override of a baked
  default, in the two places that read the host checkout. This item generalises
  that from an override to a lookup.
- **The guest-pushed scripts already take their subject as an argument**, because
  the case suites forced it: `snapshotFor <checkout>`, `refreshFor <command>`,
  `briefRunner`. That is the third kind of check
  ([CLAUDE.md](../../CLAUDE.md)) paying for itself in a direction it was not built
  for — the seam a test needed is the seam a run-time value needs.

## The one decision not taken

**Is the profile document per target, or one for the host?** Per target —
`profileDir/<name>.json`, with the slot's record naming which — is the eventual
shape and mirrors `policyDir` exactly. One document for the host is less work
today and is a second thing to migrate later. **Recommended: per target**, on the
grounds that the interim saves an hour and the migration costs a day, and that
`policyDir` has already paid for the shape. Not decided; decide it before step 3
and not during it.

## Order of work

Red/green, and the first step is a test that fails:

1. **Extend `snapshotCases`, `refreshCases` and `briefCases`** to pin the
   argument-taking form of every value each guest-side script currently
   interpolates. Watch them fail against today's text, which is the rule about
   mutating the behaviour a suite claims to pin.
2. **Move the values into arguments** in `host/state-snapshot.nix`,
   `host/observe.nix`, `host/refresh.nix`, `host/brief.nix`, `host/baseline.nix`.
   Nothing about where the values *come from* changes yet; this step only ends
   interpolation.
3. **Render the profile document.** `target.nix`'s run-time half → JSON, authored
   in nix and checked at build for free, read at run time by a program. §6.1's
   *validated document, not a nix file*, with `perimeter/egress-allow.txt` as the
   standing precedent for a plain file that is deliberately not a store path.
4. **Host programs read it after resolving `--capsule`**, exactly where
   `transport` already resolves a socket, and with the same refusal when unnamed
   ([item 28](./028-a-slot-has-no-default.md)).
5. **Pair the read with the units' permissions in `hostModuleUnits`** — a program
   that opens `profileDir` and a unit whose user can traverse it. This is
   [item 39](./039-a-bind-is-not-a-traversal.md)'s class exactly, it is not
   catchable by the cases because a sandbox has one uid, and it is where the last
   bug of this shape came from.
6. **`programVerbs` last**, since which verbs exist becomes a property of the
   document rather than of the build, and that is the step most likely to want a
   decision nobody has made yet.

## What must not drift while this is being built

Every one of these has cost something once:

- **No program probes for which target it means**, any more than one probes for a
  transport. It takes an argument or reads the record it was pointed at
  ([item 20](./020-which-capsule-a-program-means.md)).
- **Nothing target-shaped is read out of the target repo.** The document is
  host-side and keyed by name; the agent can edit the confined tree
  ([item 16](./016-target-agnostic.md)).
- **A profile is pinned at the assignment's generation; a policy is live.** Two
  owners, two clocks — editing a project's caches must not change what a running
  capsule is doing with no verb run against it, while a tightening must reach one
  without a re-assign ([contract-assignment.md](../contract-assignment.md),
  [item 25](./025-assignment-is-a-perimeter-verb.md)).
- **No control migrates into the profile.** `collectMaxPackBytes` and the
  allowlist are policies and stay policies; `stateMaxBytes` is the target's,
  because it bounds what the target's own declared paths may grow to
  ([item 36](./036-a-policy-is-selected-not-named.md)).
- **The two shipped copies stay one store path.** `host/cli.nix` is imported at
  two call sites and only stays a single derivation while every argument agrees;
  anything built at two call sites needs one construction
  ([CLAUDE.md](../../CLAUDE.md)).

## Risk, and the smoke test

`capsule-provision` and `capsule-collect` are what the live slots use, and a slot
is holding real work ([status](../status.md)). So: one commit behind `just cases`
and `just build`, and before anything else on the far side of the switch, a
`capsule all status` and one `capsule <slot> collect` against a slot whose result
is already safe. A refactor that reports success while collecting nothing is the
failure mode this repo has already had once, in `host/refresh.nix`
([item 47](./047-a-script-on-stdin-and-the-command-that-eats-it.md)).

## Which verb the evidence covers

**Read**, of `host/programs.nix`, `host/git-channel.nix`, `host/cli.nix` and
`target.nix`, plus the record-writing site. Nothing is built and no step below
has been started. The inventory is the read's product and is the part worth
trusting; the ordering is a judgement.
