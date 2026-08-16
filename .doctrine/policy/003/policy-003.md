# POL-003: One declaration per axis, and no implicit default

## Statement

**Each axis of this system has exactly one declared home, and nothing anywhere
names a value implicitly.**

| axis | the one home | what it holds |
| --- | --- | --- |
| addressing | **`net` in `flake.nix`** | tap name, both addresses, MAC, proxy port. Threaded to the guest via `specialArgs`. **Do not hardcode an address anywhere else.** |
| slots | **`capsules.nix`** | which slots exist (`a`…`j`) and the policy set an assigner may select within |
| host controls | **`policies.nix`** | an allowlist file, an ingestion bound and `mayCollect` per named policy |
| the confined repo | **`target.nix`** | name, path, tools package, caches, sizes |
| a probe's fabric | **`probeFabric` in `flake.nix`** | every name, link, address and network a probe's egress fabric is built from |

**And nothing has a default.** The four host programs take `--capsule <name>` or
`CAPSULE_NAME` and **refuse** without one. `capsule-host --policy <name>` and
`capsule-collect --policy <name>` refuse without one. Every program takes
`--profile <name>` where it takes `--capsule <name>` and refuses without one.
**No `just` recipe spells a slot name** — the delegating ones pass none and the
lifecycle ones require one (`NOTES item 28`).

**Resolution is the front end's act, never a program's.** The `capsule` front end
resolves an unnamed verb to the slot that is *up* — refusing when none or several
— and resolves which target a verb means by explicit flag, then the slot's
record, then the one profile this host declares, refusing when several. **A
program that reads host state to pick a target is `NOTES item 20`'s mistake.**

**No perimeter value lives in `target.nix` and none comes back.** A control
chosen by whoever names the project is a control the naming authority holds
(`NOTES item 36`, `NOTES item 25`).

## Rationale

A value with two homes has two answers the first time one is edited, and the
divergence is silent. A value with an implicit default is a value nobody chose,
which is the same failure with a shorter fuse — `capsule` as a flake attribute is
the guest **image**, not a slot, and `microvm -c` will happily instantiate it
(`RSK-005`).

The `probeFabric` case is the sharpest, and it is **enforced rather than asked
for**: `borrowed`, its intersection with what `capsules.nix` declares, **throws
at eval**. The reason it exists rather than a comment is `NOTES item 38` — a
probe verified a shape *before* the shape was declared, and **became a borrower
by standing still while the declaration moved onto it**, with no diff to notice.
Its cleanup trap deletes `eg-rt`, the fleet's uplink, by name; only three
refusals sitting ahead of the trap kept that theoretical.

Two related shapes that follow from the same rule:

- **`statePaths` is a template list, not a path list.** Each entry may hold one
  `{unit}`, filled at collect by an opaque token the assignment carries, and **a
  hole with no unit refuses rather than collecting everything**
  (`NOTES item 32`). That is the shape for anything a policy must scope by
  run-time state: the policy says *where* the hole is, the assignment says *what*
  fills it, and the token is bounded so it can name an instance and never widen a
  perimeter.
- **A slot is pinned to the bytes it was provisioned under.** A provision copies
  its document into the slot's own directory and records that copy's digest; every
  later verb on that slot is pointed at *that* directory. **A provision is the one
  verb that reads this host's directory**, because the act that sets a pin cannot
  be governed by it (`NOTES item 52` step 3).

## Scope

**Applies to** every address, name, bound and path in this repo.

**Excluded**: `workBranch` in `flake.nix`, deliberately — the guest's branch is a
**constant**, because a name that identifies the work is not project state
(`docs/contract-target.md`). `capsule-provision <ref>` is a ref in the target repo
and is the other thing called a branch here.

Also excluded: `target.guestPath`, the one path both sides share, which is why it
is derived in `target.nix` rather than spelled in the guest and again in the
host's git channel.

## Verification

- **Eval**: `probeFabric`'s `borrowed` throws. `hostModuleUnits` evaluates the
  module including its programs.
- **Build**: `policyCases`, `profileCases`, `gitChannelCases` and the rest run
  each program's own text against a substitute for the one thing tying it to this
  host. Three are handed a fixture and say so in their headers: the guard's
  stubbed kernel, **the front end's pool that is not this host's**, and the
  profile's target that is nobody's.
- **Not covered**: `capsule-provision` called directly writes no record
  (`CON-003`), so a slot can be provisioned with no `base` pinned and the only
  witness is a missing key and a `-` in the `gen` column.

## References

- `NOTES item 20` — which capsule a host program is talking to; don't let a
  program probe for its transport.
- `NOTES item 28` — a slot has no default, and a front end is where one is
  guessed.
- `NOTES item 36`, `NOTES item 25` — assignment is a perimeter-mutating verb.
- `NOTES item 38` — a probe that became a borrower by standing still.
- `NOTES item 52` — the document leaves the store, and the pin.
