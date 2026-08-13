# NOTES item 11 — everything host-side runs as you

*State: services half done, VMM half open.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Everything host-side runs as you** — two problems sharing one fix, and the
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

  **That last claim is wrong, and [item 18](./018-git-channel-direction.md) has
  the measurement.** The two uids share one repo by necessity, so `hooks/` and
  `config` in the mirror are writable by the serving uid and `capsule-sync` runs
  git there as you. The route to the tree is your next sync.
- `git-daemon` gets `IPAddressDeny=any` with only the guest allowed, so a
  compromise cannot dial out at all. That also closes the "still reachable from
  the host itself" gap in [item 8](./008-git-daemon-unauthenticated.md) as a
  side effect, at the price of `git://` no longer working from the host — the
  mirror is a path, so fetch it as one.
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
- The cgroup knobs in [item 12](./012-no-resource-ceiling.md) are unit options.
