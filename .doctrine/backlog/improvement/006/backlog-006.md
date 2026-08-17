# IMP-006: A second target at once, which is a second guest image

**The image tier of what `IMP-004` used to be one item about.** Host-side, a
second target is a document in a directory (`NOTES item 52`) and `IMP-004` is
that. Guest-side it is an image, and this is that.

## Why it is a separate item

`vm/capsule.nix` builds the checkout path, the cache directories, the
`guestConfig` files, the motd and the tool set from `target.nix` at build time,
and the flake input carrying the tool set is a literal that cannot be computed.
So the guest knows the project's name and cannot be told a different one at run
time — the honest limit `docs/contract-target.md` states, and `Plan D` L1:

> A second target is a second image: +3.0 GiB of erofs, its own tool set, its own
> allowlist, its own `target.nix`.

Every declared capsule is bound to one `capsuleVm`, which is what makes "one
image, N capsules" structural rather than a promise (`NOTES item 21`). Two
targets **at once** therefore needs slot→image to become a per-slot answer, and
that is `Plan D` D7 / `IMP-003`, not a value change.

**Sequential is already done and is not this.** panopticon on branch
`second-target` (`NOTES item 23`): `target.nix` wholesale, one allowlist file,
`inputs.target.url`, and one guest capability (nix-ld). Nothing generic changed.
Two targets one at a time is `git switch` plus a rebuild.

## The insurance that was not taken

`plan-c` recommended a `target` field on the instance record as cheap insurance
against exactly this. It was not taken — `declared` carries `index` and nothing
else (`Plan D` L1). Whatever shape this item lands in, that field or its
replacement is a prerequisite: a slot has to say which image it is, or the front
end is resolving a target for a guest that is a different project.

## What only this tier can buy

Three of `IMP-004`'s original six, because all three are the **build-time half**
that no document carries:

- `caches = {}` and `guestConfig = {}` — two of `RSK-002`'s three absent paths.
  The third, `baseline = null`, is document-side and is `IMP-004`'s.
- `capsule-adopt`'s gitlink mode class (`NOTES item 34`) — needs a target repo
  that actually carries one.
- The corrected `capsule-baseline` sizing (`NOTES item 23`), which has never
  produced a record because doctrine shares no inodes between `target/` and
  `.cargo`. Needs a real cold build in a real second guest.

## Precondition

Do `IMP-004` first. A second document with nothing to boot behind it is cheap and
tells you whether the host side is honest; discovering it is not *while* also
building a second image confuses two answers.

Evidence rung (`STD-001`): the capability is **reasoned**. The port's price is
**taken** — a diff (`NOTES item 23`). The image's price is hand-measured and
`docs/probes.md` says so of itself: the 3.0 GiB per-instance erofs figure is
Plan C's, and *the probe does not measure it*. What is unbuilt is concurrency.
