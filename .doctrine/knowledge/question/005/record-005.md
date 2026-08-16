# QUE-005: What is time-to-interactive for a fresh capsule

**Time-to-interactive is not 8.31 s.** "Usable" in `docs/probes.md` means
*provisioned* — that is the freshness probe's own definition, and the figure is
correct for what it measures.

An **interactive** capsule is boot + provision + setup + a cold baseline build.
And because `/work/home` is on the volume that freshness deletes, **setup is paid
per fresh capsule** rather than once.

The measurement obstacle is structural, not effort: the freshness probe **cannot
take the cold build's price itself** — its namespace has no upstream. So the
109 s and the 22 assertions **come from different runs and must not be quoted as
one result.**

That is the trap worth keeping: two correct figures from two runs, adjacent in
one document, reading as one number. It is `STD-001`'s *read back* rung applied
to measurement.

Answering it needs one run that spans all four stages with an upstream available,
which is a different probe shape rather than a longer version of the existing
one.
