# NOTES item 15 — two things that only grow: the volume, and the proxy log

*State: measured, accepted.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Two things that only grow.** Neither can exhaust the host — worth saying,
since "unbounded" is the wrong word for both — but neither ever gives space
back.
- `capsule-work.img` is sparse and capped at its declared 32 GiB, and
  **firecracker's virtio-block has no discard**, so there is no `fstrim`
  and no `discard` mount option that would return freed blocks. Deleting
  `target/` in the guest frees guest space and nothing host-side. The image
  is a high-water mark; the only reclaim is deleting it, which is also the
  documented way to reset the workspace.

  **Measured, and it climbs fast.** A pre-build capsule is a few hundred MiB,
  and `probe-freshness` has since shown that nearly all of it is *empty
  filesystem* — the ext4 a 32 GiB declaration costs before any content
  exists, plus tens of MiB for the repository. So the starting point is not
  what costs anything. One `just web-build test` took the volume to
  **7.4 GiB**, 6.9 GiB of that `/work/doctrine`, i.e. the checkout plus
  `target/` and `node_modules` — twenty-odd times, from one workload. So the
  per-capsule disk figure is the *volume*, not the store image, and the
  32 GiB cap is a few full builds away rather than theoretical. Nothing here
  is a leak: it is the build tree, kept on purpose, on a filesystem that
  cannot return blocks. Every figure, with how it was taken, is in
  [probes.md](../probes.md).

  **Most of that was the capsule not knowing what machine it was.** Those
  figures predate `target.nix`'s `guestConfig`, so cargo's defaults applied:
  full debuginfo and an incremental cache. With `debug = 0` and
  `incremental = false` the same workload leaves **1.1 GiB** in
  `/work/doctrine`. The shape of this item is unchanged — it still only
  grows, and blocks still never come back — but the rate is roughly six
  times lower, and the fix was config in the closure rather than any
  machinery.

  **Treat either number as a floor and as this target's.** n = 1, on
  doctrine, and cargo does not settle after one build — `target/` accretes
  across profiles, feature sets, dependency bumps and toolchain changes,
  and an agent iterating is the worst case for it. Expect a worked-in rust
  capsule to approach its cap. A target whose build is not rust would look
  nothing like this, which is an argument for `target.sizes.volume` being
  the per-target knob it already is.
- `.vm/host/tinyproxy.log` has no rotation on the foreground path. Small,
  but it is the record of every egress attempt, so truncating it on start
  would be the wrong fix. Rotated (weekly, `copytruncate`) on the unit path
  only — see [item 11](./011-host-side-runs-as-you.md).
