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
| 16 | target-agnostic | done, and a second target has since exercised it — item 23 |
| 17 | more than one capsule at a time | scoped — [Plan C](./plan-c-multi-capsule.md) |
| 18 | which way the git channel points | measured, inverted, done |
| 19 | the baseline build, and where a figure is allowed to live | built, run, measured |
| 20 | which capsule a host program is talking to | decided, built, run at N=2 on the devshell path |
| 21 | a declared capsule needs a flake attribute, and all of them are one value | built, unrun — needs the rebuild |
| 22 | secrets at start, and a payload that may be absent | built, unrun |

1. **What has actually been run.** The guest boots and the agent works over ssh;
   the perimeter has been exercised in both shapes — `capsule-host` in the
   devshell, and the units under dedicated uids on Sleipnir (item 11), including
   the guard's teardown against a live guest — though the unit path's git channel
   has since stopped serving, and item 18 is why. Not exercised: a second host, a
   second target repo (item 16), and the VMM half of item 11. Assume anything
   documented here but not named in this paragraph is reviewed rather than run.
2. **Agent credentials — solved by `capsule-inject`.** No shares, so nothing can
   be injected from the host *filesystem*; the channel that does it is the ssh
   one that already exists, host-initiated, as the human. `setup.nix` declares
   what leaves this host and `host/inject.nix` is the mechanism, which never
   learns what a credential is — each entry brings its own filter.

   Two payloads, and the split is the finding: the OAuth **token** is
   `~/.claude/.credentials.json`, a file that is nothing but the credential, so
   there is no subsection to take; `~/.claude.json` holds **no token at all** —
   it is identity plus ninety keys of local state, of which four travel and
   `projects`, `githubRepoPaths`, `mcpServers` and every cache do not. A
   whole-directory copy would have taken `history.jsonl` (3 MB of prompts) and
   `file-history/` into a jail that exists to not have them.

   The token rotates on refresh, and a capsule holds a *copy* rather than
   sharing the file — so the two diverge and neither is authoritative. Hence
   write-if-absent with an explicit `--force`, rather than a merge or a
   clobber. Running several agents off one credential is already known to work
   (the bwrap jails do it), but they share one file; that answers concurrency,
   not divergence.

   The older path still works and needs none of this: `export
   ANTHROPIC_API_KEY=...` in `/work/.env`, sourced at login. OAuth's device flow
   wants a browser, which is why the token is carried rather than obtained.
   **That path has a carrier now too** — the same one, as a declared payload, and
   `capsule <name> start` runs it (item 22).
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

   **All of the above is the tap shape, and the module path has now left it.**
   Under netns the tap is inside a namespace this repo's units create, so the
   control is that namespace's own `ip_forward` — nobody else writes it, there
   is no race with docker, no sudoers rule, and no `latent` state: unverifiable
   is a refusal, because an answer these units cannot read is their own fault
   and not someone else's config. What the host still owns is forwarding and
   NAT for the *proxies'* egress, which the module installs itself and on which
   nothing about a guest's confinement rests. This paragraph's machinery stays
   exactly as it is for the devshell path, which still has a tap in the root
   namespace and still needs every word of it (`host/netns.nix`,
   `host/perimeter-check.nix`).

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
      assets the capsule exists to keep away from the agent. **Written, unrun:**
      the netns work needs `microvm@<name>` to be a unit anyway, so the module
      now carries drop-ins for it and for its tap unit, and running the VMM
      under microvm.nix's own uid is what that buys. It stops short of
      *declaring* the VM — `microvm -c <name>` rather than `microvm.vms.<name>`
      — because declaring it makes the host's config evaluate the guest
      closure, which `~/flakes` must not do.
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

    **Resolved, and "the guest ignores SendCtrlAltDel" was the wrong reading of
    it.** The guest never *received* it. Firecracker's only shutdown signal is an
    i8042 keystroke, nixpkgs builds `CONFIG_SERIO_I8042` and
    `CONFIG_KEYBOARD_ATKBD` as modules, nothing autoloads a legacy port device,
    and `security.lockKernelModules` makes the omission permanent — so there was
    no keyboard to press the keys on. Loading them (`boot.kernelModules`, before
    the lock) does *not* fix it either: firecracker's i8042 is a stub for CPU
    reset and the driver refuses it outright, `probe with driver i8042 failed
    with error -22`. That route is closed, not merely unused.

    What is open instead: the guest has no ACPI power button, so a poweroff
    halts the vCPU and leaves the VMM holding the tap (`Power off not available:
    System halted instead` — the EBUSY trap), but a **reboot** unmounts and then
    resets, and `reboot=k` makes that reset the one thing the i8042 stub *does*
    implement. Measured: `Firecracker exiting successfully. exit_code=0`, with
    nothing killing it. So the stop is a reboot asked for over ssh, which is
    `host/halt.nix` — one program, both paths, since waiting for a hypervisor is
    the caller's job and only the caller can see one.

    That leaves the identity, which is the whole of what had to be decided. A
    unit has no ssh agent and no way into the human's home, and the `+` prefix
    that would make `ExecStop` root also drops it into the *root* namespace where
    the guest is unroutable — the same prefix trap noted below. So the host keeps
    a stop key of its own: private half readable by the `microvm` uid (which
    already owns the guest's memory and disk, so it grants nothing new), public
    half in the guest's closure. Rejected: the human's `~/.ssh/id`, which works
    only while it has no passphrase and would fail first at a host shutdown, and
    a `systemd-run --uid=` hop, which needs an agent that a shutting-down host
    does not have. A capsule with no readable stop key refuses to *start*, since
    the alternative is finding out at the only moment nobody is watching.

    A side effect, measured A/B and unexplained: loading `i8042`/`atkbd` in the
    guest also makes **Enter work in TUIs on the serial console**, which had been
    a standing gotcha. Neither driver binds anything — i8042 fails to probe, so
    atkbd has no port — and no input device appears, so the mechanism is not
    known. Recorded because it reproduces both ways, not because it is
    understood.

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
    | memory   | `target.sizes.mem`, hard — but a **ceiling**, not a charge. ~~the VM costs 16 GiB for its whole life~~ **struck**: firecracker does not preallocate and the guest root is tmpfs, so two booted capsules cost ~1.5 GiB between them ([probes](./probes.md)) | what the guest *touches* — no balloon, so a high-water mark is never returned. ~~Unmeasured under load~~ **measured**: two cold builds at once peaked at 7774 and 6801 MiB inside an 8192 ceiling with zero reclaim ([probes](./probes.md#two-cold-builds-at-once)), so memory is *not* the binding term at N=2. What is still open is the ratchet, not the peak — a capsule holds most of its ceiling until it is stopped |
    | vCPU     | `target.sizes.vcpu` threads of 32 | the *share*: those threads at 100% compete with everything else you are doing. A real charge from the first busy thread, unlike memory |
    | disk     | 32 GiB, hard — a sparse file cannot exceed its declared size | see item 15 |
    | disk I/O | none | a `cargo build` in the guest hammers the host disk unthrottled |

    So the real asks are `CPUQuota`/`CPUWeight` and `IOWeight`, plus
    `MemoryMax` as a backstop against a VMM leak rather than against the guest.
    Interim, without moving to the host module: `systemd-run --user --scope -p
    CPUQuota=400% -p IOWeight=50 -p MemoryMax=10G -- vm capsule`. Caps only, no
    uid separation, and the user slice needs the `cpu` controller delegated for
    the quota to take.

    **How the memory row came to be wrong is worth more than the row.** It was
    read off `target.nix` — a configuration fact, labelled as one — and it
    travelled as a measurement anyway: into this ledger, into the spike's status
    doc, into doctrine's EVD-019, and into the design of the very probe that
    eventually refuted it. DEC-189 says a row needs a falsifying delta; the
    corollary is that **a number needs one too**, and a number read off a config
    file has none. The same trap is why [probes.md](./probes.md) exists and why
    it records provenance per figure.
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

      **Most of that was the capsule not knowing what machine it was.** Those
      figures predate `target.nix`'s `guestConfig`, so cargo's defaults applied:
      full debuginfo and an incremental cache. With `debug = 0` and
      `incremental = false` the same workload leaves **1.1 GiB** in
      `/work/doctrine`. The shape of this item is unchanged — it still only
      grows, and blocks still never come back — but the rate is roughly six
      times lower, and the fix was config in the closure rather than any
      machinery.

      **Treat either number as a floor and as this target's.** n = 1, on
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

    ~~Untested: a second target. The parameterisation is only *claimed* until one
    exists~~ — **tested, by item 23**: panopticon, and the friction landed
    exactly where this paragraph guessed. `extraTools`, the cache set and the
    sizes were all this target's toolchain wearing a general name, and one of
    them was worse than that — `toolsPackage = null` plus `extraTools` is not a
    usable absent path for a tool set that is not a list of nixpkgs attr names.

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

      **All three now have their fix verified, and so does the thing none of
      those probes had in it: the perimeter.** `probe/netns-egress.sh`
      (`sudo probe-netns-egress`) joins the real `capsule-proxy` to the real
      capsule's namespace and asks the real guest to get out — 27 assertions,
      green on the first run, [probes.md](./probes.md). The allowlist answers
      200 for a host on it and 403 for one off it; guest root holding the route
      it can always add reaches neither the internet nor the aggregator; each
      denial is paired with the control that removes the thing supposedly doing
      the work and watches it fall over. Egress under netns was the last
      unverified claim in this shape and is no longer one.

      Two findings from it that change what the next step is, rather than
      confirming what was expected:

      - **The unit inventory in Plan C undercounted.** "One oneshot unit and two
        drop-ins" is the *namespace*; a working perimeter also needs a veth per
        capsule to an aggregating namespace, that namespace's forwarding and its
        two drops, and NAT plus forwarding on the host. All host-side, none of
        it in the guest — but it is the difference between one unit and a
        module.
      - **The DNS fix is a `~/flakes` edit this host does not have**, and the
        probe fell back to a public resolver rather than pretending otherwise.
        That fallback silently loses the DoT hop, which is precisely the
        property item 7's chain exists for. So the netns path's DNS claim is
        *unproven*, not merely unwired, until the stub address and its port-53
        input allow land. Do it in the same change as the units, not after.

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
19. **The baseline build, and where a figure is allowed to live.** The last of
    the three setup problems (docs/design.md) is a *command*, not a payload: run
    the target's own build-and-test to green, which both proves the capsule works
    and fills its caches. On a fresh volume that is the **cold build** — the
    largest term in time-to-interactive, and the one figure `probe/freshness.sh`
    cannot take, because its namespace has no upstream to fetch a crate from.

    Built as `capsule-baseline` (`host/baseline.nix`, `target.nix`'s `baseline`).
    Four decisions in it are worth freezing, because three of them are paid-for
    lessons rather than preferences:

    - **The record is not the terminal.** The sizing runs that produced the
      figures in [probes.md](./probes.md) lost two attempts to scrollback: the
      first printed its numbers after the agent exited, the agent was exited with
      Ctrl-C, and SIGINT killed the shell that was going to print them. So the
      run writes its log and one line of `/work/baseline/history.tsv` onto the
      volume *as it goes*. The volume is where a figure survives the session;
      probes.md is where it survives the capsule, since freshness is implemented
      by deleting volumes.
    - **The run does not depend on the session.** The guest half `setsid`s into
      its own session, so closing the channel cannot SIGHUP a twenty-minute
      build. The host attaches with `tail --pid` to watch, and leaving is free —
      re-running attaches to the run in flight rather than starting a second,
      because two runs interleaved into one record are two figures lost, not one
      gained.
    - **It is `bash -l` in the guest, and that is item 6 arriving.** `ssh host
      cmd` is neither login nor interactive, so it has no `environment.variables`
      — no proxy, no `CARGO_HOME`, no `TMPDIR`. A baseline run without the proxy
      fails looking like a network fault, which is the most expensive shape a
      failure can take here. The log's header prints `http_proxy` for that
      reason.
    - **It is not a probe.** `probe/` is evidence that needs root and answers a
      design question about the shape; this is a lifecycle command a human runs
      on a capsule they are about to work in, which happens to produce a figure.
      Putting it in `probe/` would have meant a probe that needs the real
      perimeter up, the real credentials in, and twenty minutes — none of which
      the others need.

    Generic-plus-a-value, per CLAUDE.md's guinea-pig rule: the capability is *run
    the instance's declared build-and-test and record what it cost*, and `just
    web-build test` is one target's instance of it. `baseline = null` drops the
    program rather than shipping one that cannot work — the same absent-path
    discipline as `toolsPackage`.

    **Run 1 took the number: 109 s to green on a deleted volume**, ~1.1 GiB of
    volume, figures in [probes.md](./probes.md). Two things it established beyond
    the duration. The record proves its own coldness — caches 123 MiB before,
    `.cargo` alone 144 MiB after — which is why the sizes are in the row and not
    only in the log: a duration is a cold-build figure only if something in the
    same row says the caches were empty. And **time-to-interactive is ~2 minutes,
    ~93% of it this one build**, which reorders what is worth optimising: every
    other figure this repo has taken is noise beside it.

    The `before:` breakdown was lost to scrollback on the very first run, and cost
    nothing, because it was also in the log on the volume. The lesson that shaped
    the program was confirmed by the program's first use.

    Still open: the pair probe's question. Two capsules building at once is a
    scheduling question, and two `capsule-baseline`s are how it gets asked — each
    with its own record on its own volume, which is the attribution half.

20. **Which capsule a host program is talking to.** One bug, in one line, and it
    is the thing that stood between the units running at N=1 and running at N=2:
    `host/services.nix` built `hostPrograms` once, with the lowest-indexed
    capsule's relay socket in `sshArgs`. So `capsule-provision`,
    `capsule-collect`, `capsule-inject` and `capsule-baseline` each carried one
    capsule's transport in their store path, and a second capsule had no way in
    for any of them. `probe/two-capsules.sh` is where it surfaced — it needed two
    sets of programs to provision two capsules, and recorded that as a finding
    rather than plumbing.

    The one-image lever is what makes the fix small. Every capsule runs the same
    guest from the same store path at the same address (item 17), so the *only*
    thing that differs between two of them is the relay socket — and that path is
    a pure function of the name (`capsules.socketOf`). N programs would be N store
    paths differing in one string. So the name is a run-time value and the
    transport is derived from it: one store path, every capsule.

    **The seam was already right; it only had to widen.** `sshArgs` was injected
    at the call site precisely so the two paths could differ (`host/programs.nix`).
    It is now `transport`, a *shell fragment* rather than a value: spliced at the
    top of each program, it resolves which capsule this invocation means, strips
    that argument out of `"$@"` before the program's own flag loop sees it, and
    sets `ssh_cmd`. The devshell injects the direct form, the units inject the
    via-socket form, and neither `host/programs.nix` nor the three programs under
    it learn anything about namespaces or sockets.

    **The CLI question, decided rather than accreted.** Plan C item 7 wants a
    `capsule <name> <verb>` front end; this needed an answer first, because
    `capsule-provision <ref>` and `capsule-collect <quarantine-name>` took
    different positionals and neither took a capsule. Three things settled it:

    - **A flag, not a leading positional.** `capsule-collect faux` means a
      quarantine today; making it mean a capsule tomorrow is a silent change of
      meaning on a command that already exists. `--capsule <name>` (or
      `--capsule=<name>`) collides with nothing, and every one of the four
      already refuses an unrecognised `-*`.
    - **`CAPSULE_NAME` as the session default**, joining `CAPSULE_ROOT`,
      `CAPSULE_STATE` and `CAPSULE_REPO` — you work on one capsule for an hour,
      not one command. Not the *only* form, because `VAR=x prog` is not
      universal: nushell wants `with-env`, and this host's shell is nushell.
    - **The default is `capsule`, and it is a value** (`capsules.default`), so the
      single-capsule state this host already has keeps working untyped and the
      `just` recipes' default is the same word by derivation rather than by
      coincidence.

    A `capsule` CLI on top of this is now thin: resolve the name, export it, exec.
    That is the argument for doing it in this order.

    **One argument fewer, not one more.** `capsule-collect`'s positional
    quarantine name *was* the capsule name at every call site, so it is gone: a
    capsule names its own refs and its own quarantine, at the same paths as
    before. The asymmetry closed by deleting half of it.

    Two smaller decisions worth freezing, both refusals:

    - The devshell's fragment **refuses a name that is not its one capsule**
      rather than ignoring it. Ignoring it is a silent success — "provisioned
      `edge`" while the bytes went to the only capsule there is.
    - The via-socket fragment **refuses when the socket is not there**, naming the
      relay unit. Without it the failure is socat's, one layer down, and reads as
      a dead guest.

    Not done this way, deliberately: probing for the socket and falling back to
    the direct address — which is what `just _guest-ssh` does. It would delete the
    injection entirely, and with it the property that `host/programs.nix` knows no
    transport: a program that can try both has both baked in. It also turns a
    stopped relay into an unroutable-address timeout instead of a refusal.

    **Run, and by the probe that found it: `sudo probe-two-capsules`, 28/28.** One
    program set, `--capsule` per call, two capsules provisioning over their own
    sockets and collecting into their own quarantines. The four assertions that
    depend on the transport are the four that would have failed, and the figures
    reproduced run 1 inside a tenth of a second ([probes.md](./probes.md)). The
    `%q` requoting of `GIT_SSH_COMMAND` is exercised by that run — a provision and
    a collect each go through it, over a ProxyCommand with spaces in it.

    ~~Still unrun: the *module* path.~~ Run — the module's copies of all four are
    what provisioned, injected and baselined both capsules at N=2, so the
    via-socket form with an absolute `socat` and the `wrap`ped state directories is
    exercised.

    **The CLI is built, and what it cost was a boundary rather than code.**
    `host/cli.nix`: `capsule [<name>] <verb> [args…]`, name first, omitted meaning
    `capsules.default`. It resolves a name, picks a copy, execs. Three things it
    decided on the way:

    - **Where the split falls.** `microvm -c <name>` resolves the instance's name
      as a flake attribute (item 21), so *creating* a capsule cannot happen without
      this checkout and *running* one has no business needing it — the units are on
      the host and a human logged into it has no repo. So `just up` keeps the create
      and the tap refusal, and every other run-time verb moved into the program.
      The recipes that remain are one-line delegations kept for their defaults and
      their comments; `_capsule` and `_guest-ssh` are gone rather than wrapped,
      which is the whole reason to do this at all — the alternative was a second
      implementation of the ssh door and the copy-picking.
    - **Picking a copy is a front end's latitude; carrying two transports is not.**
      The four programs still refuse rather than guess, which is this item's
      decision and stands. What the front end does is choose between two *copies*
      of one program — the same latitude `just _capsule` already took, now in one
      place. It injects no transport and holds no socket path of its own:
      `capsules.socketOf` applied to a shell expression, as everywhere else.
    - **Two refusals, both of them ambiguity rather than failure.** A capsule whose
      name is also a verb is an *eval* error, since `capsule <x> …` could then be
      read either way and both lists are known at build time. And a `--capsule` in
      the arguments of an already-named capsule is refused instead of resolved: the
      programs' own parse takes the last one, so `capsule capsule-b provision
      --capsule capsule` would have succeeded against the wrong capsule quietly.

    One store path, installed by both paths, and that is the honest statement of
    what it is: unlike the four programs it has no transport, so there is nothing
    for a second instantiation to differ in. `.#capsule-cli` as an attribute,
    `capsule` as the program — `.#capsule` has been the guest runner all along.

    **The door is run, and the thing it was needed for is what proved it.** `capsule
    <name> ssh 'tail -1 /work/baseline/history.tsv'` answered 112 s from one capsule
    and 121 s from the other — the pair of rows the load round could not tell apart
    by prompt, since every guest is `agent@capsule` (item 21). The hostname is still
    `capsule` in both, which is the price, not a bug; asking the *volume* is the
    answer, and the CLI is what makes asking one command per capsule.

    **`status` and the aggregates, and how the blindness actually closed.** `just
    status` could not see inside a namespace it did not own, and the fix is not a
    way in — `ip netns exec` wants CAP_SYS_ADMIN and a status that needs root is a
    status nobody runs. It is *naming the witness*. Every column of `capsule all
    status` is readable from the root namespace (`LoadState`/`SubState` of the VM,
    proxy and relay units, the socket, the quarantine's ref count), plus one that is
    not any unit's opinion of itself: an ssh probe through the capsule's own socket,
    because every unit reported health through the evening the VM was crash-looping
    in the wrong namespace. What is genuinely inside — each namespace's
    `ip_forward=0`, the tap's input drop, the drops between capsules — is
    `capsule-perimeter-guard`'s, audited every 10 s with egress bound to it, so its
    being active *is* the per-namespace verdict for every capsule at once. The table
    prints that as a witness line rather than printing "unknown".

    Two decisions inside it:

    - **`all` is a name, not a flag**, so it composes with the name-first grammar
      instead of adding a per-verb option. It is refused as a *capsule* name at eval,
      same as a name that collides with a verb.
    - **`all` aggregates questions, not actions.** `status`, `branches` and `fetch`
      take it; `start`, `stop`, `setup` and the four programs do not, because what to
      do when the third of five fails is a policy nobody has decided — and an action
      half-applied across N capsules is worse than one refused. When someone wants
      that policy, this is where it goes.
    - The probe uses the git channel's ssh relaxation rather than the human's strict
      door (`host/guest-ssh.nix`): a rotated host key is a fact about identity, and
      reporting it as an unreachable guest would be the wrong answer to the question
      being asked. The human's `ssh`/`admin` keep the strict default, because a
      human is there to read the warning.

    On the way past, one real bug in the recipe this replaced: `just proxy-log` still
    looked for `/var/lib/capsule-proxy/tinyproxy.log`, from before the proxy became
    one unit per capsule, so it fell through to the devshell path's log and reported
    "no proxy log yet" on a host with two of them.

    **Correction: the socket being the identity means its lifetime must be the
    capsule's, and it was not.** `capsule-ssh-relay-<name>` bound only to its
    *namespace* unit, which is `active exited` and stays up — correct for a
    namespace, wrong for the way into a guest. So a stopped capsule kept a live
    listener, and because `[ -S "$sock" ]` is the whole test both transports use,
    the consequences ran in both directions at once: the devshell's copy
    **refused** on a module path that owned nothing, and the module's copy
    **hung** — socat accepts the unix connection immediately and then blocks
    forwarding to a guest that is not there. Two capsules dead, two proxies dead,
    two relays `active running`, and every program on the host convinced the
    module path was live.

    The fix is one list: `bindsTo` the tap unit as well, which is what the proxy
    already does and for the same reason — the tap is what a VM pulls up and takes
    down, so both follow the guest instead of the namespace. `ConnectTimeout=10`
    in `host/guest-ssh.nix` was already there and is the reason this reads as a
    slow failure rather than a wedge, but it is the wrong layer to rely on: a
    bounded lie is still a lie, and the honest state of a stopped capsule is no
    socket. Note which of the two symptoms is the dangerous one — the refusal is
    loud and names the copy to run, so it was the *hang* that cost the time, from
    the copy the refusal recommends.

21. **A declared capsule needs a flake attribute, and all of them are one
    value.** Declaring a second capsule in `capsules.nix` generated its
    namespace, proxy and relay units — and then `sudo microvm -c capsule-b -f .`
    had nothing to create from. The CLI appends
    `#nixosConfigurations.<name>.config.microvm.declaredRunner` itself
    (CLAUDE.md), so *the instance's name is a flake attribute*, while
    `nixosConfigurations` was a two-entry literal: `hello` and `capsule`.

    The obvious fix is the wrong one. `mkVm name ./vm/capsule.nix` per instance
    reads as one line of `mapAttrs`, and it sets `networking.hostName = name` —
    the hostname is *in the closure*, so that is a second guest, a second 12 GiB
    image and a second thing to keep in step, for a string. The one-image lever
    (item 17) is not an efficiency here; it is what makes an instance cheap
    enough to be a unit start rather than a design change.

    So the mapping is to a single value: `capsuleVm` is built once, and every
    declared capsule is bound to *it* rather than to a rebuild of it. Identical
    modules would already produce an identical derivation, but binding the same
    value says so at the point someone would otherwise add a per-instance
    argument — the property stops depending on nobody noticing that the
    hostname, or the index, or the socket path, could be threaded in "just for
    this one". What differs between two capsules stays exactly what differed
    before: a namespace, a volume, a state directory, a relay socket.

    The price is the one plan-c-implementation.md already named: the hostname is
    `capsule` in every guest, so the prompt inside one does not say which. Paid
    knowingly, and not with `systemd.hostname=` on the cmdline — a per-instance
    cmdline is a per-instance closure again, by another route.
22. **Secrets at start, and a payload that may be absent.** Item 2 built the
    carrier and left the older path uncarried: `export ANTHROPIC_API_KEY=…` in
    `/work/.env` still had to be typed into every capsule over ssh, and at N that
    is a ritual per capsule. It needed no new mechanism, which is the finding —
    `capsule-inject` already pushes *declared payloads produced host-side*, and a
    `.env` is one. So the whole of it is a third entry in `setup.nix` plus two
    changes to what surrounds it.

    **The direction was never open.** `op` (1Password CLI) renders a template by
    talking to a host unix socket, and firecracker has no shares, so a guest can
    never reach it: the environment is rendered *here* and pushed. Both supported
    shapes are therefore the same interface — a `produce` fragment — and which one
    a host uses is a line in the declaration rather than a fork in the code. The
    plain file is the shipped default because `op` is unfree and a host that does
    not use one should not carry it in the program's closure; the `op` form is
    written out in the entry's comment.

    **`start` is where it goes, and that changed what a start promises.** A
    running VMM was the old promise, and it left a capsule nobody can work in —
    `$HOME` is on the volume freshness deletes, so credentials and secrets are
    gone with it. So `capsule <name> start` waits for the guest to answer and then
    injects the whole list, which is only safe because every payload is
    write-if-absent: a restarted capsule keeps what it has, and a repeat is a
    no-op rather than a second answer. The wait is bounded on wall clock rather
    than on attempts, because a failing ssh costs anything from nothing to
    `ConnectTimeout` and N tries is therefore not a duration. `setup` still
    injects too: a guest started by hand, or one that rebooted, has had no start
    of ours.

    **A shared declaration needs a working absent path**, which is the one new
    field: `optional = true` means a source that is not on this host is a skip
    with a message rather than a failure. Without it the entry is a host-specific
    file that every other host fails to start capsules over — the same rule as
    `toolsPackage = null` (CLAUDE.md, limb 2). It also collapsed two cases into
    one: absence and emptiness are the same fact, since a filter that matched
    nothing and a file that is not there both mean there is no payload, and
    pushing either replaces a working credential with nothing. `required` says
    which of them is a failure, once, instead of every entry saying it and one of
    them forgetting.

    Not decided, and deliberately: **a rotated secret does not reach a running
    capsule.** Write-if-absent means editing the host's `.env` changes nothing
    until `capsule <name> inject env --force`, which discards whatever the guest
    wrote into that file. Refreshing at every start is one word of policy and
    would silently do that discarding N times, so it is left to the human, on the
    same reasoning as the credential in item 2.

23. **A second target, and what the parameterisation actually cost.** Item 16
    claimed the capsule is target-agnostic and said so honestly: *claimed*, with
    one target. panopticon is the second, and the claim's price is now a diff
    rather than an argument. What changed to confine a different repo:

    - `target.nix`, wholesale — a value.
    - one new allowlist file — a value.
    - `inputs.target.url` in `flake.nix` — the literal item 16 says cannot be
      computed.
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
    [probes.md](./probes.md#the-cold-build-on-a-second-target). The one that
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

24. **A `set -u` script must not *be* the login shell, and the pressure figure that
    came out of the wreckage.** Numbered 24 rather than 23 because 23 was spent on
    branch `second-target` before either reached `main`: the numbers are frozen
    across branches, not per branch, so a branch that appends picks the next free
    number globally and neither a merge nor a cherry-pick has to renumber. Item 23
    arrived here by the second route, with the two fixes it documents.

    **The bug.** `capsule-baseline` ran the guest-side runner as `bash -l
    run.sh start STAMP`, and the login shell is load-bearing — `ssh host cmd` gets
    none of `environment.variables`, so without it the build has no proxy and no
    caches (item 6). The runner carries `set -uo pipefail`. A login shell sources
    `/etc/bash_logout` on the way out; the NixOS-generated one opens with a read of
    an unset guard variable, `set -u` was still in force, and an unbound variable
    is fatal — **so the shell's exit status became 1 whatever the script had
    returned**. Proven both ways on the host: a script exiting 64 came back as 64
    under `bash -l -c "bash script"` and as 1 under `bash -l script`. The fix is
    the extra process: the runner is a *child* of the login shell, inherits the
    environment that was the whole point, and takes `set -u` with it when it exits.

    **Nothing in this repo changed to cause it.** The guest rebuild at the end of
    the second-target round brought a nixpkgs whose `bash_logout` has that guard;
    the same code had been green three runs earlier. The general form is worth more
    than the instance: **a script that sets `-u` and is invoked *as* a login or
    interactive shell inherits that shell's own startup and shutdown files**, and
    those are written for a shell without `-u`. `NOSYSBASHLOGOUT=1` does not help —
    under `set -u` the guard read errors before the `||` beside it is reached.

    **What it cost, and what it did not.** Only the attach. `start` detaches the
    run *before* the login shell exits, so both builds ran to green and recorded
    themselves while the host program was dying with exit 1 — the volume's
    `history.tsv` was the truth and the terminal was the lie, which is exactly the
    first property item 19 built this program around. It stayed invisible because
    an exit 1 from a program whose job is to report a build's exit status reads as
    a red build.

    **And the open pressure question closed as a side effect.** Because nothing had
    been stopped, the cgroups still held the whole run: cpu and io `total=` are
    cumulative microseconds, so the figures were readable *after* the fact
    ([probes](./probes.md#pressure-under-two-concurrent-cold-builds)). Two
    concurrent cold builds stalled 0.033% of their wall clock on cpu and 0.002% on
    io — **and io being the smaller by an order of magnitude reverses what the disk
    table had this repo expecting**. The bound is honest rather than tight: the
    window is each cgroup's life, so the figure is an upper bound, and at 0.03% a
    bound is enough to settle it.

    **Two corrections to the instrument, from one 7-second smoke run.** `just load`
    sampled `avg10` only, which is a decaying average that misses anything between
    samples, so it now reads cpu/io `total=` at both ends — same argument as the
    memory peaks, one field over. And its pressure files are checked for
    readability up front, because a kernel with PSI off has the cgroup and not
    them, and an absent pressure file defaulted to zero is an instrument reporting
    *no contention* when what it means is *no measurement*. The run also caught
    what review could not: awk reads a bare `s > 0` inside a `printf` argument list
    as an output redirection, and shellcheck does not look inside an awk program.
    A rendered-and-linted script is not a run.
