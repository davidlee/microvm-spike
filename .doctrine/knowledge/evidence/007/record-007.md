# EVD-007: The flavour composition costs half a gigabyte of closure

Adding `agents` + `dev-facilities` on top of the target's floor
(`NOTES item 31`): **+0.5 GiB closure, +100.9 MiB erofs**, hand-measured as the
runner closure before/after plus the switch diff, 2026-08-13.

- The **erofs delta is what every slot shares**.
- The **closure delta is what this host stores once**.
- The guest image closure is **12.4 GiB** since the composition, 11.9 GiB before
  it, **~99% shared**. Under netns this is **the** image, once, however many
  capsules run.

The fragments: `claude`, `pi`, `rg`, `fd`, `tree`, `jq`, `bubblewrap`, `helix`,
`tmux`, `btop`, `nushell`.

**No second toolchain came with `llm-agents`** — its `claude-code` landed as
`2.1.224 → 2.1.229`, a version bump, so the pin dedupes against this repo's
nixpkgs rather than doubling it. That is the figure that says a fragment's flake
input is cheap when it shares a nixpkgs and expensive when it does not.

Source: `docs/probes.md`, *Figures*.

Supports `CON-001`: one list for the fleet is what keeps one image, and these are
the numbers per-assignment selection (`IMP-003`) would be spending.
