# POL-002: Nothing generic learns what the target is

## Statement

**The capsule is the product and the confined repo is a client.** Every target
need must be met by *a generic capability plus a value the target supplies* —
**never by the generic code learning what the target is.**

The review challenge, which is the whole point:

> **Would a different target need this code changed, or only a different value?**
> If the code, it is in the wrong place.

Three limbs:

1. **Generalise before implementing.** For each target-shaped want, name the
   capability it is an instance of, and build *that*. doctrine wants its cargo
   config tuned to the capacity it has been given; the capability is *render
   static guest config from the instance's declared reservation*. Not "support
   cargo", and emphatically not "copy the human's `~/.cargo/config.toml`" —
   which is a third failure, a config describing a machine the capsule is not.
   **The smell is a toolchain's name (`cargo`, `bun`, `sccache`) appearing
   anywhere but `target.nix`.**
2. **Anything beyond the contract is declared and optional.** The contract is
   *be a git repo on this host, and expose one flake package that is your
   devshell's tool set* (`NOTES item 16`). Everything else is a `target.nix`
   field with a **working absent path** — and a second target must be able to
   omit any field doctrine happens to set.
3. **Fix transient local state out-of-band.** A one-off in `~/flakes`, this
   host's disk, or one repo's history is fixed by hand and **not by permanent
   leniency in the flake**. Strict-and-owned beats lenient-and-coupled: it fails
   loudly here, and it is the only thing that ports.

**`doctrine` may appear in exactly two places**: `target.nix`, and
`inputs.target.url`, which cannot be computed. Nothing target-shaped goes in
`perimeter/`, `vm/capsule.nix` or the justfile; it comes from there as a value.
**And nothing target-shaped is ever read *out of the target repo*** — the agent
can edit that (`NOTES item 16`).

**No program carries a target's values or its name — nor its own existence.**
Every `capsule-<verb>` is built on every host and refuses at run time for a
document declaring nothing, because "no program rather than one that cannot work"
is the right absent path only while a host has one target (`NOTES item 51` step
6). **Same rule for printed text**: the front end's shape is not a function of
any target — `capsule all status` is one table over N slots and M targets, every
column always printed, every verb always offered.

The boundary that makes this a rule and not a preference: **a *program* holds
exactly one profile and *does* branch on it** — `capsule-collect`'s two `--unit`
refusals.

## Rationale

doctrine is the guinea pig, not the design. Its needs may inform a **default**;
they may never carry the **mechanism**. A capability built around one client is a
capability that ships with that client welded in, and the cost is invisible until
a second client exists — by which point the welding is load-bearing.

**This is doctrine's own POL-002 pointed the other way** — the same discipline,
with this repo as the platform and doctrine as the host project. That the ids
coincide is a coincidence: doctrine's `POL-002` lives in doctrine's corpus and
this one lives here, and they are **separate id spaces** (`ADR-001` term 2).

## Scope

**Applies to** every host-side program, `perimeter/`, `vm/`, the justfile, and
every printed string.

**Excluded**: `target.nix` itself, which is where a target's values are *supposed*
to live, and `inputs.target.url`.

The surface this rule produces is written down field by field:
`docs/contract-target.md` is what any repo must supply and may rely on;
`docs/contract-doctrine.md` is doctrine's two roles — the client holding the
requirements, and one instance of the contract. **Update them in the same commit
as anything that moves the boundary.**

## Verification

**Build time, partially.** `NOTES item 51` moved the target's run-time half out
of the store into a rendered document every program loads at run time, taking
`--profile <name>` and refusing without one; `NOTES item 52` moved the documents
out of the store entirely, so a second target is a file rather than a rebuild.
`profileCases` pins the render, including a target no host declares.

**Never exercised: a second target has never been declared** (`IMP-004`). The
capability is built and unused, and **three refusals are build-time-only** until
one exists — `--unit` against a target with no hole, `capsule-adopt`'s gitlink
mode class, and the corrected `capsule-baseline` sizing. **Three absent paths are
only reasoned** (`RSK-002`): `baseline = null`, `caches = {}`, `guestConfig = {}`.

So this policy's evidence is at `STD-001`'s **build** rung and no higher. That is
the honest reading and it is why `IMP-004` matters more than its size suggests.

## References

- `NOTES item 16` — target-agnostic, and the contract's floor.
- `NOTES item 51`, `NOTES item 52` — the target leaving the store, and the
  document leaving it.
- `NOTES item 31`, `docs/contract-flavour.md` — the ownership smell pointed the
  other way: a convenience in `target.nix` says doctrine needs it.
- `docs/contract-target.md`, `docs/contract-doctrine.md`.
