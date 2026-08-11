# microvm.nix spike — notes

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
| `justfile`                   | the gate (`just check`) + the multi-command questions |
| `perimeter/default.nix`      | `sync`/`proxy`/`gitd` + `capsule-host`. Jail-agnostic |
| `perimeter/egress-allow.txt` | proxy hostname allowlist — plain file, no rebuild. Per target |
| `host/perimeter-check.nix`   | is the host's nftables drop loaded? Linux-shaped, injected |
| `host/services.nix`          | the same services as units under dedicated uids. Opt-in |
| `vm/common.nix`              | shared guest config (firecracker, serial console)   |
| `vm/hello.nix`               | smoke test VM, no network                           |
| `vm/capsule.nix`             | the agent jail                                      |
| `.vm/<name>/`                | per-VM state: volume images, API socket (gitignored)|
| `.vm/host/`                  | the bare mirror, proxy config + logs (gitignored)   |
| `probe/netns.sh`             | is a netns per capsule sound? kept as evidence — `sudo probe-netns` |
| `PLAN_B.md`                  | the same perimeter, a different jail (macOS, non-NixOS) |
| `PLAN_C.md`                  | what N capsules on one host would cost (item 17)    |

The split is load-bearing, not tidiness: the perimeter is where nearly all the
policy lives and it is the only part that ports to a non-firecracker jail
(PLAN_B.md). It takes addresses and ports as arguments and one injected
`preflight` fragment — on firecracker, the tap-address check — so nothing
hypervisor- or platform-shaped leaks into it. Runtime paths are environment
(`CAPSULE_ROOT`, `CAPSULE_STATE`, `CAPSULE_ALLOWLIST`, `CAPSULE_REPO`), which
is what keeps the allowlist an editable file rather than a store path. Which
repo is confined reaches it the same way as the addresses do — as a value from
the call site, from `target.nix` (item 16).

## Running

```
direnv allow
capsule-net up      # one sudo: creates the tap, owned by you
capsule-host        # foreground: git daemon + egress proxy
vm capsule          # another terminal
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

**Git.** `git clone --mirror ~/dev/doctrine` into `.vm/host/`, served by
`git daemon` on the p2p address with `receive-pack` enabled. The guest clones
real history with real ancestry and pushes back.

- Bare is a hard requirement: a non-bare clone refuses pushes to its checked-out
  branch (`receive.denyCurrentBranch`).
- `--mirror` over plain `--bare` buys `fetch = +refs/*:refs/*`, so the mirror
  tracks every ref namespace rather than just `refs/heads/*` + tags. Your
  `phase/`, `dispatch/`, `review/`, `candidate/`, `w/` namespaces all live
  under `refs/heads/` (274 refs), so plain `--bare` would have carried them
  too — the mirror's edge is fidelity on anything future that doesn't.
- **Never `git remote update` the mirror.** A mirror's fetch is force+prune and
  would delete what the guest pushed. `capsule-host` refreshes with an explicit
  `+refs/heads/*:refs/heads/*` instead.
- An `update` hook restricts guest pushes to `refs/heads/capsule/*`. The agent
  cannot rewrite your history through the mirror — it gets a namespace, and you
  fetch from it:
  ```
  git fetch .vm/host/doctrine.git 'refs/heads/capsule/*:refs/heads/capsule/*'
  ```
  Which lines up with SPEC-012's merge-safety-by-absence: the agent has no path
  to the coordination tier, physically.

Guest helpers: `capsule-clone` (re-fetch, for when the host side came up late)
and `capsule-push <name>`.

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
  Second consequence: no `MemoryMax`/`CPUQuota`/`TasksMax`, so 16 GiB and 8
  vCPU are the guest's to abuse. See open items 11–12.

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

This is **not** the perimeter. Egress filtering and the `refs/heads/capsule/*`
restriction are both enforced on the host, where the guest — root or not —
cannot reach them. Guest uid separation buys protection from a clumsy agent,
realistic file ownership, and parity with the bwrap jails' model.

`$HOME` is `/work/home`, i.e. on the volume: `~/.claude`, credentials and shell
history survive reboots. That is most of the answer to agent auth.

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

## Getting secrets in — the bootstrap tarball

Not built yet. There is no filesystem path into the guest (firecracker: no
shares), so the options are the console or the p2p link.

Plan: have `capsule-host` serve a bootstrap tarball over the existing link —
an explicit, listed selection of `~/.claude` (OAuth credentials, settings,
possibly `CLAUDE.md`), assembled on the host and fetched once by the guest into
`/work/home`, where it persists. Explicit selection is the point: a whole-`~/.claude`
mount would hand the agent every project's history and every credential in it.

Open questions for when we build it: whether the tarball goes over the git
daemon (a `bootstrap` repo) or a second port; how to avoid re-fetching a stale
copy over a newer in-guest login; and whether OAuth tokens tolerate being used
from two places at once, or whether the capsule needs its own credential.

## nix inside the guest — considered, not done

Running `nix develop` on doctrine's flake in the capsule needs three things:

1. `microvm.writableStoreOverlay = "/nix/.rw-store"` plus its own volume — the
   guest store is a read-only erofs image. microvm.nix's docs warn the Nix DB
   forgets everything in the overlay across reboot, so it wants recreating
   rather than trusting.
2. `systemd.services.nix-daemon.environment` proxy vars. The daemon does the
   fetching and does not inherit login-shell env (see open item 6).
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

## Security posture — what the boundary actually is

Guest ring-0 to host, largest surface first:

1. **KVM.** MSR/CPUID/paging/instruction-emulation surface in the host kernel,
   reachable from guest ring 0. Irreducible in any VM, and still the reason the
   VM is worth having: the bwrap jails' equivalent boundary is the whole host
   syscall table.
2. **Firecracker's device model.** virtio-net, two virtio-block, serial, an
   i8042 stub, PCIe config space. No vsock, no balloon, no MMDS, no vhost-user,
   no virtiofsd — the generated config has `"vsock": null` and nothing else
   attached. Rust, small, seccomp-filtered (above).
3. **The host IP stack, via the tap.** The guest emits arbitrary L2 frames and
   the host kernel parses them. This is surface the bwrap jails do *not* have —
   a bwrap process holds no effective `CAP_NET_RAW`, because the host netns is
   owned by the initial user namespace. Which is why none of the host config in
   README "Host requirements" is optional (open item 7).
4. **The two host services on the /30.** tinyproxy (C, parsing guest-authored
   HTTP) and git-daemon, which runs `receive-pack` as the host user on a repo
   whose objects then flow into the real tree.

**Raising the price of (1).** Guest ring-0 is the *input* to the KVM surface,
and loading a kernel module is the cheap way to get there once something has
root in the guest. `security.lockKernelModules` + `security.protectKernelImage`
turn that into a guest kernel LPE instead. This is not the perimeter moving
inward — the perimeter stays host-side, and a guest that is already ring-0 can
undo anything in the guest. It buys the interval between "agent escalates to
guest root" and "agent is in a position to attack the hypervisor", which is
where the expensive surface begins. The device set is fixed and fully loaded by
the time the lock lands; anything wanting a module on demand (fuse, loop,
`nf_tables`) will fail, and the switch is two lines in `vm/capsule.nix`.

And the channel no hypervisor closes: **the commits**. `capsule/*` gets fetched
and built on the host, so agent-authored code executes outside the jail by
design. That is the largest practical risk here and everything above is
second-order to it. The confinement's job is to bound what the agent can reach
*while* working, not to make its output safe to run unread.

## Open items

1. **What has actually been run.** The guest boots and the agent works over ssh;
   the perimeter has been exercised in both shapes — `capsule-host` in the
   devshell, and the units under dedicated uids on Sleipnir (item 11), including
   the guard's teardown against a live guest. Not exercised: a second host, a
   second target repo (item 16), and the VMM half of item 11. Assume anything
   documented here but not named in this paragraph is reviewed rather than run.
2. **Agent credentials.** No shares, so nothing can be injected from the host
   filesystem. First boot: put `export ANTHROPIC_API_KEY=...` in `/work/.env`
   (sourced at login, persists on the volume). OAuth login would need
   `claude.ai` + `console.anthropic.com`, both allowlisted, but the device flow
   wants a browser.
3. **`pkgs.claude-code`** exists on this channel (confirmed by it failing the
   unfree check, not the existence guard). It is unfree, so the guest carries
   an `allowUnfreePredicate` naming just that package. Still guarded by
   `lib.optional (pkgs ? claude-code)` for channel drift.
4. **`just test` may want a live Postgres.** doctrine's flake sets
   `doCheck = false; # tests need a live Postgres`, though no `DATABASE_URL`
   appears anywhere in the tree. Not provisioned; `services.postgresql.enable`
   in `vm/capsule.nix` if it bites.
5. ~~No `doctrine` binary in the guest~~ — resolved: `dev-tools` carries it,
   along with jujutsu, sccache, graphviz/d2/mermaid and the rest of the
   devshell's list. Watch the store disk size.
6. **Proxy env is login-shell scope** (`environment.variables` → `/etc/set-environment`).
   Anything run from a systemd unit in the guest won't inherit it.
7. ~~**Host config.**~~ Done; the stanzas are in README "Host requirements",
   and the first attempt was wrong in a way worth
   recording. `networking.firewall.trustedInterfaces = [ "vm-capsule" ]` opens
   the *interface*, not the two ports — `firewall-nftables.nix` renders it as
   `iifname { … } accept`, so every service bound to `0.0.0.0`/`*` on the host
   became reachable from inside the jail (here: sshd, caddy on 80 and 8080,
   dictd, steam's 27036, LLMNR). Loopback-bound services were never exposed:
   guest packets are addressed to the tap, not to `127.0.0.1`. The scoped form
   is what belongs in the host config —
   `networking.firewall.interfaces."vm-capsule".allowedTCPPorts = [ 3128 9418 ];`
   — and *not* plain `allowedTCPPorts`, which would also open the proxy and the
   git daemon on the LAN and the tailnet.

   The input chain was only half of it. **The tap must also not be a transit
   path**: the guest has no default route, but a guest with root can add one,
   after which the sole remaining question is whether the host forwards.
   `net.ipv4.ip_forward` is global and not ours — docker and tailscale both set
   it — so the guarantee cannot rest on it being 0. A standalone nftables table
   dropping `iifname`/`oifname "vm-capsule"` in the forward hook is the control.
   Deliberately *not*
   `networking.firewall.filterForward`, which flips the whole host's forward
   policy to drop (`firewall-nftables.nix` renders `policy drop` on the forward
   chain) and whose `extraForwardRules` land in an allow-list chain that cannot
   express a drop anyway. A separate table needs no cooperation from the
   firewall's: a `drop` verdict in any chain is terminal for the packet.

   IPv6 on the tap is host stack the guest can reach for no benefit, and is
   turned off by `capsule-net` before the link comes up rather than by a
   boot-time sysctl, which would fire before the interface exists.

   **And it is now checked rather than documented.** A control that lives in
   someone else's file and is never read is a control you find out about
   afterwards — it was in fact missing from this host's config until the check
   was written, with `ip_forward` at 0 the whole time, which is exactly the
   failure the check exists to surface.

   The two halves fail differently and that is what decides how much machinery
   each deserves. Omit the *allow* (interface-scoped ports) and the guest
   reaches nothing: loud, self-announcing, no verification needed. Omit the
   *drop* and everything works normally until a guest gains root and adds a
   route: silent, and worth spending on. So only the drop is verified, and this
   repo cannot install it — a `drop` in any chain is terminal, so a table here
   could add denials, but nothing here can grant the accept that the host
   firewall would still be dropping. Deny-side controls can be self-installed;
   allow-side controls can't. Hence: check, don't install.

   Verification reads live kernel state (`nft list table inet capsule-forward`),
   not a stamp file or the config text, because the failure mode being guarded
   is "the config no longer matches the kernel". That read needs CAP_NET_ADMIN,
   so it depends on a NOPASSWD sudoers rule for exactly that one command,
   naming `/run/current-system/sw/bin/nft` — a store path can't work, since the
   two flakes have separate nixpkgs pins and sudo matches the command string
   literally. No rule means no verdict, which resolves to `latent`: safe only
   while nothing forwards, and reported as such rather than passed.

   Three states, one definition shared by `capsule-net` and `capsule-host`
   (`perimeterChecks` in `flake.nix` — Linux-shaped, hence at the call site and
   not in `perimeter/`): `dropped` verified, `latent` unverifiable but nothing
   forwards, `open` forwarding live and unverifiable → refuse. Preflight alone
   would only prove the perimeter held at start, so `capsule-host` also
   supervises a `watch` child that re-checks, and exits — tearing the proxy and
   the git daemon down with it — if forwarding comes up mid-session or the tap's
   address vanishes. Losing egress is the correct outcome; continuing to serve
   it past a missing control is not. `watch` is an injected fragment for the
   same reason `preflight` is: `perimeter/` must not learn what nftables is.
8. **git-daemon is unauthenticated**, and `--enable=receive-pack` is what makes
   the update hook load-bearing. Now narrowed by two independent guards:
   `--strict-paths` plus the mirror as the sole whitelisted path (so no sibling
   under `.vm/host/` that happens to look like a repo can be served), and a
   per-repo `git-daemon-export-ok` marker in place of `--export-all`. Still
   reachable from the host itself on the foreground path, which is accepted; the
   unit path closes it with `IPAddressDeny` (item 11).
9. **Egress allowlist is unproven** against a real Claude Code session —
   expect to add hosts on first run. `perimeter/egress-allow.txt`, restart
   `capsule-host`, no rebuild.
10. **Dropped since the first cut:** vendored crates
    (`rustPlatform.importCargoLock`) and the pre-seeded `node_modules` from
    doctrine's `web-modules` FOD. Both existed to make an offline capsule
    build; the proxy supersedes them, and dropping them removed this flake's
    dependency on doctrine's flake (and its `pub` / `llm-agents` transitives).
    Worth restoring if you want cold-start builds without network.
11. **Everything host-side runs as you** — two problems sharing one fix, and the
    first half is now done.

    - The **VMM**: a firecracker escape lands on uid 1000, with ambient access
      to `~/.ssh`, `~/.claude`, every repo and every shell rc — precisely the
      assets the capsule exists to keep away from the agent. Still open.
    - **`capsule-host`**: tinyproxy is C parsing guest-authored HTTP, and
      git-daemon runs `receive-pack`, both as you. Independent of the
      hypervisor, so it was worth doing first and on its own.

    **The services half — deployed and exercised** on Sleipnir
    (`nixosModules.capsule-perimeter`, `host/services.nix`, wired from
    `~/flakes/modules/nixos/capsule.nix`; README has the switch and the path
    changes). Still opt-in as a module — the foreground path is untouched — but
    no longer merely available. What running it proved and cost:

    - The units bind as uid 971/972, the guest's allowlisted egress works and a
      host off the allowlist gets a 403 from tinyproxy, pushes to `capsule/*`
      land in `/var/lib/capsule/doctrine.git` and `owner` fetches them out by
      group. The guard's teardown was tested by deleting the table and setting
      `ip_forward=1` under a running guest: both services stopped inside the
      10s poll and egress died with them. That is the whole claim of this half,
      so it is worth re-running after any change to the guard.
    - **First-eval and first-run cost, all of it environmental rather than in
      the module.** `~/flakes` sits in a sparse `~/.git`, so an untracked
      `capsule.nix` is simply absent from the flake's store copy — `git add`
      before the build, not after the confusing error. `owner`'s new
      `capsule-git` membership does not reach an already-open session, and the
      resulting `Permission denied` on a `2775` directory reads as a mode bug.
      And `capsule-host` must be *stopped*, not merely Ctrl-C'd — see the
      shutdown gotcha in CLAUDE.md; while it holds the ports the units flap on
      `Restart=on-failure` with `tinyproxy: Could not create listening
      sockets`.
    - `perimeter.sync` had to be installed **wrapped**. Its defaults are
      relative to `CAPSULE_ROOT`, which is right for the foreground path and
      wrong for a program on `$PATH`: run from anywhere it would mirror into
      `$PWD/.vm/host` and the units would keep waiting for a mirror that exists
      somewhere else. The wrapper is in the module because that is the only
      place that knows `stateDir`. Deliberately still named `capsule-sync`, so
      the devshell's copy shadows it inside this repo and each path gets its
      own mirror.

    What is worth recording about the shape:

    - `perimeter/` now builds four programs instead of one: `sync`, `proxy`,
      `gitd`, and `host` as their foreground composition. That split is what
      lets the same code be either three children of one unprivileged process
      or three units under separate uids, with no second implementation. The
      foreground path is kept deliberately — it needs no root and no rebuild,
      which is what makes it usable for development, and it is the only path
      that survives on a host without systemd (PLAN_B).
    - **The best part is not the uid split, it is what `sync` being separate
      buys.** The mirror's refresh is the only operation that reads
      `~/dev/doctrine`, and it runs as you. So the uid *serving* the mirror —
      the one exposed to an unauthenticated `receive-pack` — has no route to
      the tree the mirror came from. Before, a git-daemon bug read the whole
      home directory; now `ProtectHome` costs it nothing, because it never
      needed home in the first place.
    - `git-daemon` gets `IPAddressDeny=any` with only the guest allowed, so a
      compromise cannot dial out at all. That also closes the "still reachable
      from the host itself" gap in item 8 as a side effect, at the price of
      `git://` no longer working from the host — the mirror is a path, so fetch
      it as one.
    - The proxy cannot be locked down that way, since being the egress point is
      its job. It instead loses loopback, link-local and RFC1918, with the
      guest and the resolver allowed back by longest-prefix match, so it can
      reach the internet and not the LAN. It also sees exactly one file from
      `$HOME` — `ProtectHome=tmpfs` plus a read-only bind of the allowlist —
      which keeps the allowlist an ordinary editable file without handing a C
      HTTP parser the rest of the directory.
    - The mirror is setgid and `core.sharedRepository=group`, which is what lets
      one uid serve pushes while another syncs and fetches them out. Ownership,
      not ACLs, and `owner` is a member of the daemon's group rather than the
      reverse.
    - The guard unit is this path's `preflight` + `watch`: root, so it reads the
      nftables ruleset directly and needs no sudo rule. `BindsTo` on both
      services, and no `Restart`, so a refusal stays a refusal.
    - `host/perimeter-check.nix` is the one definition of the check, taking
      `nft` as a whole command so the sudo path and the root path share it.

    The VMM half is next, and is the option below rather than a decision. Note
    the coupling the wiring introduced: `~/flakes` takes this repo as an input
    with `inputs.doctrine.follows = "nixpkgs"`, purely so the input graph is
    fetchable on a machine without `/home/david/dev/doctrine`. It costs nothing
    while the host config only reads `nixosModules.capsule-perimeter`, and must
    be undone if the VMM moves to the host module below — that path evaluates
    the guest, and the guest's tool set is doctrine.

    **The VMM half — microvm.nix's host module. An option, not yet taken.**
    Verified against the pinned source (`nixos-modules/host/`), because the
    details decide whether it is worth it:

    - `microvm@%i.service` runs `User=microvm`, `Group=kvm`, `WorkingDirectory=
      ${stateDir}/%i` with `stateDir = /var/lib/microvms`. So the uid drop is
      free, and `~/.ssh` / `~/.claude` / every repo leave the VMM's reach.
    - The tap becomes a **root-side** `microvm-tap-interfaces@%i.service`
      (`ExecStart=…/bin/tap-up`, `ExecStop=…/bin/tap-down`, `partOf` the VM),
      which retires `capsule-net` and its sudo for this path.
    - Declared as `microvm.vms.capsule.flake = <this flake>` from `~/flakes`,
      which means adding this repo as an input there — and `git+file:` reads
      committed HEAD, so a host rebuild would start depending on this repo
      being committed. `microvm.vms.<name>.autostart` and `microvm.autostart`
      exist if it should come up at boot; it should not, at least at first.
    - `Group = "kvm"` is **not** a private group — it is shared with everything
      else on the host that touches `/dev/kvm`. Anything mode-`0660` group-kvm
      is inside the VMM's reach. Worth a look before adopting.

    **It does not fix the shutdown jank, and the earlier note here claiming it
    would was wrong.** `ExecStop` is `microvm-shutdown`, i.e. the same
    `SendCtrlAltDel` this guest ignores (CLAUDE.md). So `systemctl stop` waits
    out `TimeoutSec` and then SIGTERMs the VMM — a power cut with extra steps,
    and the volume replays its journal. Also `Restart = "always"`, so killing
    the VMM by hand brings it straight back. Adopting this path therefore wants
    a drop-in overriding `ExecStop` with the ssh poweroff `vm-stop` already
    does, and a decision about `Restart`.

    **It also takes a network namespace, which PLAN_C needs and this was
    checked for at the same time.** `microvm@` and `microvm-tap-interfaces@` are
    ordinary `systemd.services` attributes, and the module already emits a
    per-name drop-in for each (`overrideStrategy = "asDropin"`), so
    `serviceConfig.NetworkNamespacePath` goes in per instance through a
    mechanism it uses in-tree — no patch, and no `%i` specifier to gamble on.
    `tap-up` is namespace-agnostic (`ip tuntap add … user`, `ip link set up`,
    and `tap-down` deletes), so putting the namespace on that unit too means the
    tap is created and destroyed *inside* it and never moves. `User = microvm`
    is no obstacle: systemd sets namespaces up as PID 1, before dropping
    privilege. Watch one detail — `ExecStartPost`/`ExecStopPost` carry the `+`
    prefix, which bypasses sandboxing, so those run in the *host* namespace;
    harmless today (they do nothing without `registerWithMachined`) and a silent
    hole for anything added there later.

    Remaining costs: the VM is declared in `~/flakes`, iterating means a host
    rebuild, and the console moves to the journal — which matters little, since
    TUIs never worked on the serial console anyway and ssh is already the
    documented way in. Keep the standalone `nix run` path for development; the
    host-module path would be the real posture.

    A systemd unit is also what makes the rest of this list cheap, which is why
    it is worth preferring over the LSM routes:

    - `ProtectHome`, `ReadWritePaths`, `NoNewPrivileges`,
      `RestrictAddressFamilies`, `DeviceAllow=/dev/kvm` give the filesystem
      scoping **Landlock** would, through a mechanism already in use. Landlock
      is the better shape only if the `nix run` path stays the real posture —
      it is unprivileged and needs no root policy, but it needs a launcher that
      installs the ruleset before exec, so check what nixpkgs actually carries
      before counting on it. **AppArmor** is the wrong tool here regardless:
      profiles attach by path, and the exec path is a `/nix/store` path that
      changes on every rebuild.
    - Seccomp needs nothing: firecracker installs its own filter in-process and
      only `--no-seccomp` loses it. Do not add a second layer — the realistic
      outcome is a weaker one.
    - The cgroup knobs in item 12 are unit options.
12. **No resource ceiling on the VM** — though less is unbounded than that
    suggests, and the distinction matters for what is worth fixing. (The two
    host services now have ceilings; see item 11. This is about the VMM.)

    | resource | bound today | actually open |
    | -------- | ----------- | ------------- |
    | memory   | 16 GiB, hard. No balloon in the firecracker runner, so the high-water mark is never returned to the host either | nothing, but the VM costs 16 GiB for its whole life |
    | vCPU     | 8 threads of 32 | the *share*: 8 threads at 100% compete with everything else you are doing |
    | disk     | 32 GiB, hard — a sparse file cannot exceed its declared size | see item 15 |
    | disk I/O | none | a `cargo build` in the guest hammers the host disk unthrottled |

    So the real asks are `CPUQuota`/`CPUWeight` and `IOWeight`, plus
    `MemoryMax` as a backstop against a VMM leak rather than against the guest.
    Interim, without moving to the host module: `systemd-run --user --scope -p
    CPUQuota=600% -p IOWeight=50 -p MemoryMax=18G -- vm capsule`. Caps only, no
    uid separation, and the user slice needs the `cpu` controller delegated for
    the quota to take.
13. **Accepted, not fixed:** host SMT is on and `machine-config` carries
    `smt: true`, against firecracker's own host-setup guidance for untrusted
    guests. Zen 5 reports vmscape mitigated (IBPB on VMEXIT) and is unaffected
    by MDS/L1TF, and a side channel is a preposterous amount of work to steal
    what the agent's own commits can carry out in the open. Revisit only if the
    capsule ever hosts something genuinely adversarial.
14. **Hypervisor choice.** firecracker's feature floor — no shares — is what
    shapes the bootstrap-tarball problem, the credential problem and the
    read-only store, i.e. about half of this list. `hypervisor =
    "cloud-hypervisor"` is a one-word switch: also a Rust VMM, runner passes
    `--seccomp true`, gains virtiofs shares (secrets by ro-bind, no tarball)
    and balloon. Cost is virtiofsd — one more host-side daemon speaking a
    guest-controlled protocol — and a slightly larger device model. The policy
    (no default route, proxy-only egress, host-side ref guard) is unchanged
    either way. Worth a branch. `crosvm` is the other candidate: shares plus
    `--pivot-root` and per-device minijail sandboxing built in, but its nixpkgs
    maintenance needs checking first. `qemu` is the only runner honouring
    `microvm.user`, but it is the largest surface and its user-mode networking
    would void the egress control. Direct firecracker + jailer is not worth it:
    the jailer wants everything inside a chroot while the generated config is
    absolute `/nix/store` paths, so it means pre-populating a chroot with the
    closure — reimplementing microvm.nix, badly, for less than item 11 buys.
15. **Two things that only grow.** Neither can exhaust the host — worth saying,
    since "unbounded" is the wrong word for both — but neither ever gives space
    back.
    - `capsule-work.img` is sparse and capped at its declared 32 GiB, and
      **firecracker's virtio-block has no discard**, so there is no `fstrim`
      and no `discard` mount option that would return freed blocks. Deleting
      `target/` in the guest frees guest space and nothing host-side. The image
      is a high-water mark; the only reclaim is deleting it, which is also the
      documented way to reset the workspace.
    - `.vm/host/tinyproxy.log` has no rotation on the foreground path. Small,
      but it is the record of every egress attempt, so truncating it on start
      would be the wrong fix. Rotated (weekly, `copytruncate`) on the unit path
      only — see item 11.
16. **Target-agnostic — done for one target at a time.** Nothing structural tied
    the confinement to doctrine. The perimeter was already target-blind: the
    mirror's name is `basename "$CAPSULE_REPO"`, the ref restriction is
    `refs/heads/capsule/*` whatever the repo is, and `host/services.nix` took
    `repo` as an option. What was actually hardcoded was smaller than it looked —
    the string `doctrine` in `vm/capsule.nix` (checkout dir, clone URL, motd),
    the input's name in `flake.nix`, doctrine-shaped defaults in
    `perimeter/default.nix` and `justfile`, and a handful of guest settings that
    are really *toolchain* settings: `CARGO_HOME`, `BUN_INSTALL_CACHE_DIR`,
    `init.defaultBranch = "edge"`, `pkg-config`/`openssl`, the vcpu/mem/volume
    sizes, and half the allowlist.

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
    - **Per-target policy must not live in the target repo.** The tempting
      version — `.capsule/egress-allow.txt` in the repo being worked on — hands
      the allowlist to the thing being confined. Not directly (the host reads
      the human's working tree, not the mirror) but one careless `capsule-sync`
      after a `capsule/*` merge and the agent has widened its own egress. The
      allowlist, the sizes and the ref policy are host-side config keyed by
      target name; only the *tool set* comes from the target, because that is a
      build input rather than a control. Keep that asymmetry explicit or the
      whole perimeter argument leaks.
    - **One target chosen ≠ several at once.** The parameterised single-target
      version is what got built, and it is an afternoon. What the other one costs
      is now written down — [PLAN_C.md](./PLAN_C.md), which starts from the
      observation that the guest's address lives in its *closure*, so N capsules
      naively means N store images. *Concurrent* capsules is
      a different job: `net.nix` becomes per-instance (tap name, /30, MAC, two
      ports each), the units become templates (`capsule-proxy@<target>`) with a
      uid pair each, and the host's own config grows a per-tap nftables drop and
      per-interface ports — i.e. it reaches into `~/flakes`, which is the part
      this repo cannot install for itself (item 7). Don't buy the second while
      pricing the first.

    The contract, written down: *be a git repo on this host, and expose one flake
    package for this system that is your devshell's tool set* (doctrine:
    `packages.dev-tools`). Everything else about the target is optional and
    host-side. `toolsPackage = null` still works — the guest then gets
    `extraTools` from this repo's nixpkgs and loses the no-drift property that
    made threading the target's own list worth it.

    Untested: a second target. The parameterisation is only *claimed* until one
    exists, and the likely friction is in the guest — `extraTools`, the cache
    set, and the sizes are all this target's toolchain wearing a general name.

17. **More than one capsule at a time — scoped, not started.**
    [PLAN_C.md](./PLAN_C.md) is the list of what a plan has to settle, with the
    costs attached. The three things worth knowing without reading it:

    - **The deciding cost is the guest image, not the plumbing.** Tap, MAC and
      /30 reach the guest through its config today, and its store image is
      generated per config, so the obvious design pays N image blobs — N × disk,
      and N × *pack* time on every `dev-tools` bump. Not N × build: the closure
      is almost entirely shared. Getting the per-instance values out of the
      closure buys one image and N small runners, and there are two of them, not
      one: the guest's address, and the **base commit**, which a capsule is
      usually pinned to and which `capsule-clone` would bake in the same way the
      remote already is. A kernel param does *not* work for either — it lands in
      `toplevel` and so in the closure. Measure `nix path-info -Sh .#capsule`
      before choosing, and see the netns option below, which makes the guest
      bit-identical without any of it.
    - **No daemon, and the premise that suggests one is wrong.** Nix runs nothing
      at run time here: `vm` is build-then-exec. Everything a dispatcher would do
      is systemd's, and microvm.nix's host module already models it — which is
      why the VMM half of item 11 should be done *with* this work rather than
      before or after it. Per-instance ceilings stop being optional at N anyway
      (item 12).
    - **A capsule can reach another capsule's tap, and the forward drop is not
      what stops it.** B's tap address is a *host* address, so a packet from A
      to it is INPUT, not forward, and Linux accepts an address on any interface
      from any interface. The drop never sees it. Precondition is guest root —
      the same precondition the drop itself exists for — and what actually holds
      the line today is the units' `IPAddressAllow`/`Deny`, which the foreground
      path has no equivalent of. So the tempting host-config simplification (one
      wildcard `iifname "vm-cap*"` accept, written once and never touched again)
      is exactly wrong: it *grants* the reach. The accept has to pair iifname
      with destination address. The drop can still be a wildcard.
    - **A netns per capsule dissolves most of the above, and has been probed:
      it holds.** Identical /30 and MAC in every capsule (so one image, with no
      DHCP and no boot-time step), no path from A to B, and — because
      `net.ipv4.ip_forward` is per-netns — a forward control that is *ours*
      rather than one shared with docker and tailscale. `probe/netns.sh` models
      two capsules and a guest that already has root: it cannot reach the
      upstream, cannot reach the other capsule, and cannot be reached from
      outside even by something holding a route to it, while a process in the
      namespace reaches the internet normally. Flipping the namespace's
      `ip_forward` to 1 lets the guest straight out, which is what proves the
      switch is the thing doing the work.

      The plumbing went with it. A tap can be created directly inside a capsule
      namespace, or created in the root namespace and moved in — and after a
      move it is *gone* from root, so nothing there can delete it out from under
      the guest. Either way a process inside can bind an address on it. Creating
      it inside is the plan, because `tap-up`/`tap-down` are namespace-agnostic
      and putting the namespace on that unit makes stop symmetric with start
      (item 11); the move is the fallback. And ssh gets in over a unix socket
      (`/run/capsule/<name>/ssh.sock`, an `ssh` `ProxyCommand`), since the
      filesystem is not namespaced — no privilege, no port allocation, no
      socket-activation fd passing, and identical guest addresses never reach
      `known_hosts` because the socket path is the identity.

      The host module takes the namespace without a patch — verified against the
      pinned source, see item 11. What is left is one boot: whether firecracker
      comes up with its tap inside a namespace. Reading source is not running
      code.

      Netns applies to the **host-module path only**. The devshell path keeps
      working with no rebuild and no root, which a namespace cannot do, so the
      foreground path stays the current tap shape at N=1 — the same split
      `capsule-host` and `host/services.nix` already have.

      Three costs it found: a guest can reach its own capsule's *egress*
      address (weak host model again, one scope down — bind explicitly, drop on
      the veth); whatever aggregates the capsules' egress forwards, so
      proxy-to-proxy needs an interface-pair drop; and DNS needs
      `DNSStubListenerExtra=` plus `/etc/netns/<ns>/resolv.conf`, since loopback
      is per-namespace and `127.0.0.53` is not in it.

      The consequence worth reading this item for: it largely retires the
      "part of the perimeter is not in this repo" problem in item 7. The control
      becomes a sysctl inside a namespace this repo creates, the host's input
      chain leaves the guest path, and the runtime nftables verification plus
      its sudoers rule go with them. The host still has to forward and
      masquerade — but for the *proxy's* egress, with nothing about the guest's
      confinement resting on it. Cost is that namespace creation is root-side,
      so the host module stops being optional.

    Mixed targets stays deferred, with the instance record carrying its own
    target so it remains a relaxation rather than a rewrite (item 16).
