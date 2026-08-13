# Contract — what a repo must be to be confined

The capsule is the product and the repo it confines is a client, so the
integration surface is worth stating as a contract rather than discovering it
per target. This file is that surface, field by field, in both directions: what
a target must supply, and what it may rely on the capsule to provide.

The *rule* that produced this shape is in [CLAUDE.md](../CLAUDE.md) ("doctrine
is the guinea pig, not the design") and the history is
[item 16](./ledger/016-target-agnostic.md). Neither is restated here. How far
any of it has been exercised is [status.md](./status.md)'s to say; this file
describes the interface, not its state. Usage — the commands in order, with a
live target — is [README.md](../README.md).

doctrine is one instance of this contract, and the other half of *its*
relationship with this repo is [contract-doctrine.md](./contract-doctrine.md).

Two sibling contracts cover what happens once there is more than one of
anything, and neither is built:
[contract-flavour.md](./contract-flavour.md) is where a guest's capabilities and
tool closure come from, and
[contract-assignment.md](./contract-assignment.md) is what a slot is assigned
and who may say so. This file describes today's single-target shape; where each
of its fields is headed is the `owner` column below.

## The floor

*Be a git repo on this host, and expose one flake package for this system that
is your devshell's tool set.* Everything else is a `target.nix` field with a
working absent path, and every one of those fields is **host-side** — nothing is
ever read out of the target repo, because the agent can edit that.

**Stated plainly, because hedging it would mislead: the supported set is
nix-integrated projects.** A target exports a package or it is not a target —
`toolsPackage = null` plus `extraTools` is bare nixpkgs attr names, so a tool
set assembled by a function has no name to give and the absent path is
*structurally* unavailable rather than merely worse
([item 23](./ledger/023-second-target.md)). That is a defensible contract and
this repo commits to it as the current one. Where it is headed is
[contract-flavour.md](./contract-flavour.md): what a target owes is a *floor* —
the fragments it cannot be built or tested without — and exporting a package
your devshell shares becomes the convenient way to supply one rather than the
only way. A floor may be a single reference to a shared base and nothing else,
which is what makes a repo with no flake at all confinable.

Two literals are unavoidable and nothing checks that they agree:

- `inputs.target.url` in `flake.nix` — an input's url cannot be computed.
- `path` in `target.nix` — where `capsule-provision` pushes from.

Switching targets means editing both, or `--override-input target path:/…` for
one build. Renaming the *input* is not free downstream either: the host's own
config (`~/flakes`) carries `inputs.target.follows`, and its next lock fails on
an input that no longer exists.

## Configuration — `target.nix`

`rec`, so the guest paths derive from `name` and `volumePath` rather than being
spelled on both sides.

The `owner` column is an **analysis of what is already here**, not a planned
change: it says which authority each field answers to, and it is the reason a
single file holding all of them is a coupling rather than a convenience.
`profile` is project semantics, `flavour` is the tool closure, `class` is the
machine reservation, `policy` is a host control, `source` is where this host
keeps the repo, and `capsule` marks a field that is not target-shaped at all.
Where each is headed is
[contract-assignment.md](./contract-assignment.md) and
[contract-flavour.md](./contract-flavour.md); nothing about today's shape
changes until they are built.

| field | owner | read by | required | absent path |
| --- | --- | --- | --- | --- |
| `name` | profile | guest (checkout dir, motd), host (`services.capsule-perimeter.repo` default) | yes | — |
| `path` | **source** | host: `capsule-provision`'s source repo | yes | `CAPSULE_REPO`, or the module's `repo` option, overrides it per host — and having two host-side overrides where no other field has any is the tell that it was never project state |
| `volumePath` | capsule | both: the volume's mount point, and what `caches`/`guestConfig`/records resolve against | yes | — |
| `guestPath` | capsule | both: the guest's checkout | derived | — |
| `toolsPackage` | flavour | guest: `packages.<system>.<name>` from the target's own flake | in practice yes | `null` — the guest gets `extraTools` only, and loses the no-drift property that made threading the target's list worth it. **Available only to a target whose whole tool set is a list of nixpkgs attr names**: `extraTools` is a supplement, never a substitute, so anything built by a function — a `python3.withPackages (…)` has no attr name — has to export a package (NOTES item 23) |
| `extraTools` | flavour | guest: nixpkgs attr names, resolved against the *guest's* pkgs | no | `[]` |
| `allowlist` | **policy** | host: the proxy's hostname allowlist, relative to `CAPSULE_ROOT` | yes | — |
| `caches` | profile | guest: env var → directory under the volume, and the dirs the seed creates and chowns | no | `{}` — everything then writes wherever its tool defaults, which for a RAM-backed root means guest RAM |
| `cachePaths` | capsule | guest seed, and `capsule-baseline`'s before/after sizing | derived | — |
| ~~`defaultBranch`~~ | — | — | **no such field** | deleted, and nothing replaces it: the guest's branch is the constant `work`, spelled once in `flake.nix` and threaded to its two consumers — see below |
| `collectMaxPackBytes` | **policy** | host: `capsule-collect`'s `ulimit -f` | yes | — |
| `commands` | profile | guest: the motd's line about the target's own entrypoints | no | `""` |
| `baseline` | profile | host: the command `capsule-baseline` runs in the checkout | no | `null` — the program is not built at all, rather than shipped unable to work |
| `sizes` | class (`vcpu`, `mem`) / volume (`volume`) | guest: `vcpu`, `mem`, `volume`; and whatever `guestConfig` derives from them | yes | — |
| `guestConfig` | profile | guest: path-under-the-volume → file content, rendered into the closure and linked on by the seed | no | `{}` |

**Three rows are the ones the column exists for.** `allowlist` and
`collectMaxPackBytes` are host controls — what a capsule may talk to, and how
much may come back — sitting in the same file as `commands` and a motd string.
That is harmless while a target is a build-time literal and one host has one
allowlist, and it stops being harmless the moment assigning a project is a
run-time verb, because the project would then be naming its own perimeter
([item 25](./ledger/025-assignment-is-a-perimeter-verb.md)).

**And `path` is a third, quieter one.** `/home/david/dev/doctrine` says where
*this host* keeps a checkout; it says nothing about the project, and the
difference shows up the moment there is a second host, a second checkout, or a
controller working from its own clone. It becomes a host-held `profile → source`
binding rather than a profile field
([contract-assignment.md](./contract-assignment.md)) — and, more sharply, one an
assigner may never spell: `capsule-provision` reads that repo **as the human**
([item 11](./ledger/011-host-side-runs-as-you.md)), so a freely-named path is a
local-repository read primitive with a delivery mechanism attached.

**And `defaultBranch` is deleted outright — decided, and now done.** Nothing
replaces it. The guest's branch is the constant `work`, a capsule constant
beside the volume's mount point, and no contract has a field for it. It lives as
`workBranch` in `flake.nix`, which is the wiring layer rather than a fourth
value file: it is not addressing (`net.nix`), not a slot's (`capsules.nix`) and
emphatically not the target's, and its two consumers — the guest's seed and
`capsule-provision` — are both already fed from there.

The first draft of this decision kept an optional `workBranch` on the profile,
on the reasoning that a project might care what its work is called. That is
wrong by one altitude, and the test that shows it is two slices of one project
at once: if a branch name identifies *the work*, it is not a property of the
project, and every capsule on that profile would want a different one. It is not
assignment state either — `capsule-collect` already lands everything as
`refs/capsule/<slot>/*`, so whatever names a piece of work outside this repo can
name it there, at the point where it means something. A capsule needs a base
commit and somewhere local to land commits; it needs neither the target's
canonical branch nor a name for what it is doing.

The mechanics allow it outright. There are exactly two consumers — the guest's
seed (`git init --initial-branch`, `init.defaultBranch`) and `capsule-provision`
(the advertised-symref check, and the push refspec). `capsule-collect` fetches
`+refs/heads/*:refs/capsule/<name>/*` and never reads the field at all, so it is
already branch-agnostic. Both remaining consumers need *a* name and neither
needs *that* name; the symref check is about the seed and the pusher agreeing,
which one shared constant satisfies exactly as well as one shared field.

The two things called "branch" separate cleanly on the way past.
`capsule-provision <ref>` is a ref **in the target repo on this host** — that is
unaffected, still required and still deliberately undefaulted, and it survives
on the assignment as `base.ref` provenance beside the commit it resolved to. The
guest's branch is the other one, and it is the one going.

L13 closes by subtraction, in the strongest form available: the field with no
run-time override does not get one, and does not become a defaulted field
either. It stops existing.

`extraTools = []` is the absent path a second target exercised (NOTES item 23),
and `toolsPackage = null` is the one that turned out to be **narrower than it
looks** — see its row. Still unexercised: `baseline = null`, `caches = {}`,
`guestConfig = {}`. Those are absent paths by construction — read the consumers,
not this table, before relying on one.

### What is deliberately not a target field

- **The allowlist file is host-side, keyed by target.** The tempting version — a
  `.capsule/egress-allow.txt` in the repo being worked on — hands the allowlist
  to the thing being confined. Not directly, since the host reads the human's
  working tree, but one careless merge of collected work and the agent has
  widened its own egress. Same for `sizes` and `guestConfig`.
- **Only the tool set comes from the target**, because it is a build input
  rather than a control. Keep that asymmetry explicit or the perimeter argument
  leaks.
- **`setup.nix` is not target-shaped at all.** Which agent you sign in as is a
  property of you, not of the repo under confinement, so a second target takes
  that list unchanged. Empty is a working value: a capsule with no injections is
  one you log into by hand.

## What the capsule supplies back

A target may rely on all of this. It is `vm/capsule.nix` plus the seed, and it
is the same for every target.

| | what |
| --- | --- |
| checkout | `guestPath`, a git repo, **initially empty** — history arrives by `capsule-provision`, so the base commit is an argument and not a value in the closure |
| `$HOME` | `<volumePath>/home`, on the volume, so agent state survives reboots and dies with a fresh capsule |
| `TMPDIR` | `<volumePath>/tmp`, mode 1777 — on disk, because the guest's root is tmpfs and therefore guest RAM |
| caches | one env var per `caches` entry, pointing at a directory the seed has created and chowned |
| egress | `HTTP(S)_PROXY`/`http(s)_proxy` at the host's allowlist proxy, `NO_PROXY` for the host and loopback. No default route and no resolver in the guest |
| tools | `git`, plus `compose(floor, extras)`: the floor is this repo's — `toolsPackage` + `extraTools` — and the extras are the host operator's, from `fragments.nix`'s vocabulary (`agents`, `dev-facilities`). A target names no convenience and may rely on none ([contract-flavour.md](./contract-flavour.md), [item 31](./ledger/031-the-fragment-vocabulary.md)) |
| git | `user.name`/`user.email` set, `init.defaultBranch` = the constant `work`, and `receive.denyCurrentBranch = updateInstead` so a provision checks out rather than moving a ref |
| static config | every `guestConfig` entry symlinked onto the volume from the closure — a link, so a rebuild replaces it and a fresh capsule cannot start with a stale copy |
| secrets | `<volumePath>/.env`, sourced at login, persisting on the volume — and pushed there at `capsule <name> start` if this host declares a source for it (`setup.nix`, which is not the target's) |
| foreign binaries | a loader for generic-linux dynamically linked executables (nix-ld), so a toolchain that *downloads* a prebuilt binary — a pypi wheel's, an npm package's, a Go module's vendored one — can run it. NixOS ships no `/lib64` loader, and without this the failure is `Could not start dynamically linked executable`, one second into an otherwise healthy run |
| user | `agent`, uid 1000, no sudo and no su; root reachable by key from the host only |

Four limits shape what a `baseline` — or any command run in the guest — can be.
**They are not the same kind of thing, and a target should not come to depend on
the second kind.** An *invariant* is what the confinement claims and will keep
claiming under a different backend; a *current floor* is what this hypervisor
happens to impose, and a seatbelt or VM-based shape
([plan-b-other-jails.md](./plan-b-other-jails.md)) could lift it without any of
the claims changing.

Invariants — these hold whatever runs underneath:

- **No host directory can ever be mounted in.** No shares, no passthrough
  (CLAUDE.md, "Firecracker constraints"). Anything that must get in arrives over
  the link or is in the closure. Firecracker enforces it; the confinement would
  assert it anyway, since a shared directory is a channel the perimeter does not
  mediate.
- **There is no route out except the proxy**, and therefore no host service
  reachable by address. A target whose tests want a database gets it inside the
  guest closure or not at all ([item 4](./ledger/004-live-postgres.md) is this
  gap, open and unhit). What is *not* invariant is that the database cannot be
  in the closure — that is a missing capability, and
  [contract-flavour.md](./contract-flavour.md) is where it would land.

Current floor — true today, and true because of firecracker plus this guest's
construction rather than because of anything the confinement promises:

- **`nix` does not work in the guest.** The store is a generated read-only
  image; a working `nix` needs `writableStoreOverlay` plus its own volume. A
  baseline that shells out to nix cannot pass. This is a construction choice
  with a known price, not a claim.
- **`environment.variables` is login-shell scope.** Anything the target runs as
  a guest unit needs its own environment; `capsule-baseline`'s `bash -l` exists
  for exactly this reason
  ([item 6](./ledger/006-proxy-env-login-shell-scope.md)). NixOS's, not the
  capsule's.

## Commands and arguments at the boundary

Everything crossing the boundary is host-initiated, runs as the human, and takes
the capsule as an argument rather than being built per capsule
([item 20](./ledger/020-which-capsule-a-program-means.md)).

| command | arguments | touches the target repo? |
| --- | --- | --- |
| `capsule-provision` | `[--capsule <name>] <ref> [--force]` — any commit-ish in `path` | yes: reads it, as you. The only program that does |
| `capsule-collect` | `[--capsule <name>]` | no: fetches into a host-authored quarantine named for the capsule |
| `capsule-inject` | `[--capsule <name>] [payload...] [--force]` | no: `setup.nix`'s payloads |
| `capsule-baseline` | `[--capsule <name>] [--detach]` | no: runs `baseline` in the guest's checkout |

`<ref>` is required, and there is nothing left it could be defaulted to: it is
a ref in the *target repo*, and `work` is the guest's branch, which is the whole
separation the deleted field turned on. A capsule's base commit is the one thing
it is pinned to, and it should be stated at every provision.

Environment, in the order a program consults it:

| variable | what |
| --- | --- |
| `CAPSULE_NAME` | which capsule, when `--capsule` is not given. Default is `capsules.default` |
| `CAPSULE_REPO` | overrides `target.nix`'s `path` for `capsule-provision` |
| `CAPSULE_ROOT` | this checkout, for resolving `allowlist` and the default state directory |
| `CAPSULE_STATE` | where quarantines live — `/var/lib/capsule` on the module path, `$CAPSULE_ROOT/.vm/host` otherwise |
| `CAPSULE_ALLOWLIST` | the allowlist file, overriding the target's |

The guest initiates nothing. It has no remote and no route to one, so what used
to be a ref restriction is now the absence of a channel
([item 18](./ledger/018-git-channel-direction.md)). Work leaves as commits,
through `capsule-collect`, into a quarantine repo — including any change the
agent made to files the target treats as its own records.

## Porting to a second target

**Done once, so the price is a diff rather than an argument.** panopticon is the
second target, on branch `second-target` — its cold `just check` is green
through a brand-new allowlist ([item 23](./ledger/023-second-target.md),
[probes](./probes.md#the-cold-build-on-a-second-target)). What that port changed
outside this file: one allowlist file, `inputs.target.url`, and **one guest
capability** — `programs.nix-ld`, because a pypi wheel, an npm prebuild and a Go
module's vendored helper all need a `/lib64` loader and none of them supplies a
different one. Nothing else generic moved. In order:

1. `inputs.target.url` in `flake.nix`, and `path` in `target.nix` — the two
   literals above. Check `~/flakes` if you renamed the input.
2. `name`, `commands`, `baseline`. Not a branch: there is no such field, and
   the guest's is the constant `work` whatever the target calls its own.
3. Its own `allowlist` file. Half of any such list is that target's dependency
   hosts, so it is a new file rather than an edit to doctrine's.
4. `toolsPackage`. `null` plus a filled-out `extraTools` is the absent path on
   paper and is unavailable to most targets in practice — attr names only, so a
   tool set assembled by a function has to become an exported package in the
   *target*, which is where the contract says that cost belongs.
5. `sizes`, and `guestConfig` derived from them — not copied from a human's
   machine, which describes a machine the capsule is not.
6. `caches` for its toolchain, `{}` if it has none.

The likely friction is all in the last three: `extraTools`, `caches` and `sizes`
are doctrine's toolchain wearing a general name — panopticon took half the
memory and a quarter of the volume, which is what inheriting them would have got
wrong. The review question, every time, is CLAUDE.md's: *would a different
target need this code changed, or only a different value?*

Concurrent capsules on *different* targets is a much larger job than a different
one — a different tool set is a different guest image, which is exactly the
sharing the one-image design buys — and it is priced in
[plan-c-multi-capsule.md](./plan-c-multi-capsule.md), not here.
