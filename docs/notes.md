# Notes — the item ledger

One numbered item per question the design has had to answer. **Cited from source
and from the other docs as `NOTES item N`**, so the numbers are frozen and
append-only: a resolved item is struck or annotated in place, never deleted and
never renumbered. Add at the end.

Resolved items are kept because the reasoning is the value — several of them
record a wrong first answer next to the measurement that corrected it, which is
what stops it being proposed again.

| # | item | state |
| --- | --- | --- |
| 1 | what has actually been run, versus reviewed | standing caveat |
| 2 | agent credentials into a guest with no shares | open |
| 3 | `pkgs.claude-code` is unfree, and guarded for channel drift | resolved |
| 4 | `just test` may want a live Postgres | open, unhit |
| 5 | ~~no `doctrine` binary in the guest~~ | resolved — `dev-tools` |
| 6 | proxy env is login-shell scope, so units don't inherit it | accepted |
| 7 | ~~host config~~ — the accept, the forward drop, and checking the drop | resolved, plus one host edit outstanding (item 18) |
| 8 | ~~git-daemon is unauthenticated~~ | resolved by deletion (item 18) |
| 9 | egress allowlist unproven; and the `MaxClients` hang that was not it | half — slots fixed, list still unproven |
| 10 | vendored crates and pre-seeded `node_modules`, dropped | decision |
| 11 | everything host-side runs as you | services half done, VMM half open |
| 12 | no resource ceiling on the VM | open |
| 13 | host SMT is on | accepted, not fixed |
| 14 | hypervisor choice — firecracker's floor is what shapes half this list | open option |
| 15 | two things that only grow: the volume, and the proxy log | measured, accepted |
| 16 | target-agnostic | done for one target; a second is untested |
| 17 | more than one capsule at a time | scoped — [Plan C](./plan-c-multi-capsule.md) |
| 18 | which way the git channel points | measured, inverted, done |

1. **What has actually been run.** The guest boots and the agent works over ssh;
   the perimeter has been exercised in both shapes — `capsule-host` in the
   devshell, and the units under dedicated uids on Sleipnir (item 11), including
   the guard's teardown against a live guest — though the unit path's git channel
   has since stopped serving, and item 18 is why. Not exercised: a second host, a
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
   `networking.firewall.interfaces."vm-capsule".allowedTCPPorts = [ 3128 ];`
   — and *not* plain `allowedTCPPorts`, which would also open the proxy on the
   LAN and the tailnet. It was `[ 3128 9418 ]` until the git channel inverted
   (item 18); dropping 9418 is a host-config edit and a rebuild, not something
   this repo can do.

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
   supervises a `watch` child that re-checks, and exits — tearing the proxy
   down with it — if forwarding comes up mid-session or the tap's
   address vanishes. Losing egress is the correct outcome; continuing to serve
   it past a missing control is not. `watch` is an injected fragment for the
   same reason `preflight` is: `perimeter/` must not learn what nftables is.
8. ~~**git-daemon is unauthenticated**~~ **— resolved by deletion (item 18).**
   It was, and `--enable=receive-pack` was what made the update hook
   load-bearing. It had accumulated `--strict-paths` with the mirror as the sole
   whitelisted path, a `git-daemon-export-ok` marker in place of `--export-all`,
   `IPAddressDeny` on the unit path, and finally a `safe.directory` exception to
   work at all. Every one of those confined a service the host only ran because
   the guest was the party initiating. The host initiates now, so there is no
   daemon, no hook, no mirror and no port. Kept here because the accretion is the
   argument: five guards on one service is what a wrongly-pointed channel costs.
9. **Egress allowlist is unproven** against a real Claude Code session —
   expect to add hosts on first run. `perimeter/egress-allow.txt`, restart
   `capsule-host`, no rebuild.

   **The first real workload found a limit that was not the allowlist.**
   `bun install` in the guest hung mid-download, repeatably, and succeeded
   instantly when killed and re-run. Nothing was denied and nothing was logged:
   tinyproxy was at `MaxClients 32`, so it had stopped accepting, while the
   kernel went on completing handshakes — 32 connections sat in the listener's
   accept queue (`ss -lnt 'sport = :3128'`, `Recv-Q 32`) and bun waited on
   sockets no worker would ever read. bun's default `--network-concurrency` is
   48, so it deadlocked against 32 workers every time; it looked intermittent
   only because how many packages are already cached decides how wide it fans
   out. `MaxClients 128` and `Timeout 300` now (`perimeter/default.nix`, with
   the reasoning). Worth generalising: a proxy in the path turns *any* client's
   parallelism into a shared resource, and the failure mode is a hang with no
   error on either side — not a refusal. The allowlist is the control; the slot
   count is capacity, and they fail in completely different ways.
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

      **That last claim is wrong, and item 18 has the measurement.** The two
      uids share one repo by necessity, so `hooks/` and `config` in the mirror
      are writable by the serving uid and `capsule-sync` runs git there as you.
      The route to the tree is your next sync.
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

      **Measured, and it climbs fast.** A pre-build capsule is a few hundred MiB,
      and `probe-freshness` has since shown that nearly all of it is *empty
      filesystem* — the ext4 a 32 GiB declaration costs before any content
      exists, plus tens of MiB for the repository. So the starting point is not
      what costs anything. One `just web-build test` took the volume to
      **7.4 GiB**, 6.9 GiB of that `/work/doctrine`, i.e. the checkout plus
      `target/` and `node_modules` — twenty-odd times, from one workload. So the
      per-capsule disk figure is the *volume*, not the store image, and the
      32 GiB cap is a few full builds away rather than theoretical. Nothing here
      is a leak: it is the build tree, kept on purpose, on a filesystem that
      cannot return blocks. Every figure, with how it was taken, is in
      [probes.md](./probes.md).

      **Treat 7.4 GiB as a floor and as this target's number.** n = 1, on
      doctrine, and cargo does not settle after one build — `target/` accretes
      across profiles, feature sets, dependency bumps and toolchain changes,
      and an agent iterating is the worst case for it. Expect a worked-in rust
      capsule to approach its cap. A target whose build is not rust would look
      nothing like this, which is an argument for `target.sizes.volume` being
      the per-target knob it already is.
    - `.vm/host/tinyproxy.log` has no rotation on the foreground path. Small,
      but it is the record of every egress attempt, so truncating it on start
      would be the wrong fix. Rotated (weekly, `copytruncate`) on the unit path
      only — see item 11.
16. **Target-agnostic — done for one target at a time.** Nothing structural tied
    the confinement to doctrine. The perimeter was already target-blind, and is
    more so since item 18 — it holds no repo path at all now, only the allowlist
    — and `host/services.nix` took `repo` as an option. What was actually hardcoded was smaller than it looked —
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
      the allowlist to the thing being confined. Not directly, since the host
      reads the human's working tree — but one careless merge of collected work
      and the agent has widened its own egress. The allowlist and the sizes are
      host-side config keyed by target name; only the *tool set* comes from the target, because that is a
      build input rather than a control. Keep that asymmetry explicit or the
      whole perimeter argument leaks.
    - **One target chosen ≠ several at once.** The parameterised single-target
      version is what got built, and it is an afternoon. What the other one costs
      is now written down — [Plan C](./plan-c-multi-capsule.md), which starts from the
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
    [Plan C](./plan-c-multi-capsule.md) is the list of what a plan has to settle, with the
    costs attached. The three things worth knowing without reading it:

    - **The deciding cost is the guest image, not the plumbing.** Tap, MAC and
      /30 reach the guest through its config today, and its store image is
      generated per config, so the obvious design pays N image blobs — N × disk,
      and N × *pack* time on every `dev-tools` bump. Not N × build: the closure
      is almost entirely shared. Getting the per-instance values out of the
      closure buys one image and N small runners, and there are two of them, not
      one: the guest's address, and the **base commit**, which a capsule is
      usually pinned to and which `capsule-clone` baked in the same way it baked
      the remote. A kernel param does *not* work for either — it lands in
      `toplevel` and so in the closure. See the netns option below, which makes
      the guest bit-identical without any of it.

      **Both halves are now closed, and the image is measured.** The base commit
      went as a side effect of item 18: the guest boots with an empty repository
      and `capsule-provision <ref>` is what puts history in it, so the ref is an
      argument to a host command and never reaches the closure. The address goes
      with netns. And the measurement that was supposed to decide this is in —
      [probes.md](./probes.md) has the closure, the per-instance blob and what
      each was taken with. It prices the N-blob design rather than forbidding it,
      which is why the recommendation rests on netns being verified and not on
      the disk number.
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
      pinned source, see item 11. **And the boot is no longer a question
      either**: `probe/netns-boot.sh` (`sudo probe-netns-boot`) puts the real
      capsule in a namespace with its tap created inside it and the runner
      started in there as you — 9 assertions green. The VMM comes up, the guest
      boots and answers ssh in the namespace, its NIC carries traffic on the
      namespaced tap, and the tap, the guest and its ssh port are all
      unreachable from the root namespace. ssh and git both cross a unix socket
      into it unprivileged. No host config was needed to establish any of that,
      which is the other result: the boot was never systemd's question.

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
18. **Which way the git channel points — measured, inverted, and done.**
    Asked because doctrine wants to know how a result leaves a capsule; answered
    with two commands, and the answer deleted more than it added.

    It used to be that the **guest pushed**: the host ran `receive-pack` as a
    live service on a port the guest could reach, and the ref hook, the
    `capsule-git` group and the mirror-sync uid all existed to confine that. The
    host now **initiates both directions** over the ssh channel that already
    existed — `capsule-provision <ref>` pushes history in, `capsule-collect`
    fetches work out into a host-side quarantine repo.

    **Both directions run, n = 1, on Sleipnir, on the devshell tap shape.** For
    doctrine — 66.4k objects, 32 MiB — each direction moves at ~100 MiB/s over
    the tap, so the link is not the cost. The push needs
    `receive.denyCurrentBranch=updateInstead`, which accepts an unborn HEAD and
    leaves a populated worktree, so provisioning is one host action with no bare
    intermediary and no guest-side step. It refuses once the worktree is dirty —
    mid-session re-provisioning is the thing that costs, and a bare
    `/work/origin.git` plus a guest-side local clone is the fallback if that
    matters. Freshness (item 17, `REQ-450`) means never re-provisioning, so those
    two decisions hold each other up: if anything ever needs a mid-session
    re-provision, both move together.

    **`denyCurrentBranch` only governs the branch HEAD names, and that is
    load-bearing.** Push a branch the guest's HEAD does not point at and the
    guard never applies: the ref lands, the worktree is untouched, and nothing
    says so — a capsule with history and no files. So the guest's HEAD must name
    the branch provision pushes to. It does, twice over: `capsule-seed` passes
    `--initial-branch` explicitly rather than leaning on `init.defaultBranch`,
    and `capsule-provision` checks the guest's advertised HEAD symref before
    pushing and refuses if it has moved — which is the case that actually
    happens, an agent running `git checkout -b`. `git ls-remote --symref` does
    the check over the git transport, so the program still knows only a URL; an
    empty repo advertises no symref at all, which is why the seed has to
    guarantee the first one.

    **A correction that was itself wrong, worth recording as method.** This rule
    was found by a reproduction that concluded the original probe had only
    appeared to work — `git init` giving `HEAD = refs/heads/master`, so the push
    of `edge` bypassing the guard. That is not what happened here: the probe ran
    `git init` *inside the guest*, where `/etc/gitconfig` sets
    `init.defaultBranch = edge`, so HEAD was on `edge` and `updateInstead` did
    apply. Verified after the fact — `git config --show-origin` reports
    `file:/etc/gitconfig edge`, `/work/scratch` HEAD is `refs/heads/edge`, and its
    worktree is populated. The rule is real and the fix is worth having; the
    retraction was an artefact of reproducing in a different environment, which is
    the same `n = 1` trap in the other direction.

    **Both programs then ran against a real fresh capsule**, which is what the two
    hand commands only modelled. Provision: 32 MiB in, worktree populated at the
    named commit on `edge`, clean. Collect: 32.10 MiB out at 118 MiB/s,
    `transfer.fsckObjects` passed, `ulimit -f` untouched, and exactly one ref
    landed — `refs/capsule/capsule/edge`, no `refs/tags/*`, which is the
    `--no-tags` claim holding in practice rather than in argument.

    **The first collect per capsule always pays a full transfer**, and that is the
    price of quarantining rather than a defect: a host-authored repo cannot share
    objects with `~/dev/doctrine`, so 32 MiB crosses the link and a second copy
    lands on disk even though the host already had every object. Later collects
    are incremental, which is most of why the quarantine is kept. `--depth` would
    cut the first one and breaks the second step into the real repo;
    `objects/info/alternates` pointing at the target repo would remove the copy
    and make the exhibit non-self-contained, which defeats the point of keeping
    it. So the cost stands: N capsules is N full first-fetches and N × repo on
    disk. Trivial at 3-4 on a dev machine, not at ranch scale — and it is the
    per-instance disk figure that was asked for.

    The doubled segment in `refs/capsule/capsule/edge` is the default instance
    name meeting the namespace, not redundancy: the quarantine is per capsule
    *and* the refs are namespaced, because `just fetch` merges several capsules'
    refs into one real repo and that is where the name has to survive. It reads
    correctly the moment a capsule is called anything else.

    **Git over the netns unix-socket `ProxyCommand` now runs**, which item 17 had
    only crossed with socat and raw bytes: `probe/netns-boot.sh` does
    `git ls-remote --symref` against the guest through the socket, as the human,
    with the guest in a namespace — the same call `capsule-provision` makes
    before it pushes. Still not measured: throughput over the socket (the tap did
    ~100 MiB/s each way), and whether `transfer.fsckObjects` rejects anything the
    old push path accepted.

    **The refspec does not fully decide the destination.** The fetch also wrote
    `refs/tags/*`, outside the `refs/capsule/<name>/*` namespace it was given,
    via automatic tag following. Harmless into a disposable quarantine repo, but
    `--no-tags` is what makes "the host chooses where guest refs land" true as
    stated, and the unqualified version of that claim should not be repeated.

    **Nor does the guest stop initiating connections to the host** — the proxy is
    one, and tinyproxy is the larger of the two C parsers of guest-authored
    input. What the inversion removes is any host service that parses guest git
    input. That is the claim worth making; the stronger one is wrong.

    **The finding that decides it was a live defect, not the probes.** The
    guest's `origin` was dead while both new directions worked. `capsule-gitd` is
    up and reachable; `upload-pack` refuses inside — git 2.55 `detected dubious
    ownership`, because the daemon runs as `capsule-git` and `capsule-sync`
    creates the mirror as the human. So item 1's "exercised in both shapes" is
    stale for this half: the unit path's git channel had stopped serving. Fixed
    where it broke — `GIT_CONFIG_*` on the unit, which is the `command` scope and
    so counts as the protected configuration `safe.directory` insists on. Needs a
    host rebuild to take effect, and is the safe direction of that exception: the
    serving uid trusts a repo the human owns. The reverse is the escalation
    below, and has no exception.

    Underneath that is the reason the check exists. The mirror is `2775` group
    `capsule-git` with `core.sharedRepository=group`, because the push design
    *requires* two uids to share one repo — the human syncs it, the daemon
    serves and receives into it. So `hooks/` and `config` are writable by the
    daemon's uid, and `capsule-sync` and `just fetch` both run git in that repo
    **as the human**. A compromised `receive-pack` — the precondition the uid
    split exists for — writes `hooks/post-receive` or sets `core.hooksPath`, and
    the next sync executes it as you. Item 11's "the uid serving the mirror has
    no path to the tree the mirror came from" is therefore not true: the path is
    the human's next sync. It is also the same shape as doctrine's rule about
    never running trusted git in a capsule-authored repository, reached from the
    host end instead of the guest end.

    **The inversion removes the precondition rather than the bug.** No repo is
    written by two uids anywhere: the host pushes from a repo only the human
    writes, fetches into a quarantine repo only the human writes, and the
    guest's repo is only the guest's. No setgid, no `sharedRepository`, no
    `safe.directory` exception, nothing for a compromised daemon to leave behind
    — because there is no daemon.

    **What went**, and the `safe.directory` fix above went with it, having lasted
    one commit: `perimeter/`'s `sync`, `gitd`, `pushGuard`, export marker and
    `gitPort` — leaving it the proxy and nothing else, which is what the perimeter
    now is; `host/services.nix`'s `capsule-gitd` unit, `capsule-git` user and
    group, and setgid state directory; the mirror itself, since it *was* the
    two-uid repo; `net.nix`'s `gitPort`; and the guest's `capsule-clone` and
    `capsule-push`, leaving the guest with no capsule-specific program at all.
    What arrived is `host/git-channel.nix` — two programs, no service, jail-shaped
    transport injected at the call site on the same seam as `preflight`/`watch`.
    One of the two ports leaves the host's own firewall stanza too (item 7 —
    outside this repo, so it is a README change and a rebuild you do). In PLAN_C
    it retires the per-capsule git daemon entirely, and with it the whole "one
    gitd uid or N" question.

    **It also finishes the single-image goal in item 17 for free.** The base
    commit was one of the two per-instance values that had to leave the guest's
    closure, and `capsule-clone` baked it in exactly as it baked the remote. It is
    now an argument to a host command — required, not defaulted, because a
    capsule's pin should be stated at every provision — so the only value left in
    the closure is the address, which netns already handles.

    Five things it costs or leaves open, none of them fixed by pretending
    otherwise:

    - **`index-pack` still parses guest bytes host-side.** True of every option
      including bundles. `transfer.fsckObjects` is on, and `ulimit -f`
      (`target.collectMaxPackBytes`) bounds the packfile — but **that is a
      backstop on one file, not a bound on the transfer.** RLIMIT_FSIZE: a pack
      of a million small objects never trips it and still fills the disk, and a
      delta bomb never trips it and still eats `index-pack`'s memory. A real
      bound needs a quota or a dedicated filesystem for the quarantine directory
      (disk), `ulimit -v` or a `MemoryMax` cgroup around the fetch (expansion),
      and `--depth` (input) — the first of which is host config, the same
      category as the nftables drop. **Do not read the `ulimit -f` as closing
      this.**
    - **The quarantine is persistent, not fresh**, which is a deviation from what
      was accepted: kept so a second collect is incremental, and because the
      repository is the retained exhibit. The execution-context rule is
      untouched — it is host-created, host-configured, and the guest can write
      neither its config nor its hooks — only freshness changed. Recorded here
      rather than left to be discovered.
    - **The sha is the pin; the quarantine repo is the exhibit.** So reaping the
      quarantine is when the exhibit expires, and nothing here sets that
      retention. First concrete instance of a knob that was deliberately left
      unspecified upstream.
    - **Non-git provisioning inputs have no program.** The guest boots empty and
      gets one push, which carries committed objects only. Uncommitted files,
      gitignored working material, generated config and secrets have no carrier
      — today's `/work/.env` is still made by hand over ssh. The *transport*
      exists and is already host-initiated; what is missing is anything that uses
      it, and a worker needing a `.env` is how that gets discovered rather than
      decided.
    - **The agent loses the ability to hand work over.** `capsule-push` was the
      guest's own act; now only the host pulls. A workflow regression rather than
      a security one, and the only thing the inversion makes worse.

    **The first thing a fresh capsule broke was `known_hosts`, and it was the git
    channel that made it matter.** The guest's host keys live on its volume, so a
    new volume means new keys at the same address; a real capsule hit exactly
    that. Before, ssh was convenience and a changed key annoyed `just ssh`. Now
    the channel rides ssh, so it blocks provisioning outright — and freshness
    (item 17, `REQ-450`) means it fires on *every* capsule, not occasionally.
    `StrictHostKeyChecking=accept-new` is not the fix: it accepts hosts that are
    unknown, and this one is *changed*.

    So `guestSsh` in `flake.nix` turns the check off and keeps no record
    (`UserKnownHostsFile=/dev/null`), injected through `sshCommand` — the seam
    that exists for exactly this, so `host/git-channel.nix` still knows only a
    URL. `vm-stop` takes it too, or a fresh capsule's key would send its shutdown
    down the API-socket fallback. **It is sound only because of what the link
    is:** a /30 this host created, one peer, nobody on it to be in the middle. A
    bridge, a LAN or another machine invalidates it, and it has to change in the
    same commit that changes the transport. A capsule-scoped `known_hosts` file
    was the tidier-looking option and is worse — it accumulates a stale key per
    capsule and reintroduces the failure it was meant to fix. `just ssh` and
    `just admin` deliberately keep the strict default: a human is there to read
    the warning. Under netns none of this is needed, because the socket path is
    the identity (item 17).
