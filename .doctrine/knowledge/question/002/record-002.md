# QUE-002: Which stage does a host-authored commit land at

With no archive a host-authored commit is always a **root commit**, so it parents
nothing, and `implementation` is **a default somebody picked** — overridable with
`--stage`.

The question is whether that default is right, and it has never been pressured
because nothing has needed a different one.

**Reserved and related: the chain across stage names.** An audit capsule
collecting at `--stage audit` cannot take the implementation state it was briefed
with as its parent. The shape is
`capsule-collect --stage audit --after implementation` — **~10 lines across two
files**, which is small enough that the reason it is unbuilt is that the semantics
are undecided, not the cost.

Settling this needs a real audit capsule chained behind a real implementation
capsule, which `IDE-001` would produce as a side effect.
