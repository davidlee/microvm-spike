# QUE-004: How many hot slots actually fit on this host

**N=2 is not N, and nothing has a time series.** The stall figures are cumulative
totals over each cgroup's life, so they bound *how much* and say nothing about
*when*; `just load` has still never sampled a build.

The term that decides the answer is the **ratchet**: a capsule holds most of its
ceiling until it is stopped — measured as **6141 MiB of `anon` for a guest
reporting 481 MiB used**, because firecracker has no balloon and no free-page
reporting. So peaks are **not additive across a working day**, and the naive
sum-of-ceilings arithmetic is wrong in the safe direction by an unknown margin.

The question that replaces the old 6144 one is narrower and unmeasured:

- **how many hot slots actually fit** — ~7.5 GiB per built slot against this
  host's 60.4 GiB, and
- **whether any ceiling low enough to cut the charge is low enough to squeeze the
  guest.** 6144 was not, and nothing says where that boundary is.

`docs/plan-d-fleet.md` §0's recommendation **needs rewriting rather than
re-running** — it answers the superseded question.

Answering it needs `just load` to sample a build, which is a time series and not
a total. Read the count, not the colour (`STD-001`).
