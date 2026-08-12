# Design — the shape, and why it is this shape

The rationale for what is built. What the boundary is worth is
[threat-model.md](./threat-model.md); the open questions and the resolved ones
are the numbered ledger in [notes.md](./notes.md); usage is
[README.md](../README.md).

A **capsule**: a firecracker microVM used as an agent jail. It holds a real
git clone of one target repo (`target.nix`; here `~/dev/doctrine`), can run that
project's build and tests, and has exactly enough network for a coding agent to
work — no more.

## Layout

| path                         | what                                               |
| ---------------------------- | -------------------------------------------------- |
| `flake.nix`                  | VMs, devshell, tap + runner scripts, module exports |
| `net.nix`                    | tap name, both addresses, MAC, ports — single source |
| `target.nix`                 | which repo is confined, and everything target-shaped |
| `capsules.nix`               | which capsules exist — namespace, socket, uplink, and the default name |
| `justfile`                   | the gate (`just check`) + the multi-command questions |
| `perimeter/default.nix`      | `proxy` + `capsule-host`. Jail-agnostic            |
| `perimeter/egress-allow.txt` | proxy hostname allowlist — plain file, no rebuild. Per target |
| `host/programs.nix`          | the four programs the human runs at a capsule, built once per path |
| `host/guest-ssh.nix`         | how the host reaches a guest, and which capsule it means (`--capsule`) |
| `host/git-channel.nix`       | `capsule-provision` / `capsule-collect`. Host-initiated git |
| `host/perimeter-check.nix`   | is the host's nftables drop loaded? Linux-shaped, injected |
| `host/services.nix`          | the same proxy as a unit under its own uid. Opt-in  |
| `vm/common.nix`              | shared guest config (firecracker, serial console)   |
| `vm/hello.nix`               | smoke test VM, no network                           |
| `vm/capsule.nix`             | the agent jail                                      |
| `.vm/<name>/`                | per-VM state: volume images, API socket (gitignored)|
| `.vm/host/`                  | proxy config + logs, `collect/` quarantines (gitignored) |
| `probe/harness.sh`           | check/observe/measure/report + the capsule-in-a-namespace boot, prepended to each probe at build |
| `probe/netns.sh`             | is a netns per capsule sound? kept as evidence — `sudo probe-netns` |
| `probe/netns-boot.sh`        | does firecracker boot with its tap in one? (yes) — `sudo probe-netns-boot` |
| `probe/freshness.sh`         | what does a *fresh* capsule cost, and which axes hold? — `sudo probe-freshness` |
| `docs/`                      | everything but usage and the agent rules — [docs/index.md](./index.md) is the map |

The split is load-bearing, not tidiness: the perimeter is where nearly all the
policy lives and it is the only part that ports to a non-firecracker jail
([plan-b-other-jails.md](./plan-b-other-jails.md)). It takes addresses and ports
as arguments and one injected `preflight` fragment — on firecracker, the tap-address check — so nothing
hypervisor- or platform-shaped leaks into it. Runtime paths are environment
(`CAPSULE_ROOT`, `CAPSULE_STATE`, `CAPSULE_ALLOWLIST`, `CAPSULE_REPO`), which
is what keeps the allowlist an editable file rather than a store path. Which
repo is confined reaches it the same way as the addresses do — as a value from
the call site, from `target.nix` ([notes](./notes.md) item 16).

## Running

Kept short and deliberately duplicated — [README.md](../README.md) "Quickstart"
and "Commands" are the full version, and are what to edit.

```
direnv allow
capsule-net up      # one sudo: creates the tap, owned by you
capsule-host        # foreground: the egress proxy
vm capsule          # another terminal
capsule-provision edge   # the guest boots empty; this gives it history
```

`vm capsule` *is* the console — firecracker attaches its serial line to your
terminal, and the guest autologins `agent` on it. Ctrl-C kills the VM, so give
it its own tmux window. `poweroff` to leave.

For further sessions: `ssh agent@10.99.0.2` from the host (key auth only,
`id.pub`, root login refused). Host keys live on the volume so known_hosts
stays stable across boots.

`vm hello` first if you want to prove firecracker boots before debugging
anything else. `capsule-net down` removes the tap.

## The confinement shape

**Link.** One point-to-point tap, `10.99.0.1/30` (host) ↔ `10.99.0.2/30`
(guest). No bridge, no LAN exposure, **no NAT and no default route in the
guest**. The guest cannot originate traffic anywhere except the host end of
the /30.

**Egress.** tinyproxy on the host, `FilterDefaultDeny Yes` over
`perimeter/egress-allow.txt` (hostnames, extended regex). The guest gets
`HTTPS_PROXY` and no resolver at all — `services.resolved.enable = false`, since
networkd otherwise leaves a stub on 127.0.0.53 that has no upstream it can reach
and so answers nothing while still answering. DNS happens in the proxy, as the
host, which means guest lookups inherit the host's resolver chain (here resolved
-> stubby -> ControlD over DoT) and nothing guest-side can route around it. So a
name
that is not on the list cannot even be resolved, let alone reached. IP-level
allowlisting was rejected: `api.anthropic.com` is CDN-fronted with rotating
addresses.

**What the allowlist is not.** It is a *destination* control, not an exfil
control, and the difference is structural: filtering happens on the CONNECT
hostname, and everything after that is TLS the proxy cannot read. `github.com`
and `api.anthropic.com` are both full-duplex channels, so anything on the list
is a way out for data as well as a way in for code. What the allowlist buys is
the elimination of accidents and casual beaconing — a typo'd domain, a
postinstall script phoning home, a dependency's telemetry — plus a log of
every attempt. Going further would mean MITM (own CA in the guest,
mitmproxy-style), which trades a small gain for a large amount of machinery
and a guest that trusts a host-held signing key. Not worth it.

**Git.** Host-initiated, both directions, over the ssh channel — no service,
no mirror, nothing for the guest to reach. `capsule-provision <ref>` pushes any
commit-ish from `~/dev/doctrine` onto the guest's working branch;
`capsule-collect` fetches the guest's refs into a quarantine repo under
`.vm/host/collect/`. [NOTES item 18](./notes.md) is the measurement and the
reasoning.

- The guest boots with an **empty repository** and no history until you provision
  it, which is what makes the base commit an argument rather than a value in the
  guest's closure.
- `receive.denyCurrentBranch=updateInstead` in the guest is what turns the push
  into a checkout. It governs only the branch the guest's HEAD names, so the
  seed sets `--initial-branch` and provision verifies the advertised symref
  before pushing — otherwise a push lands history and leaves the worktree alone,
  silently.
- A provision is refused rather than forced when it would discard the guest's
  commits, and refused by the guest while its worktree is dirty.
- Collection is `--no-tags` into `refs/capsule/<name>/*` with
  `transfer.fsckObjects`: the host names the destination namespace, and tag
  auto-following is the one way the guest could otherwise choose where its refs
  land. Then `just fetch` is the second step into the repo you work in.
  Which lines up with SPEC-012's merge-safety-by-absence: the agent has no path
  to the coordination tier, physically — and now no channel to it either.

**State.** One 32 GiB sparse volume at `/work`: the checkout, `target/`,
`TMPDIR`, cargo + bun caches. Survives reboots. Deliberately not on the
rootfs — microvm.nix roots are tmpfs, i.e. guest RAM.

## Why firecracker forces this

`lib/runners/firecracker.nix:86` in microvm.nix:

```
else if shares != []
then throw "9p/virtiofs shares not implemented for Firecracker"
```

Same for device passthrough, balloon, hotplug memory. Firecracker also has no
user-mode networking — tap only, which is why `capsule-net` needs one sudo.
(qemu and kvmtool do have user-net *and* virtiofs, which would remove the host
setup entirely at the cost of the isolation story and of any real egress
control.) Consequences: guest `/nix/store` is a generated disk image, nothing
host-side can be mounted in, and the only channels into the VM are the tap and
the volume.

microvm.nix has **no jailer support** — firecracker runs unwrapped. What that
does and does not cost is worth being exact about, because the obvious reading
overstates it:

- **Seccomp is still on.** Firecracker installs its default filter in-process
  at startup; losing it needs an explicit `--no-seccomp`, which nothing here
  passes. (`firecracker --help`: "allows starting and using a microVM without
  seccomp filtering. Not recommended.")
- **What the jailer would add** is chroot/pivot_root, a network namespace,
  cgroup limits, and a uid drop.
- **Consequence, and it is the real one:** firecracker runs as *you*, uid 1000,
  with ambient access to `~/.ssh`, `~/.claude`, every repo and every shell rc.
  A VMM escape lands directly on the assets the capsule exists to protect.
  Second consequence: no `MemoryMax`/`CPUQuota`/`TasksMax`, so whatever
  `target.sizes` declares is the guest's to abuse — and, memory being a ceiling
  the guest converges on rather than a charge at boot ([probes](./probes.md)),
  abusing it is the only way to pay for it. See [notes](./notes.md) items 11-12.

Also note microvm.nix appends **`--enable-pci`** unconditionally for
firecracker ≥ 1.13 (`lib/runners/firecracker.nix`), and `firecracker.extraArgs`
can only append, so there is no opting out short of pinning
`microvm.firecracker.package` to an older release. PCIe is the newest device
code in firecracker and is opt-in at its CLI; this config therefore takes the
less-exercised transport by default rather than the long-fuzzed MMIO one.

## Guest user model

The agent runs as `agent` (uid 1000, matching the host user so ownership reads
correctly if the volume is ever inspected from outside — see the warning below
about *how*), with **no sudo and no su**. Root is reachable only
by key over ssh from the host (`PermitRootLogin = "prohibit-password"`), so
administration happens from outside the jail and the agent has no escalation
path. The trade: if sshd or the tap breaks, there is no root at all — fix it
declaratively and reboot the VM.

(`initialHashedPassword = ""` was tried first and doesn't work: it only applies
at account creation, and PAM rejects empty passwords for `su` without `nullok`.)

This is **not** the perimeter. Egress filtering is enforced on the host, where
the guest — root or not — cannot reach it, and the git tier is not a restriction
at all any more but the absence of a channel ([notes](./notes.md) item 18).
Guest uid separation buys protection from a clumsy agent, realistic file
ownership, and parity with the bwrap jails' model.

`$HOME` is `/work/home`, i.e. on the volume: `~/.claude`, credentials and shell
history survive reboots. That is most of the answer to agent auth — the rest is
[capsule-only setup](#capsule-only-setup--three-problems-one-name), which is
where the credentials come from in the first place.

**Do not loop-mount `capsule-work.img` on the host.** It is a filesystem the
guest has had write access to, and `mount` hands its metadata to the host
kernel's ext4 implementation — historically one of the softest targets
reachable from untrusted data, and it would undo the containment in one
command. If you need to read the volume from outside, use a userspace reader
(`fuse2fs`, `debugfs`), or ask the guest for it over ssh.

## Tools: one list, two consumers

doctrine's flake now splits its package list in two:

- `devToolPkgs` — the tools, agent-free.
- `projectPkgs = devToolPkgs ++ [codex claude]` — what its devshell uses.

and exports `packages.dev-tools` (a `buildEnv` over `devToolPkgs`), which this
flake drops straight into the guest's `systemPackages`. The capsule and that
devshell therefore cannot drift, and the rust toolchain comes from doctrine's
own pin — `rust-overlay` is no longer an input here.

The jailed `claude` / `codex` wrappers are deliberately excluded: they are bwrap
wrappers binding *host* paths, which mean nothing inside the VM. The capsule
gets `pkgs.claude-code` instead, and its confinement is the VM.

**`git+file:` reads committed HEAD.** Changes to doctrine's flake need a commit
there before `nix flake update doctrine` will see them.

## Capsule-only setup — three problems, one name

A provisioned capsule is not yet a capsule you can work in. There is no
filesystem path into the guest (firecracker: no shares), so anything that has to
get there arrives over the link or is baked into the closure — and which of those
it is depends on what it is. The decomposition is the part worth having written
down, because the three parts have different mechanisms and different trust
properties. All three are built now, and they stayed three programs rather than
becoming one: they differ in what they carry, in what may see it, and in how
long they take.

| | what | mechanism | in the closure? | program |
| --- | --- | --- | --- | --- |
| static config | build config, git config, shell rc, agent instructions | derived from `target.sizes`, guest-side | **yes** — config, not secret | the guest's seed |
| credentials | OAuth tokens, API key | host-initiated push over the ssh channel | **never** — `/nix/store` is world-readable | `capsule-inject` |
| baseline | the target's own build-and-test to green, caches seeded | a host-initiated *command* | n/a | `capsule-baseline` |

**Static config is a function of `target.sizes`, not a copy of a human's
dotfiles.** The tempting version — carry in `~/.cargo/config.toml` — imports a
config tuned for the host's thread count and page cache into a guest that has
neither, and a `jobs` count from a 32-thread machine inside a 4-vCPU guest is a
worse default than none. So derive the sizing-shaped settings from the same
`target.sizes` the VM is built from and keep them in the guest's config, where
they cannot disagree with the machine they run on. This is the same asymmetry as
[notes](./notes.md) item 16's: the *tool set* comes from the target because it is
a build input, and policy does not.

It is also the worked example for CLAUDE.md's "doctrine is the guinea pig, not
the design": the capability is *render static guest config from the instance's
declared reservation*, and cargo's `jobs` is one target's instance of it. A
target that does not build with cargo needs a different value here, not
different code.

**Built, as `target.nix`'s `guestConfig`**: guest paths relative to the volume
mount, file contents, rendered into the closure by `vm/capsule.nix` and linked
onto the volume by the seed. Links rather than copies, for the same reason the
values are derived rather than copied — a copy on the volume outlives the sizes
it was rendered from and nothing would say so. The generic side knows only
"path, content"; the string `cargo` appears once in this repo, in `target.nix`,
and `{}` is a working absent value for a target that wants none of it.

What it changed for doctrine is not subtle: until it existed, the capsule built
with full debuginfo and an incremental cache — cargo's defaults, since neither
the human's config nor doctrine's own `Cargo.toml` reaches a capsule. Every
volume figure in [probes.md](./probes.md) was taken against that untuned build.

**Credentials are a push, not a fetch, and item 18 is why.** The earlier plan
here had `capsule-host` *serve* a bootstrap tarball, with an open question about
whether it went over the git daemon or a second port. Both halves of that
question died with the inversion: the host initiates over ssh now, so a
credential injection is one host-side program pushing an explicit list of paths
into `/work/home`, with no service, no port and nothing for the guest to reach.

**Built, as `capsule-inject`.** `setup.nix` declares the payloads and
`host/inject.nix` is the mechanism — and the mechanism never learns what a
credential is, because each entry carries its own host-side `produce` fragment.
No filename, format or key name appears in the program. Same rule as
`guestConfig`, same seam as `capsule-provision`.

Selection is the whole point, and the shape of these two payloads is the
argument for it:

- `~/.claude/.credentials.json` is **nothing but the token**, so it travels
  whole — there is no subsection to take.
- `~/.claude.json` holds **no token at all**: 94 KB of identity plus ninety keys
  of local state, including `projects` — 16 repo paths and their per-project
  history. Four keys travel (`oauthAccount`, `userID`, and the two onboarding
  flags); the rest, and `history.jsonl`'s 3 MB of prompts beside it, stay on the
  host. A whole-`~/.claude` copy would have taken all of it into a jail that
  exists to not have it.

One open question is answered and one is not. **Concurrency**: several agents do
run off one credential — the bwrap jails already do — so a capsule does not need
its own. **Divergence**: those jails share one *file*, whereas a capsule holds a
*copy* on its volume, and the token rotates on refresh, so the two drift and
neither is authoritative. Hence write-if-absent with an explicit `--force`
rather than a merge or a clobber: replacing a capsule's credential discards
whatever it has written since, and that should be a decision. The `/work/.env`
API-key path in item 2 still works and needs none of this.

**`$HOME` is on the volume, so setup is paid per fresh capsule.** Freshness is
implemented by deleting volumes, and `/work/home` is on one — so setup and
baseline are not one-time costs, they are part of what a fresh capsule costs.
That also means the cold baseline build is the largest term in
time-to-interactive, and it is the one figure the freshness probe cannot take:
its namespace has no upstream. A host-initiated baseline command is where that
number comes from.

**Built, as `capsule-baseline`.** `target.nix`'s `baseline` is the command —
this target's is `just web-build test`, and nothing outside that file knows what
`just` is. The program is `host/baseline.nix` and knows an ssh destination, a
command line and four guest paths.

The measurement lesson is structural in it rather than remembered. Two sizing
runs were lost to a figure whose only copy was terminal scrollback, so the run
writes its log and one line of `/work/baseline/history.tsv` **onto the volume as
it goes**, and it detaches into its own session — the host attaches to watch and
may leave without stopping it. Re-running while one is in flight attaches to
that one instead of starting a second, because two runs interleaved into one
record are two figures lost rather than one gained. It also sizes the checkout
and every `target.caches` directory before and after, so a recorded run says for
itself whether it was cold; the totals are in the record and the breakdown is in
the log. The volume is where a figure survives the session — freshness deletes
the volume, so [probes.md](./probes.md) is where it survives the capsule.

Two things it refuses. A capsule with no commit at `guestPath` is a mistake, not
a red — it does not run, and says to provision first. And the record lives
*beside* the checkout, never in it: a record written into the worktree is a
dirty worktree, which is exactly what `receive.denyCurrentBranch = updateInstead`
refuses the next provision on.

**Run 1: 109 s to green, and it reorders the design's priorities.**
Time-to-interactive is ~2 minutes and this build is ~93% of it, so the boot
figures everything else in [probes.md](./probes.md) chases are noise beside the
first `cargo build`. What that argues for is not a faster capsule but a warmer
one — carrying a crate cache in, or not discarding it — and that runs straight
into freshness, which is implemented by discarding exactly that. The tension is
real and unresolved; it is at least now a tension between two measured things.

## nix inside the guest — considered, not done

Running `nix develop` on doctrine's flake in the capsule needs three things:

1. `microvm.writableStoreOverlay = "/nix/.rw-store"` plus its own volume — the
   guest store is a read-only erofs image. microvm.nix's docs warn the Nix DB
   forgets everything in the overlay across reboot, so it wants recreating
   rather than trusting.
2. `systemd.services.nix-daemon.environment` proxy vars. The daemon does the
   fetching and does not inherit login-shell env (see [notes](./notes.md) item 6).
3. Allowlist: `cache.nixos.org`, `channels.nixos.org`, `api.github.com`.

Then every overlay reset rebuilds `doctrine` via crane, plus `pub` /
`llm-agents`, inside the VM.

Preferred alternative: have doctrine's flake expose its tool list as a package
(`packages.dev-tools = pkgs.buildEnv { paths = projectPkgs; }`, a few lines
there), and have the capsule put
`inputs.doctrine.packages.x86_64-linux.dev-tools` straight into
`systemPackages`. One list, two consumers, no writable store, no drift. Cost is
re-adding doctrine as an input, pulling its `pub` / `llm-agents` transitives
into this lock.

Worth doing the nix route only if the agent needs to *change* its own toolchain
or run `nix build` checks.

