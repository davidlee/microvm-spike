# NOTES item 23 — a second target, and what the parameterisation actually cost

*State: done on branch `second-target`.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**A second target, and what the parameterisation actually cost.**
[Item 16](./016-target-agnostic.md) claimed the capsule is target-agnostic and
said so honestly: *claimed*, with one target. panopticon is the second, and the
claim's price is now a diff rather than an argument. What changed to confine a
different repo:

- `target.nix`, wholesale — a value.
- one new allowlist file — a value.
- `inputs.target.url` in `flake.nix` — the literal
  [item 16](./016-target-agnostic.md) says cannot be computed.
- one edit **in panopticon**, which is the interesting one, below.

Nothing generic changed. Not `perimeter/`, not `vm/capsule.nix`, not
`host/`, not the justfile, not a program. The switch is a git branch, which
is the right shape for two literals: `second-target` here holds panopticon
and `main` holds doctrine, so neither is a second implementation of the
other. `panopticon` appears in exactly the two places `doctrine` was allowed
to (CLAUDE.md), which is the rule passing rather than being restated.

**The floor held by forcing the target to move.** `toolsPackage` names a
package that *is* the devshell tool set, and panopticon's `packages.default`
is the application — `panopticon-desktop`, carrying no pytest, no ruff and no
`just`, so a `baseline` could not run against it. The obvious fallback is
`toolsPackage = null` plus a filled-out `extraTools`, and that turns out to be
**structurally unavailable**: `extraTools` is `map (name: pkgs.${name})`, bare
nixpkgs attr names, and this target's tool set contains a
`python3.withPackages (…)`, which has no name. So the second target had to
grow the export doctrine already had — the same `projectPkgs` its bwrap jails
and its devshell share, as one `buildEnv`. That is the contract working: the
cost landed on the target, where the floor says it belongs, instead of on a
generic field learning what a python environment is.

Worth being exact about the limit it exposes, since it will recur: **a target
whose tool set is not a list of nixpkgs names has no absent path.** It exports
a package or it is not a target. `extraTools` is a supplement, never a
substitute, and the table in contract-target.md now says so.

**One field a target switch cannot leave to run time: `defaultBranch`.** Every
other host-side value either is not in a program (`sizes`, `caches`,
`guestConfig` are the guest's) or has a run-time override — `path` has
`CAPSULE_REPO` and the module's `repo` option, `allowlist` has
`CAPSULE_ALLOWLIST` and the module's option. `defaultBranch` is interpolated
straight into `capsule-provision` and `capsule-collect`, so the *module path's*
copies still say `edge` until the host is rebuilt, and a provision of
panopticon's `main` against them refuses — correctly, and with a clear
message, since the guest's HEAD says `main` and the program checks that
symref. Recorded rather than fixed: the asymmetry is invisible until someone
ports a target, which is what this item is, and an override would be a third
way to say which branch when the honest answer is that switching targets is
a rebuild. What is *not* acceptable is discovering it during the rebuild, so
it is in the table.

**`guestConfig` already reached `$HOME`, and nobody designed that.** Its keys
are paths under `volumePath` and `$HOME` is `<volumePath>/home`, so a
user-level `uv.toml` is a `guestConfig` entry with no new field and no change
to the seed, which already `install -d`s each parent. That closes a gap this
port would otherwise have opened: `uv` defaults to *downloading* an
interpreter, and a capsule fetching 30 MiB of python-build-standalone through
an allowlist proxy — when its own tool set puts 3.12 on `PATH` — is a config
describing a machine the capsule is not, which is CLAUDE.md's third failure
wearing a different toolchain's clothes. `python-downloads = "never"` is also
why panopticon's allowlist needs no GitHub release host for its build.

So both halves of that field are exercised now, and they are different halves:
doctrine's cargo config is **derived from the declared reservation**,
panopticon's uv config is **pure policy**. The generic capability is
*render static guest config*; neither instance taught it a toolchain.

**Which absent paths this did and did not exercise.** `extraTools = []` is
now real — panopticon's list is self-contained because it was built for jails
that bind no host toolchain. Still unexercised: `baseline = null`,
`caches = {}`, `guestConfig = {}`. The last of those was available and
deliberately not taken — a uv capsule with no `uv.toml` works, it just pays
for an interpreter it already has — because a probe that passes by declining
the useful configuration is not evidence about the useful configuration.

**The one thing that did need generic code, and it is not a value.** The
first baseline failed in one second, exit 127, after doing everything else
right: uv used the tool set's own interpreter (so the `uv.toml` above worked
and no python was downloaded), resolved 31 packages from pypi through the
proxy (so a brand-new allowlist was live-tested and correct), built the
project — and then could not *exec* the `ruff` it had just installed.
`Could not start dynamically linked executable`: NixOS ships no
`/lib64/ld-linux-x86-64.so.2`, and a pypi wheel carries a binary built for
generic linux. The host runs the identical command daily because the host has
`programs.nix-ld`; the guest did not.

The tempting fixes are all wrong in the same direction. Making the target's
`baseline` call the nix `ruff` instead of `uv run`'s would have the capsule
running a command the repo does not, which is a worse test than a failing one.
A `target.nix` field would make it look parameterised when it is not: **every
non-nix-native toolchain needs this and none of them supplies a different
value for it** — npm's prebuilds and a Go module's vendored helper fail
identically. So it goes in `vm/capsule.nix`, beside `TMPDIR` and the caches,
as something the capsule *supplies*; doctrine never hit it only because cargo
links against nix's own stdenv.

Worth stating plainly, because it is the honest score for this item: the port
changed **one** thing outside `target.nix` and the allowlist, and that one
thing is a guest capability rather than a target-shaped leak. It widens
nothing outward — the perimeter is host-side, and a guest carrying a compiler
could already run whatever it built; this only stops the kernel refusing an
interpreter that is absent for packaging reasons.

**It is green.** `just check` cold on a fresh volume: 3 s, exit 0, 327 passed
and 3 skipped, 31 packages fetched from pypi through a brand-new allowlist on
the first try, and no interpreter downloaded. Figures in
[probes.md](../probes.md#the-cold-build-on-a-second-target). The one that
changes an existing claim is the ratio: doctrine's cold build is ~93% of
time-to-interactive, and this one is 3 s against an 8.31 s boot, so **the
largest term in time-to-interactive is target-shaped** and nothing generic
should be tuned against either number.

**And it corrected an instrument, which is the second time a second thing has
done that here.** `capsule-baseline` measured its paths in one `du -sm`, and
`du` charges a hardlinked inode to whichever argument came first. uv hardlinks
its `.venv` out of its cache, so the record read checkout 105 MiB / cache
4 MiB where the trees are 8 and 97. The total was right throughout — a volume
pays for an inode once — but the *split* is what the coldness proof is
arithmetic on (cache-after must exceed all-caches-before), and at 4 against 4
this run could not have proven its own coldness. `sizes()` now asks each path
separately while `total()` keeps the single invocation, so the two answer
their own questions and no longer necessarily sum. Same family as the slice's
`memory.peak` outliving its units: **an instrument calibrated on one target is
a thing a second target reads wrong**, and cargo sharing no inodes between
`target/` and `.cargo` is the only reason this stood for as long as it did.

**One risk this cannot answer before it builds.** panopticon's own `.envrc`
is `use flake . --impure`, and a flake *input* is evaluated purely. If any
attribute the capsule needs were impure the repo could not be a target at
all, with no workaround on this side. `dev-tools` should be pure — the jail
library that wants the environment is only forced by `packages.jailed-*` —
but "should be" is what a build is for. If a future target does need impurity
in its tool set, the answer is a pure attribute in that repo, not `--impure`
here: this flake builds a confinement, and an impure one cannot be pinned.

**One trap the switch itself set, found by accident.** `.envrc` is
`use flake`, so direnv relocks on every entry into this checkout — and with
the target's working tree dirty, nix locks the *dirty tree* and records a
`dirtyRev` rather than refusing. So a target switch will happily write an
unreproducible `flake.lock`, from a shell prompt, with no command run. Commit
in the target *first*, then relock; and check `git diff flake.lock` for
`dirtyRev` before committing one. The upside of the same accident is free
evidence: the lock resolved, so panopticon's whole input closure is
fetchable — which is the cheapest half of the impurity question above
answered without a build.

Two smaller notes, both values doing their job. `sizes` went to half the
memory and a quarter of the volume, because a pytest suite has no `target/`
and the two things that grow are `.venv` and the uv cache — a second target
inheriting doctrine's numbers would have been the same failure as copying a
human's machine. And doctrine's allowlist keeps the name
`perimeter/egress-allow.txt` while this one is
`perimeter/egress-allow-panopticon.txt`: the convention going forward is a
file named for its target, and the first one is grandfathered rather than
renamed, because its name is spelled in seven documents and a rename buys
nothing a comment does not.
