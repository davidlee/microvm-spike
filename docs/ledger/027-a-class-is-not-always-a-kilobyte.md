# NOTES item 27 — a class is a kilobyte only over what the profile ignores

*State: settled for `mem` by eval; the `vcpu` half read from source. Nothing
built.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**The inference [Plan D](../plan-d-fleet.md) §5 flagged is settled, and the
conclusion it was carrying is narrower than the claim it was asked to support.**
§5 compared `system.build.toplevel.drvPath` with and without a changed
`microvm.mem` and asked for identical paths. They are identical. So `mem` is
runner configuration and nothing else: a capsule declared at 6144 and one at
8192 share one 3.0 GiB erofs, the drop in §9 step 3 is free of the image, and a
class that varies only `mem` costs the ~1 KB of JSON §5 read from the runner.

**What does not follow is "a class costs a kilobyte", because the other half of
a class is `vcpu` and `vcpu` does not stop at the runner.** Read from source:
`vm/capsule.nix` does `inherit (target.sizes) vcpu mem`, and `mem` reaches
`microvm.mem` and dies there — but `target.nix` renders

    jobs = ${toString sizes.vcpu}

into `guestConfig`'s cargo config, which is a store file **in the closure**. So
for this target, changing the vCPU reservation changes the image. Class 2, a
`microvm -u` per slot, not a kilobyte.

**This is the capability working, not a leak, and that distinction is the whole
point of the item.** CLAUDE.md's worked example for the guinea-pig rule is
exactly *render static guest config from the instance's declared reservation* —
the alternative being a copy of a human's `~/.cargo/config.toml`, which
describes a machine the capsule is not. The coupling is intended and doctrine
is right to have it. What was wrong was the **cost model**, which assumed a
reservation only ever reaches the runner.

So the rule the class/profile boundary actually wants:

> A class may vary freely, at a kilobyte, only over reservations that the
> assigned profile derives nothing from.

Which is a predicate over a *(class, profile)* pair and not a global fact,
because profiles differ: a profile with no reservation-derived guest config has
`vcpu` free too, and a second target that derives something from `mem` would put
`mem` in the image. Nothing generic should be tuned against doctrine's answer
here — the same conclusion the cold-build ratio reached from the other direction
([item 23](./023-second-target.md)).

**The model absorbs this without new mechanism, which is the reassuring part.**
An assignment already identifies its image by the *resolved store path* rather
than by a name, and already refuses a changed image on a non-clean volume
([contract-assignment.md](../contract-assignment.md)). A class change that
re-renders derived config produces a different path, so it is already an image
change and already caught. What has to change is only what the documents *claim*
about cost — and D2's pool arithmetic, which assumed classes were free to
multiply.

## The methodological half, which is the reason this is an item

**The check that settled `mem` would have passed `vcpu` too, silently.** Running
the same eval against `microvm.vcpu` forces the *option*; the cargo config reads
`target.sizes.vcpu`, the *value* the option is derived from. Forcing the option
leaves `target.nix` untouched, so `guestConfig` is unchanged and the closure
does not move — a green result for a coupling that is real. The probe would have
confirmed the claim it was meant to falsify.

What found it was reading the source for every consumer of the value, which took
one grep. Same family as the two instrument corrections already recorded here: a
single `du -sm` charging a hardlinked inode to whichever argument came first
([item 23](./023-second-target.md)), and a slice's `memory.peak` outliving the
units in it ([status](../status.md)). The pattern is consistent enough to state
as a habit: **an eval that overrides an option tests the option, and a value
threaded through `specialArgs` is not reachable that way.** Override the value —
or read the source — when the question is what depends on a *declaration*.
