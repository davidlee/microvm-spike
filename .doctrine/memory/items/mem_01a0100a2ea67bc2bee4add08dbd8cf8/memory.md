`receive.denyCurrentBranch = updateInstead` checks out the pushed commit, so a
provision resets **tracked** files and nothing else. Every untracked and
gitignored file in the guest's work tree crosses the assignment boundary, along
with `/work/home`, the caches and `/work/baseline` — and **generated files that
are stale by exactly what the finished slice changed** are the dangerous half:
they contradict the code beside them and surface as a red test on the new base
ref.

`setup` is not `handoff`: it calls neither `archiveRefs` nor `guestDropState`, so
the first repurpose of any slot that has collected is refused for its own stale
`refs/capsule/state/<stage>`, naming a cause that is not the cause.

The only deterministic reset is the volume: `capsule <slot> stop`, `sudo rm
/var/lib/microvms/<slot>/capsule-work.img`, `capsule <slot> start`, then
`ssh-keygen -R capsule-<slot>` because the fresh volume means fresh host keys at
the same address. ~2 min, nearly all of it the discarded crate cache. There is no
verb for it — `ISS-009`, `IMP-001`.

Same file, one tier down: [[mem.fact.oubliette.deny-current-branch-only-governs-head]]
is what makes the tracked half land at all. The quarantine's version of this shape
is `NOTES item 50`; the volume's is `ISS-009`.
