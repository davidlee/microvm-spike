# microvm.nix spike — notes

A **capsule**: a firecracker microVM used as an agent jail. It holds a real
git clone of `~/dev/doctrine`, can run `just web-build` / `just test`, and has
exactly enough network for a coding agent to work — no more.

## Layout

| path                         | what                                               |
| ---------------------------- | -------------------------------------------------- |
| `flake.nix`                  | VMs, devshell, tap + runner scripts, the link's config |
| `perimeter/default.nix`      | proxy, mirror, ref guard — `capsule-host`. Jail-agnostic |
| `perimeter/egress-allow.txt` | proxy hostname allowlist — plain file, no rebuild   |
| `vm/common.nix`              | shared guest config (firecracker, serial console)   |
| `vm/hello.nix`               | smoke test VM, no network                           |
| `vm/capsule.nix`             | the agent jail                                      |
| `.vm/<name>/`                | per-VM state: volume images, API socket (gitignored)|
| `.vm/host/`                  | the bare mirror, proxy config + logs (gitignored)   |

The split is load-bearing, not tidiness: the perimeter is where nearly all the
policy lives and it is the only part that ports to a non-firecracker jail
(PLAN_B.md). It takes addresses and ports as arguments and one injected
`preflight` fragment — on firecracker, the tap-address check — so nothing
hypervisor- or platform-shaped leaks into it. Runtime paths are environment
(`CAPSULE_ROOT`, `CAPSULE_STATE`, `CAPSULE_ALLOWLIST`, `CAPSULE_REPO`), which
is what keeps the allowlist an editable file rather than a store path.

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
`HTTPS_PROXY` and no resolver at all — DNS happens in the proxy, so a name
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

1. **Nothing here has been run yet** — no eval, no build. Expect first-boot
   friction.
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
   dropping `iifname`/`oifname "vm-capsule"` in the forward hook is the control;
   `capsule-net up` warns when forwarding goes live so the omission is visible
   rather than latent. Deliberately *not*
   `networking.firewall.filterForward`, which flips the whole host's forward
   policy to drop (`firewall-nftables.nix` renders `policy drop` on the forward
   chain) and whose `extraForwardRules` land in an allow-list chain that cannot
   express a drop anyway. A separate table needs no cooperation from the
   firewall's: a `drop` verdict in any chain is terminal for the packet.

   IPv6 on the tap is host stack the guest can reach for no benefit, and is
   turned off by `capsule-net` before the link comes up rather than by a
   boot-time sysctl, which would fire before the interface exists.
8. **git-daemon is unauthenticated**, and `--enable=receive-pack` is what makes
   the update hook load-bearing. Now narrowed by two independent guards:
   `--strict-paths` plus the mirror as the sole whitelisted path (so no sibling
   under `.vm/host/` that happens to look like a repo can be served), and a
   per-repo `git-daemon-export-ok` marker in place of `--export-all`. Still
   reachable from the host itself, which is accepted.
9. **Egress allowlist is unproven** against a real Claude Code session —
   expect to add hosts on first run. `perimeter/egress-allow.txt`, restart
   `capsule-host`, no rebuild.
10. **Dropped since the first cut:** vendored crates
    (`rustPlatform.importCargoLock`) and the pre-seeded `node_modules` from
    doctrine's `web-modules` FOD. Both existed to make an offline capsule
    build; the proxy supersedes them, and dropping them removed this flake's
    dependency on doctrine's flake (and its `pub` / `llm-agents` transitives).
    Worth restoring if you want cold-start builds without network.
11. **Everything host-side runs as you.** Biggest remaining gap (see the jailer
    note above), and it is two problems that happen to share one fix.

    - The **VMM**: a firecracker escape lands on uid 1000, with ambient access
      to `~/.ssh`, `~/.claude`, every repo and every shell rc — precisely the
      assets the capsule exists to keep away from the agent.
    - **`capsule-host`**: tinyproxy is C parsing guest-authored HTTP, and
      git-daemon runs `receive-pack`, both as you. This half is independent of
      the hypervisor and gets no benefit from anything in the VM story, so it
      is worth doing even if the VMM never moves.

    Fix is a dedicated host uid owning the tap, the mirror and both processes,
    so a break-out lands on an account holding nothing. The cheap route for the
    VMM is microvm.nix's **host module**, which already runs VMs as
    `User=microvm` out of `/var/lib/microvms` with a root-side
    `microvm-tap-interfaces@` service — and which would also retire most of the
    lifecycle jank in CLAUDE.md, since `systemctl restart microvm@capsule`
    SIGTERMs the VMM after `ExecStop` and frees the tap. `capsule-host` needs
    no upstream help: it is already a plain foreground process with its paths
    in the environment (`CAPSULE_STATE`, `CAPSULE_ALLOWLIST`, `CAPSULE_REPO`),
    which is most of what a unit file wants.

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

    Costs: the VM is declared host-side (`microvm.vms.<name>.flake` can still
    point here), the console moves to the journal, and iterating means a host
    rebuild. Keep the standalone `nix run` path for development, add the
    host-module path as the real posture.
12. **No resource ceiling** — though less is unbounded than that suggests, and
    the distinction matters for what is worth fixing.

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
    - `.vm/host/tinyproxy.log` has no rotation. Small, but it is the record of
      every egress attempt, so truncating it on start would be the wrong fix —
      rotate it.
