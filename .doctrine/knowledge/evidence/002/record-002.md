# EVD-002: Time-to-interactive is about two minutes, not 8.31 s

`docs/probes.md` measures **time to a usable fresh capsule: 8.31 s** (run 1:
8.60) — boot 6.41 s plus provision 1.90 s. **"Usable" means provisioned**, which
is the freshness probe's own definition and is correct for what it measures.

An **interactive** capsule is that plus `capsule-inject` (unmeasured, seconds)
plus setup plus a **cold baseline build of 109 s ± ~5%**. So 8.31 s is **~7%** of
time-to-interactive, and both halves are paid **per fresh capsule**, because
`/work/home` is on the volume freshness deletes.

**The two figures come from different runs and must not be quoted as one
result.** The freshness probe cannot take the cold build's price itself — its
namespace has no upstream — so the 109 s and freshness's 22 assertions are
separate runs.

Also from the same rounds: the price of freshness **at boot** is +0.07 s (run 1:
−0.02) — it **changed sign between runs**, which is the finding: boot is free to
within ~1%. The real price of freshness is the discarded cache, three orders of
magnitude larger.

Source: `docs/probes.md`, *Figures* and *The cold build*.

Supports `QUE-005`. An instance of `STD-001`'s *read back* rung: two correct
figures, adjacent in one document, reading as one number.


## Disputes doctrine's EVD-019

doctrine's corpus holds `EVD-019` (*Fresh capsule cost: freshness is free at the
boundary*), whose headline datum is **8.31 s to a usable fresh capsule**. That
figure is correct for what its probe measures and is the one this record says
must not be read as time-to-interactive. `EVD-019` is `captured` and carries no
note of this.

Stated here in prose because the edge is not authorable: `doctrine link` resolves
a target only within one corpus (`ADR-003`, clause 3). doctrine's side owes the
matching sentence.
