# EVD-001: The ratchet — a capsule holds most of its ceiling until stopped

A capsule's cgroup charged **`anon` 6141 MiB**, page cache 965 MiB and 29 MiB of
slab, while **inside that same guest `free -m` reported 481 MiB used**. That gap
is the finding: firecracker has **no balloon and no free-page reporting**, so
guest RAM handed back inside the guest is never handed back to the host.

Consequences that other records rest on:

- **Peaks are not additive across a working day.** A slot holds ~7.5 GiB once
  built, against this host's **60.4 GiB** (13.1 GiB available with both capsules
  idle and other work running).
- **Cutting the ceiling barely moves the charge.** At a 6144 MiB ceiling the same
  workload's `anon` was **6095 MiB** — 46 MiB against a 2048 MiB cut — and it had
  touched 6141 MiB when given 8192. That reads like saturation and is the
  ratchet.

**The numbers are cumulative totals over each cgroup's life**, so they bound *how
much* and say nothing about *when*. `just load` has never sampled a build.

Source: `docs/probes.md`, *What a capsule holds after it has built*, *Two cold
builds at once*, *The first cold build at a 6144 ceiling*.

Supports `QUE-004` — and it is why that question is *how many hot slots fit*
rather than *what ceiling to set*.
