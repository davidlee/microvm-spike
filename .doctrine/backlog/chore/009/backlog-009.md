# CHR-009: Measure socat's nodelay

`socat`'s `,nodelay` is **shipped and unmeasured**. Bulk throughput over the
relay is fine — 93.7 MiB/s out, 117.9 MiB/s back — but the per-packet fix that
stopped interactive echo clumping has no figure at all.

Bulk throughput is the wrong instrument for it: the symptom was latency under an
interactive session, and a bulk number is green whether or not the fix does
anything.

Land the figure in the observation ledger.

Evidence rung (`STD-001`): the option is **shipped** and the behaviour it changes
was **observed by eye**. There is no rung for that. A figure is what would put it
on the ladder.
