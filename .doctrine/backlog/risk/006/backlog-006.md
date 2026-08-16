# RSK-006: The byte bound on collect bounds one packfile, not the transfer

`ulimit -f` bounds **one packfile**, not the transfer. Many small objects, or a
delta bomb, go straight past it.

The host-shaped answer is a quota or a dedicated filesystem for the quarantine —
a host control for a host-side perimeter, which is where controls belong.

The state half has its own ceiling in a **different place and for a different
reason**: `stateMaxBytes`, checked *in the guest* before the commit, because the
fetch is atomic and an over-budget state half must skip rather than take the code
refs down with it. Do not unify them; the asymmetry is load-bearing.

`capsule-adopt` adds no bound at all — it reports the byte count and lets a human
decide, which is a deliberate choice and not an oversight.

Context: a tree that comes out of a capsule is **attacker-shaped input**, and
`NOTES item 34` is where the three escape classes and their handling live.

Evidence rung (`STD-001`): reasoned. The bound that exists has been **exercised**;
the bypass has not been attempted.
