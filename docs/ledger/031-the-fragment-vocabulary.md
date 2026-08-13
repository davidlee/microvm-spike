# NOTES item 31 — the fragment vocabulary: composition built, selection deferred

*State: built, unrun — the image has not been rebuilt on this host yet.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What was asked, and what it turned into

A slot about to take a real workload wanted amenities — tmux, an editor, `rg`.
Three obvious homes, and two of them are wrong:

- **`target.nix`'s `extraTools`.** Wrong by ownership. That field is "tools the
  *target's* list assumes the host already has"; `tmux` is nobody's project, and
  putting it there says doctrine needs it. The smell CLAUDE.md names is a
  toolchain's name outside `target.nix`; this is the same rule from the other
  side — a *non*-toolchain's name inside it.
- **`vm/capsule.nix`'s `systemPackages`.** Wrong by precedent, and it is where
  `claude-code` already was. It works, and it makes the convenience/floor split
  implicit exactly where [contract-flavour.md](../contract-flavour.md) says the
  split is the whole design.
- **A host-declared vocabulary**, which is what the contract already specified
  and nothing had built.

So the amenities paid for the first limb of the flavour contract rather than
being pasted somewhere. What is built is `compose(floor, extras)`:
[`fragments.nix`](../../fragments.nix) is the vocabulary, `extras` in
`flake.nix` is the selection, and `vm/capsule.nix` composes the two. The
`claude-code` line is absorbed rather than left beside it — one construction,
not two, which is the same rule the `observe` argument cost a rebuild to learn.

## What it deliberately does not buy

**Selection is fleet-wide.** `extras` is one list, so every slot composes to one
image and the one-image lever is untouched ([item 21](./021-declared-capsule-flake-attribute.md)).
Per-assignment extras — and with them the record's inert `image` field, the
gcroot that retains a resolved image, and the refusal to change a composition
under a dirty volume — are [Plan D](../plan-d-fleet.md) D7. A per-slot list is
this value moving into `capsules.nix` or the record, not a mechanism anything
here has to grow.

**No capability fragment.** The contract's fragment is packages *plus* guest
capability, and `programs.nix-ld` is its standing example — but that one is
already decided the other way: every non-nix-native toolchain needs it
identically, so it belongs in what the capsule supplies
([item 23](./023-second-target.md)). Nothing else has asked. The shape is
`{packages = …;}`, an attrset rather than a bare list, so `guestModule` has a
place the day something wants one. Building the half nothing needs would be a
limb with no case to keep it honest.

**No store-path identity.** "A flavour is identified by its store path" is the
contract's, and it wants a composition that *is* one artifact. Today the guest's
`systemPackages` is a list, as it always was. Wrapping it in a `buildEnv` to
mint a path would nest an env inside an env for a reader that does not exist
yet; D7 is where the reader arrives.

## Where the agents come from, and why not through `pub`

`claude` and `pi` come from `inputs.llm-agents` directly. The ask was
`~/flakes/pub`'s `jailed-agents#unjailed`, and that attrset is literally
`inherit (llm-agents.packages.${system}) claude-code pi` — same derivations,
same numtide cache. Going through `pub` would have added five entries to this
repo's lock (`pub`, its nixpkgs, `flake-utils`, `jail-nix`, and an
`emacs-overlay` tarball) for zero difference in the closure.

That is the contract's own arithmetic, and it is worth stating as a rule rather
than as a preference: **the unavoidable literal is per tool *source***, so a
vocabulary should register the source it actually consumes and not the flake
that re-exports it. `llm-agents` is not pinned to this repo's nixpkgs on
purpose — these are prebuilt against their own pin, and `follows` would rebuild
them here for nothing.

The jailed wrappers stay out, as they always have: they bind *host* paths this
guest does not have, and the capsule's confinement is the VM.
`pkgs.bubblewrap` is in the `agents` fragment for the opposite case — an agent
jailing its own subprocesses inside the guest, over guest paths. **Untested**:
bwrap needs unprivileged user namespaces, and this guest runs
`security.lockKernelModules` with `protectKernelImage`.

## What this supersedes

[item 3](./003-claude-code-unfree.md) — `pkgs.claude-code` and the
`allowUnfreePredicate` that named it are both gone from `vm/capsule.nix`. The
derivation is created in llm-agents' own eval now, so this repo's nixpkgs config
does not gate it and a predicate naming it would be dead config. The channel-drift
guard (`lib.optional (pkgs ? claude-code)`) goes with it: an input's package
either exists at the pinned revision or the eval says so, which is a better
failure than silently shipping a guest with no agent in it.

## Cost, and what is unmeasured

A second nixpkgs is now in the guest closure — llm-agents' pin, for the two
agent CLIs. The image is ~3.0 GiB today ([probes](../probes.md#figures)) and
disk is the binding constraint here, so the delta is worth reading off the next
build rather than assumed. Nothing has built it yet.

The refusal was watched failing before it was kept: a misspelt fragment name
evaluates to
`fragments.nix: no fragment named 'dev-faciltiies' — the vocabulary is agents,
dev-facilities`, which is the check this file's one branch exists for.
