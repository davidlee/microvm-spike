`receive.denyCurrentBranch = updateInstead` checks out the pushed commit, so a
provision resets **tracked** files and nothing else. Every untracked and
gitignored file in the guest's work tree crosses the assignment boundary, along
with `/work/home`, the caches and `/work/baseline` — and **generated files that
are stale by exactly what the finished slice changed** are the dangerous half:
they contradict the code beside them and surface as a red test on the new base
ref.

**The refusals are fixed and the residue is not.** `setup` now asks the guest for
its `refs/capsule/state/*` before it writes or pushes, refuses a repurpose that
would land on a stale chain, and drops it under `--force` (`ISS-009` step 1). What
it still does is provision onto everything else the volume holds.

So the only deterministic reset is the volume, and there is no verb for it yet
(`ISS-009` step 2, `IMP-001`): `capsule <slot> stop`, `sudo rm
/var/lib/microvms/<slot>/capsule-work.img`, `capsule <slot> start`, `just
reset-known-hosts <slot>` because a fresh volume means fresh host keys at the same
address, then `setup` again. ~2 min, nearly all of it the discarded crate cache.

Same file, one tier down: [[mem.fact.oubliette.deny-current-branch-only-governs-head]]
is what makes the tracked half land at all. The quarantine's version of this shape
is `NOTES item 50`; the volume's is `ISS-009`.
