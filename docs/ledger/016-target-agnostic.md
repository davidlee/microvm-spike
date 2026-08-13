# NOTES item 16 — target-agnostic

*State: done, and a second target has since exercised it — [item 23](./023-second-target.md).*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Target-agnostic — done for one target at a time.** Nothing structural tied the
confinement to doctrine. The perimeter was already target-blind, and is more so
since [item 18](./018-git-channel-direction.md) — it holds no repo path at all
now, only the allowlist — and `host/services.nix` took `repo` as an option. What
was actually hardcoded was smaller than it looked — the string `doctrine` in
`vm/capsule.nix` (checkout dir, clone URL, motd), the input's name in
`flake.nix`, doctrine-shaped defaults in `perimeter/default.nix` and `justfile`,
and a handful of guest settings that are really *toolchain* settings:
`CARGO_HOME`, `BUN_INSTALL_CACHE_DIR`, `init.defaultBranch = "edge"`,
`pkg-config`/`openssl`, the vcpu/mem/volume sizes, and half the allowlist.

**What it became:** `target.nix`, the shape `net.nix` already established —
`{name, path, toolsPackage, extraTools, allowlist, caches, defaultBranch,
commands, sizes}` — imported by `flake.nix` and threaded via `specialArgs`
alongside `net`, with every literal above derived from it. `perimeter/` gained
two arguments (`repo`, `allowlistFile`) and lost two doctrine defaults, which
is the same move as `bind`/`client`: a value from the call site, not knowledge
in the library. `justfile` grew `_target` beside `_net`. `caches` is one
declaration serving both the guest's env vars and the directories the seed
service must create; it used to be two lists that could disagree. Net effect
on size is roughly nil, and `doctrine` now appears in exactly two places —
`target.nix`, and the input url it cannot be removed from.

Three things decided the shape, and they are not the code:

- **A flake input cannot be computed.** `inputs.<name>.url` must be a
  literal, so the target's flake ref stays spelled in `flake.nix` no matter
  how much else is parameterised: `inputs.target.url` and `target.nix`'s
  `path` name the same repo and nothing checks that they agree. Swapped by
  editing both, or by `--override-input target path:…` for one build. Which
  means the win is "this repo does not *name* doctrine", not "targets are
  data". Renaming that input is also not free downstream — `~/flakes` carries
  `inputs.target.follows = "nixpkgs"` and had to be edited in the same
  breath, or its next lock fails on an input that no longer exists.
- **Per-target policy must not live in the target repo.** The tempting version —
  `.capsule/egress-allow.txt` in the repo being worked on — hands the allowlist
  to the thing being confined. Not directly, since the host reads the human's
  working tree — but one careless merge of collected work and the agent has
  widened its own egress. The allowlist and the sizes are host-side config keyed
  by target name; only the *tool set* comes from the target, because that is a
  build input rather than a control. Keep that asymmetry explicit or the whole
  perimeter argument leaks.
- **One target chosen ≠ several at once.** The parameterised single-target
  version is what got built, and it is an afternoon. What the other one costs is
  now written down — [Plan C](../plan-c-multi-capsule.md), which starts from the
  observation that the guest's address lives in its *closure*, so N capsules
  naively means N store images. *Concurrent* capsules is a different job:
  `net.nix` becomes per-instance (tap name, /30, MAC, two ports each), the units
  become templates (`capsule-proxy@<target>`) with a uid pair each, and the
  host's own config grows a per-tap nftables drop and per-interface ports — i.e.
  it reaches into `~/flakes`, which is the part this repo cannot install for
  itself ([item 7](./007-host-config.md)). Don't buy the second while pricing
  the first.

The contract, written down: *be a git repo on this host, and expose one flake
package for this system that is your devshell's tool set* (doctrine:
`packages.dev-tools`). Everything else about the target is optional and
host-side. `toolsPackage = null` still works — the guest then gets
`extraTools` from this repo's nixpkgs and loses the no-drift property that
made threading the target's own list worth it.

~~Untested: a second target. The parameterisation is only *claimed* until one
exists~~ — **tested, by [item 23](./023-second-target.md)**: panopticon, and the
friction landed exactly where this paragraph guessed. `extraTools`, the cache
set and the sizes were all this target's toolchain wearing a general name, and
one of them was worse than that — `toolsPackage = null` plus `extraTools` is not
a usable absent path for a tool set that is not a list of nixpkgs attr names.
