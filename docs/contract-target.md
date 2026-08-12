# Contract — what a repo must be to be confined

The capsule is the product and the repo it confines is a client, so the
integration surface is worth stating as a contract rather than discovering it
per target. This file is that surface, field by field, in both directions: what a
target must supply, and what it may rely on the capsule to provide.

The *rule* that produced this shape is in [CLAUDE.md](../CLAUDE.md) ("doctrine is
the guinea pig, not the design") and the history is [notes](./notes.md) item 16.
Neither is restated here. How far any of it has been exercised is
[status.md](./status.md)'s to say; this file describes the interface, not its
state. Usage — the commands in order, with a live target — is
[README.md](../README.md).

doctrine is one instance of this contract, and the other half of *its*
relationship with this repo is [contract-doctrine.md](./contract-doctrine.md).

## The floor

*Be a git repo on this host, and expose one flake package for this system that is
your devshell's tool set.* Everything else is a `target.nix` field with a working
absent path, and every one of those fields is **host-side** — nothing is ever
read out of the target repo, because the agent can edit that.

Two literals are unavoidable and nothing checks that they agree:

- `inputs.target.url` in `flake.nix` — an input's url cannot be computed.
- `path` in `target.nix` — where `capsule-provision` pushes from.

Switching targets means editing both, or `--override-input target path:/…` for
one build. Renaming the *input* is not free downstream either: the host's own
config (`~/flakes`) carries `inputs.target.follows`, and its next lock fails on an
input that no longer exists.

## Configuration — `target.nix`

`rec`, so the guest paths derive from `name` and `volumePath` rather than being
spelled on both sides.

| field | read by | required | absent path |
| --- | --- | --- | --- |
| `name` | guest (checkout dir, motd), host (`services.capsule-perimeter.repo` default) | yes | — |
| `path` | host: `capsule-provision`'s source repo | yes | `CAPSULE_REPO`, or the module's `repo` option, overrides it per host |
| `volumePath` | both: the volume's mount point, and what `caches`/`guestConfig`/records resolve against | yes | — |
| `guestPath` | both: the guest's checkout | derived | — |
| `toolsPackage` | guest: `packages.<system>.<name>` from the target's own flake | no | `null` — the guest gets `extraTools` only, and loses the no-drift property that made threading the target's list worth it |
| `extraTools` | guest: nixpkgs attr names, resolved against the *guest's* pkgs | no | `[]` |
| `allowlist` | host: the proxy's hostname allowlist, relative to `CAPSULE_ROOT` | yes | — |
| `caches` | guest: env var → directory under the volume, and the dirs the seed creates and chowns | no | `{}` — everything then writes wherever its tool defaults, which for a RAM-backed root means guest RAM |
| `cachePaths` | guest seed, and `capsule-baseline`'s before/after sizing | derived | — |
| `defaultBranch` | both: the guest's `init.defaultBranch` and initial HEAD, the branch `capsule-provision` lands on and verifies | yes | — |
| `collectMaxPackBytes` | host: `capsule-collect`'s `ulimit -f` | yes | — |
| `commands` | guest: the motd's line about the target's own entrypoints | no | `""` |
| `baseline` | host: the command `capsule-baseline` runs in the checkout | no | `null` — the program is not built at all, rather than shipped unable to work |
| `sizes` | guest: `vcpu`, `mem`, `volume`; and whatever `guestConfig` derives from them | yes | — |
| `guestConfig` | guest: path-under-the-volume → file content, rendered into the closure and linked on by the seed | no | `{}` |

Only `toolsPackage`'s absent path has been exercised. The rest are absent paths
by construction — read the consumers, not this table, before relying on one.

### What is deliberately not a target field

- **The allowlist file is host-side, keyed by target.** The tempting version — a
  `.capsule/egress-allow.txt` in the repo being worked on — hands the allowlist to
  the thing being confined. Not directly, since the host reads the human's working
  tree, but one careless merge of collected work and the agent has widened its own
  egress. Same for `sizes` and `guestConfig`.
- **Only the tool set comes from the target**, because it is a build input rather
  than a control. Keep that asymmetry explicit or the perimeter argument leaks.
- **`setup.nix` is not target-shaped at all.** Which agent you sign in as is a
  property of you, not of the repo under confinement, so a second target takes
  that list unchanged. Empty is a working value: a capsule with no injections is
  one you log into by hand.

## What the capsule supplies back

A target may rely on all of this. It is `vm/capsule.nix` plus the seed, and it is
the same for every target.

| | what |
| --- | --- |
| checkout | `guestPath`, a git repo, **initially empty** — history arrives by `capsule-provision`, so the base commit is an argument and not a value in the closure |
| `$HOME` | `<volumePath>/home`, on the volume, so agent state survives reboots and dies with a fresh capsule |
| `TMPDIR` | `<volumePath>/tmp`, mode 1777 — on disk, because the guest's root is tmpfs and therefore guest RAM |
| caches | one env var per `caches` entry, pointing at a directory the seed has created and chowned |
| egress | `HTTP(S)_PROXY`/`http(s)_proxy` at the host's allowlist proxy, `NO_PROXY` for the host and loopback. No default route and no resolver in the guest |
| tools | `toolsPackage` + `extraTools` + `git` + `claude-code` where nixpkgs has it |
| git | `user.name`/`user.email` set, `init.defaultBranch` = `defaultBranch`, and `receive.denyCurrentBranch = updateInstead` so a provision checks out rather than moving a ref |
| static config | every `guestConfig` entry symlinked onto the volume from the closure — a link, so a rebuild replaces it and a fresh capsule cannot start with a stale copy |
| secrets | `<volumePath>/.env`, sourced at login, persisting on the volume |
| user | `agent`, uid 1000, no sudo and no su; root reachable by key from the host only |

Four limits that shape what a `baseline` — or any command run in the guest — can
be, all of them firecracker's floor rather than choices:

- **No host directory can ever be mounted in.** No shares, no passthrough
  (CLAUDE.md, "Firecracker constraints"). Anything that must get in arrives over
  the link or is in the closure.
- **`nix` does not work in the guest.** The store is a generated read-only image;
  a working `nix` needs `writableStoreOverlay` plus its own volume. A baseline
  that shells out to nix cannot pass.
- **There is no host service to reach.** A target whose tests want a database get
  it inside the guest closure or not at all — the proxy is HTTP egress, not a
  route ([notes](./notes.md) item 4 is this gap, open and unhit).
- **`environment.variables` is login-shell scope.** Anything the target runs as a
  guest unit needs its own environment; `capsule-baseline`'s `bash -l` exists for
  exactly this reason ([notes](./notes.md) item 6).

## Commands and arguments at the boundary

Everything crossing the boundary is host-initiated, runs as the human, and takes
the capsule as an argument rather than being built per capsule
([notes](./notes.md) item 20).

| command | arguments | touches the target repo? |
| --- | --- | --- |
| `capsule-provision` | `[--capsule <name>] <ref> [--force]` — any commit-ish in `path` | yes: reads it, as you. The only program that does |
| `capsule-collect` | `[--capsule <name>]` | no: fetches into a host-authored quarantine named for the capsule |
| `capsule-inject` | `[--capsule <name>] [payload...] [--force]` | no: `setup.nix`'s payloads |
| `capsule-baseline` | `[--capsule <name>] [--detach]` | no: runs `baseline` in the guest's checkout |

`<ref>` is required and deliberately not defaulted to `defaultBranch`: a
capsule's base commit is the one thing it is pinned to, and it should be stated
at every provision.

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
([notes](./notes.md) item 18). Work leaves as commits, through `capsule-collect`,
into a quarantine repo — including any change the agent made to files the target
treats as its own records.

## Porting to a second target

Untested, and the parameterisation is only *claimed* until one exists. In order:

1. `inputs.target.url` in `flake.nix`, and `path` in `target.nix` — the two
   literals above. Check `~/flakes` if you renamed the input.
2. `name`, `defaultBranch`, `commands`, `baseline`.
3. Its own `allowlist` file. Half of any such list is that target's dependency
   hosts, so it is a new file rather than an edit to doctrine's.
4. `toolsPackage`, or `null` and a filled-out `extraTools`.
5. `sizes`, and `guestConfig` derived from them — not copied from a human's
   machine, which describes a machine the capsule is not.
6. `caches` for its toolchain, `{}` if it has none.

The likely friction is all in the last three: `extraTools`, `caches` and `sizes`
are doctrine's toolchain wearing a general name. The review question, every time,
is CLAUDE.md's: *would a different target need this code changed, or only a
different value?*

Concurrent capsules on *different* targets is a much larger job than a different
one — a different tool set is a different guest image, which is exactly the
sharing the one-image design buys — and it is priced in
[plan-c-multi-capsule.md](./plan-c-multi-capsule.md), not here.
