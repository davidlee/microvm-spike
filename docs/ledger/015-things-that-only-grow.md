# NOTES item 15 — things that only grow: the volume, the proxy log, and a document

*State: two measured and accepted, one fixed
([item 54](./054-status-grew-a-changelog.md)).*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Things that only grow.** None of them can exhaust the host — worth saying,
since "unbounded" is the wrong word — but none ever gives space back. The first
two are disk and are accepted; the third is a document, and it is the one that
turned out to be fixable, because a document's eviction rule is a sentence
rather than a filesystem feature.
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
- **[status.md](../status.md) reached 2463 lines**, 29% of it a
  reverse-chronological changelog of fourteen sessions in the one file whose
  contract is the present tense — and in a repo whose
  [index](../index.md) says there is no changelog. Fixed rather than accepted:
  five recent entries, evicting, with the rule written into the file
  ([item 54](./054-status-grew-a-changelog.md)).

- **[ledger/index.md](./index.md) reached 57 KB in 79 lines**, with one table
  cell at **10,618 characters** — longer than several of the items it indexes,
  in a file whose own header promises that reading one item costs one item. Cut
  back the same day, with the bound written into that header.

**Three kinds, and only the first two are about storage.** The distinction is
what makes this item worth citing:

1. **Nothing can return the space.** The volume and the proxy log. Measure the
   rate, accept it, and revisit only if the rate changes — neither can be argued
   out of growing.
2. **Nothing says what leaves.** status.md. An eviction rule costs one sentence,
   and its absence is what let fourteen sessions accumulate one entry at a time
   with no diff big enough to notice.
3. **Nothing bounds an entry, and the last one is visible.** The ledger index.
   Nothing here accumulates — each row is written once and never touched again.
   It grew because every new row was calibrated against the row above it, so the
   average climbed from 145 characters over items 1–35 to 2,662 over 36–54 with
   no single edit that looked wrong. **This is the one with no diff to catch it
   and no total to watch**, because the file's line count never moved: 79 lines
   before and after. It is also the one that generalises to the next table
   somebody adds.

Before accepting the next thing that only grows, work out which kind it is.
Only the first is a fact about the world.
