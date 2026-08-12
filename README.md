# microvm-spike

A **capsule**: a [firecracker](https://github.com/firecracker-microvm/firecracker) [microVM.nix](https://github.com/microvm-nix/microvm.nix) used to confine a coding agent. It holds a
real git clone of one **target** repo — `target.nix`, here `~/dev/doctrine` —
carries that project's tool set, and has exactly enough network to work and no
more. Nothing below is doctrine-specific: `target.nix` is the only file that
names it, and `net.nix` is the only file that holds an address.

Design rationale and known gaps live in [docs/](./docs/index.md). This file is
how to drive it.

## Prerequisites

- KVM (`/dev/kvm` is `crw-rw-rw-` here, so no group membership needed).
- nix-direnv — `direnv allow` gets you the devshell and its commands.
- The host config below. Without it the capsule still runs; it just isn't
  confined.

## Host requirements

Part of the perimeter lives in the host's NixOS config rather than in this
flake, because it has to hold across a reboot and be unreachable from anything
this repo runs. Nothing here is optional.

```nix
# The only port the guest may reach: the proxy. It was two until the git
# channel inverted (NOTES item 18) — the host initiates git now, so there is
# no service on 9418 and nothing to allow.
networking.nftables.enable = true;
networking.firewall.interfaces."vm-capsule".allowedTCPPorts = [3128];

# The tap is an endpoint, never a transit path.
networking.nftables.tables.capsule-forward = {
  family = "inet";
  content = ''
    chain forward {
      type filter hook forward priority filter - 10; policy accept;
      iifname "vm-capsule" drop
      oifname "vm-capsule" drop
    }
  '';
};

# So the host side can prove the drop above is loaded, rather than trusting
# that this file still says so. Read-only, exact arguments, one command.
# Sudoers is last-match-wins: this must come after any broad wheel/ALL rule
# or it does nothing.
security.sudo.extraRules = lib.mkAfter [{
  users = ["david"];
  commands = [{
    command = "/run/current-system/sw/bin/nft list table inet capsule-forward";
    options = ["NOPASSWD"];
  }];
}];
```

**These are verified, not assumed.** `capsule-net up` and `capsule-host` both
call the same check and report one of three states:

| state     | means                                                              |
| --------- | ------------------------------------------------------------------ |
| `dropped` | the table is loaded and both rules are present. Verified.           |
| `latent`  | the drop can't be read, but `net.ipv4.ip_forward` is 0, so nothing forwards yet. Warns. |
| `open`    | forwarding is live and the drop can't be read. **Refuses to start.** |

`capsule-host` keeps checking for the life of the session, because forwarding is
global state it doesn't own — start docker or tailscale mid-session and the
watch tears the proxy down with it. Same if the tap's address disappears. The guest loses egress rather than keeping it past a control that
has gone.

`latent` is the honest verdict for a host with no sudo rule: unverifiable is
not the same as absent, and it is only safe while nothing forwards.
`/run/current-system/sw/bin/nft` rather than a store path because this flake and
the host config have separate nixpkgs pins and sudo matches the command string
literally.

**Interface-scoped ports, not `trustedInterfaces`.** That option accepts
*everything* arriving on the tap, which puts every `0.0.0.0`-bound host service
inside the jail's reach — sshd, whatever's on 8080, the lot. Plain
`allowedTCPPorts` is the opposite mistake: it opens the proxy and the git
daemon on the LAN and the tailnet.

**The forward drop is what makes "no default route" true rather than merely
configured.** The guest has no gateway, but a guest that gets root can add one,
and then the only thing between it and your LAN is whether the host forwards.
`net.ipv4.ip_forward` is global and both docker and tailscale turn it on for
their own reasons, so this cannot be left to inspection — hence the check
above, which refuses to bring the link or the services up in that state. Its own
table rather than `networking.firewall.filterForward`, which switches the
*whole host's* forward policy to drop and would take those same daemons out;
`drop` is terminal in any chain, so a separate table needs no cooperation from
the firewall's.

IPv6 on the tap is handled by `capsule-net` itself (disabled before the link
comes up) — a boot-time sysctl would fire before the interface exists.

The *allow* half of the firewall config is not verified, and doesn't need to be:
omit it and the guest reaches nothing, loudly. Only the silent-failure half
(the forward drop) is checked.

### The proxy under a dedicated uid

`capsule-host` runs tinyproxy as **you** — a bug in its HTTP parser lands on an
account holding `~/.ssh`, `~/.claude` and every repo on the machine. The flake
exports a NixOS module that gives it its own system uid, namespace and cgroup
ceiling instead:

```nix
imports = [inputs.microvm-spike.nixosModules.capsule-perimeter];
services.capsule-perimeter = {
  enable = true;
  owner = "david"; # runs the git channel; reads the egress log by group
};
```

Wired in on Sleipnir: `~/flakes/modules/nixos/capsule.nix`, imported from
`hosts/Sleipnir/config.nix`, with the input taking `inputs.target.follows =
"nixpkgs"` so the graph is fetchable from darwin (the `git+file:` target path
exists on one machine only, and nothing in the host config evaluates the guest).
That shim has to be undone if the VMM ever moves to microvm.nix's host module —
NOTES item 11.

Opt-in, and `capsule-host` stays exactly as it was — it needs no root and no
rebuild, which is what makes it the development path. **Run one or the other,
never both:** they bind the same port, so together you get a port fight. What
the module changes:

| | `capsule-host` | the unit |
| --- | --- | --- |
| runs as | you | `capsule-proxy` |
| proxy log | `.vm/host/tinyproxy.log` | `/var/lib/capsule-proxy/tinyproxy.log`, rotated weekly |
| quarantine | `.vm/host/collect/` | `/var/lib/capsule/collect/` |
| perimeter check | sudo read + supervised watch | `capsule-perimeter-guard.service`, root, no sudo rule needed |
| ceilings | none | `MemoryMax`, `CPUQuota`, `TasksMax`, `IOWeight` |

```
capsule-net up                     # or `vm capsule`; the tap first
systemctl start capsule-proxy      # pulls in the guard first
```

- The module installs `capsule-provision` and `capsule-collect` **wrapped** with
  the units' `CAPSULE_STATE` and `CAPSULE_REPO`, because unwrapped they default
  to `$PWD/.vm/host` — the foreground path's — and would quarantine wherever you
  happened to be standing. The devshell's copies still shadow them inside this
  repo, so each path keeps its own state; both print the path they used, so read
  that line rather than assuming.
- **The guard is a start dependency (`BindsTo`)**, so the services cannot come
  up while the perimeter is unverifiable-and-forwarding, and stop when it goes.
  It does not restart itself: a refusal stays a refusal until you fix the cause
  and start it again. Exercised on the live host — deleting the table and
  setting `ip_forward=1` under a running guest stopped both services within the
  10s poll and took the guest's egress with them. To repeat it, restore with
  `sudo systemctl restart nftables`, put `ip_forward` back, then start the two
  services again; the guard is left `failed` and needs the explicit start.
- The proxy unit is conditional on the tap existing, so start it after
  `capsule-net up`. It is not enabled at boot.
- Adding this repo as an input to the host config means host rebuilds read its
  committed HEAD, same as the `git+file:` gotcha for doctrine.

Still as you: the VMM. NOTES item 11 has the microvm.nix host-module
option and what it does and doesn't fix.

## Quickstart

Three terminals, or three tmux windows:

```
capsule-net up      # once per boot; sudo. creates the tap, owned by you
capsule-host        # foreground: the egress proxy
vm capsule          # foreground: the VM, with its serial console on your tty
```

The guest boots with an **empty** `/work/doctrine`. Give it history from the
host, naming the base commit — any branch, tag or sha in the target repo:

```
capsule-provision edge
```

Then from a fourth terminal: `ssh agent@10.99.0.2`. Inside the guest you are
`agent`, in `/work/<target>`:

```
just test
just web-build
git commit -am 'work'      # locally; there is nothing to push to
```

Back on the host, collect it. That fetches the guest's branches into a
quarantine repo — `--no-tags`, fsck'd, under a packfile ceiling — and prints what
landed with its sha:

```
capsule-collect            # -> .vm/host/collect/capsule.git
just branches              # what is in there
just fetch                 # second step: quarantine -> the repo you work in
```

## Commands

| command             | what                                                       |
| ------------------- | ---------------------------------------------------------- |
| `capsule-net up`    | create the tap + assign `10.99.0.1/30`. Needs sudo.         |
| `capsule-net down`  | remove it. Refuses while a VM runs; `--force` overrides.    |
| `capsule-net verify`| report the perimeter's state without touching the link.      |
| `capsule-host`      | tinyproxy + the perimeter watch. Foreground, unprivileged.   |
| `capsule-provision REF` | push `REF` from the target repo onto the guest's branch. |
| `capsule-collect [NAME]` | fetch the guest's refs into a quarantine repo.          |
| `vm [name]`         | run a VM (`capsule` by default; `hello` is the smoke test). |
| `vm-stop [name]`    | clean shutdown over the firecracker API socket.             |
| `sudo probe-netns`  | evidence: is a netns per capsule sound? No VM, seconds.      |
| `sudo probe-netns-boot` | evidence: does the capsule boot with its tap in one?     |
| `sudo probe-freshness [REF]` | evidence: what a fresh capsule costs, and which axes hold. |

Nothing in the guest: it initiates neither direction, and has no remote.

The two probes are answers kept runnable, not tools — see NOTES "Layout".
`probe-netns-boot` boots the real capsule inside a namespace and shuts it down
again, so it refuses to start beside `capsule-net up` or a running VM; run it
from the repo, since `$PWD/.vm` is where the VM's state lives.

Those are the lifecycle; `just` has everything that needs more than one command
to answer, and does not wrap them. `just check` is the gate (every nix file
parses and is alejandra-clean — no eval, so it can't trigger a VM build).
`just status` puts the VM, the tap, the listener, the perimeter's verdict, the
units and what has been collected on one screen. Then `just verify`,
`just fetch`, `just branches`, `just proxy-log`, `just allowed`, `just ssh`,
`just admin`.
`just --list` for the rest. Addresses come from `net.nix` and target paths from
`target.nix`, never a literal.

## Process lifecycle

`vm` is **not** a daemon: it's firecracker in the foreground with the guest's
serial console on your terminal. Closing the terminal SIGHUPs it, which works
but is a power-cut — the guest gets no shutdown and the volume replays its ext4
journal next boot. Prefer `poweroff` at the console, or `vm-stop` from
elsewhere. `pgrep -af 'microvm@'` is the entire inventory; nothing is
registered anywhere.

**A guest that has shut down may leave the VM running.** Firecracker doesn't
exit on guest poweroff — it halts the vCPU and keeps holding the tap, so the
next `vm capsule` fails with `Device or resource busy`. `vm-stop` handles this
(poweroff, wait, then terminate the VMM); `pgrep -af 'microvm@'` is the check.

**A tap cannot be swapped under a running VM.** `capsule-net down` while the VM
runs destroys the netdev while firecracker keeps the fd; recreating the tap
attaches to nothing and the guest goes silent (`No route to host`). Only a VM
restart recovers it, which is why `down` refuses by default.

## Network

Point-to-point tap, host `10.99.0.1/30` ↔ guest `10.99.0.2/30`. No bridge, no
NAT, **no default route in the guest**, no resolver in the guest. Everything
outbound goes through the host's proxy, which resolves names itself — so an
unlisted host cannot be reached or even resolved.

To let something new out, edit `perimeter/egress-allow.txt` (extended regex,
one hostname per line) and restart `capsule-host`. No rebuild.

`ssh` runs the other way — host to guest — and widens nothing.

## Changing the guest's tools

The tool set comes from the target's own flake — `target.nix`'s `toolsPackage`,
for doctrine `packages.dev-tools` — so both this VM and that devshell take from
one list. To change it:

```
cd ~/dev/doctrine        # edit devToolPkgs in flake.nix
git commit               # git+file: inputs read committed HEAD
cd ~/dev/microvm-spike && nix flake update target
vm-stop capsule && vm capsule
```

Tools the target's list omits because it assumes a host that has them go in
`target.nix`'s `extraTools`, not here.

## Pointing it at a different repo

`target.nix` holds everything target-shaped: name, path, tools package, egress
allowlist file, cache directories, working branch, collect ceiling and the
guest's sizes. Change it and the guest's checkout path, the branch the git
channel provisions onto, the motd and the host side all follow.

One duplication is unavoidable: an input's url must be a literal, so
`inputs.target.url` in `flake.nix` has to name the same repo as `path` in
`target.nix`, and nix will not check that for you. For a one-off, override it
instead: `--override-input target path:/home/you/dev/other`.

Give each target its own allowlist file — half of any such list is that
project's dependency hosts. And keep it here, host-side: an allowlist read out
of the repo being worked on is an allowlist the agent can widen. NOTES item 16
has the reasoning, and why *concurrent* capsules is a much bigger job than a
different one.

## Troubleshooting

| symptom                                        | cause                                                     |
| ---------------------------------------------- | --------------------------------------------------------- |
| `Cannot assign requested address` on start     | tap missing — `capsule-net up`                             |
| firecracker `TapOpen … Operation not permitted` | also tap missing: an absent name makes `TUNSETIFF` *create* one, which the unprivileged VMM may not do. Tap present and still EPERM ⇒ wrong owner (`cat /sys/class/net/vm-capsule/owner` should be your uid) |
| firecracker `Device or resource busy`          | tap exists and is already attached — a VMM outlived its guest; `pgrep -af 'microvm@'`, then `vm-stop` |
| `Address already in use` on start              | orphaned daemon from an earlier run; `capsule-host` names the pid |
| `No route to host` to `10.99.0.2`              | tap was recreated under a running VM, or the VM is down    |
| `refusing — net.ipv4.ip_forward is on`         | the `capsule-forward` table isn't loaded (or isn't readable) while something forwards — see "Host requirements" |
| egress dies mid-session, `Tearing down egress` | same, but it happened after start: docker/tailscale flipped forwarding |
| `FORWARD drop ... cannot be verified`          | the sudo read rule is missing; safe only while `ip_forward` is 0 |
| guest reaches nothing, host is up              | host firewall dropping the tap — see "Host requirements"    |
| a hostname 403s through the proxy              | not in `perimeter/egress-allow.txt`; `.vm/host/tinyproxy.log` names it |
| a download hangs mid-way, no error, no log line | proxy at `MaxClients` — `ss -lnt 'sport = :3128'` shows a non-zero `Recv-Q` (connections queued, never accepted). Cap the client (`bun install --network-concurrency 8`) or raise `MaxClients` in `perimeter/default.nix` |
| the proxy log looks stale while egress works   | the unit path is serving, not `capsule-host` — its log is `/var/lib/capsule-proxy/tinyproxy.log`. `just proxy-log` picks the right one |
| a TUI (claude, etc.) renders but ignores Enter | serial console input quirk — run TUIs over ssh              |
| `modprobe` fails in the guest                  | `security.lockKernelModules` — deliberate; NOTES has the trade |

State lives in `.vm/` (volume images, sockets, proxy logs, quarantine repos) and
is gitignored. Deleting `.vm/capsule/capsule-work.img` resets the guest's
workspace — **including any commits not yet collected**. Deleting
`.vm/host/collect/` discards the collected exhibits, so fetch anything worth
keeping into the real repo first.

**Never loop-mount `capsule-work.img`.** It is guest-written ext4, and `mount`
feeds its metadata to the host kernel. Read it with `fuse2fs`/`debugfs`, or
just ask the guest over ssh. (docs/design.md has the reasoning.)
