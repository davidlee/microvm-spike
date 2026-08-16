# EVD-005: Disk is the practical limit, and this filesystem has no reflink

Host disk under `/var/lib`: **166 GiB available of 1.78 TiB, 91% used**
(`df /var/lib`, 2026-08-13).

`/var/lib` is on the root filesystem, `/dev/nvme0n1p2`, **ext4 — so no reflink**.
A cloned volume is a **real copy of the source's *allocated* blocks**, which is
its **high-water mark and not its current usage**. That is the term that decides
what a clone costs, and it is not the number a `du` of the live tree reports.

This row is what bounds the number of capsules.
`docs/plan-c-multi-capsule.md`'s 180 GiB is the same disk earlier, and its N
table is that much optimistic.

Supporting volume figures, all `du -B1` allocated blocks:

- after boot, before provision: **260 MiB** — an empty ext4 for a 32 GiB
  declaration. The declared 32 GiB is sparse and is not a disk cost.
- after provision: **296 MiB**, so a provision costs **36 MiB** against a 32 MiB
  repository.
- one `just web-build test` in, **untuned**: 7.4 GiB. **Tuned** (`debug = 0`,
  `incremental = false`): **1.1 GiB** — a *floor*, not a plateau, since there is
  no discard and `target/` accretes.

Source: `docs/probes.md`, *Figures*.

Bears on `QUE-004` and on `IMP-001` — clone semantics are where the no-reflink
fact becomes a design constraint rather than a number.
