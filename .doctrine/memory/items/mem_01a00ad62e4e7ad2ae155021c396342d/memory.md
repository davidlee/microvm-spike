Push **any other branch** and the ref lands while the worktree is untouched,
**silently**.

The seed sets `--initial-branch` and `capsule-provision` verifies the advertised
symref for exactly this reason; do not remove either.

**An empty repo advertises no symref at all**, so the check cannot cover the
first provision — the seed is what does.