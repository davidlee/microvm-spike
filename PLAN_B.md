# Plan B — the same perimeter, a different jail

**Partly superseded, and the change is in this document's favour.** Everything
below about a served git mirror, `git daemon`, `refs/heads/capsule/*` and a
second port describes a perimeter that no longer exists: the host initiates git
in both directions now, so the portable half is *only* the proxy, and the git
channel is two ordinary programs that take a URL (NOTES item 18). That makes both
shapes below cheaper — Shape B in particular, where the "guest" is a sandbox on
the same host and the URL is a local path rather than a daemon on loopback. The
egress and jail reasoning is unaffected. Read the git parts as history until this
is rewritten.

The capsule is two things bolted together, and only one of them is portable:

| part | what | portable? |
| --- | --- | --- |
| **perimeter** | allowlist proxy (was: proxy + a served git mirror) | yes — plain shell + tinyproxy |
| **git channel** | host-initiated push and fetch over any git URL | yes — plain shell + git |
| **egress enforcement** | no default route in the guest | no — mechanism is per-platform |
| **jail** | firecracker microVM | no — needs KVM |
| **tool set** | doctrine's `packages.dev-tools` | yes — anywhere nix runs |

Nearly all the *policy* value is in the first row, and it is a shell script.
What varies is the second and third: how you make "the proxy is the only way
out" true, and what contains the agent while it works. Structure the repo so
those are the only legs that change and a port stops being a rewrite —
see [Refactor](#refactor-what-to-factor-out) below.

Two sketches follow: **Shape A**, a Linux VM with the perimeter on the macOS
side, for people who want real containment; and **Shape B**, seatbelt, for the
low-barrier local tier. macOS is not the production target — B is what should
ship as the default there, and A is documented for anyone who wants more.

## Linux without NixOS

Cheapest plan B of all, and worth stating first: nothing about the current
design needs a NixOS *host*. The guest is a closure built by nix; the host
needs nix, `/dev/kvm`, `iproute2`, and one sudo for the tap. What changes:

- **The microvm.nix host module is NixOS-only** (`User=microvm`,
  `/var/lib/microvms`, `microvm-tap-interfaces@`). It's the mechanism NOTES
  open item 11 recommends for the dedicated-uid fix, so elsewhere that becomes
  a hand-written unit — about 20 lines, but yours to maintain.
- **The firewall rule is distro-shaped.** Same rule, different declaration:
  `nft add rule inet filter input iifname vm-capsule tcp dport { 3128, 9418 } accept`
  plus a drop, or the firewalld/ufw equivalent.
- `/dev/kvm` is usually `0660 root:kvm`, so group membership rather than this
  box's `0666`.

Portability cost is host-side plumbing, not confinement.

## Shape A — one Linux VM, perimeter on the macOS host

Don't nest. Firecracker inside a mac VM needs nested virt, which on Apple
silicon means M3-or-later and macOS 15+, and even then you are maintaining two
boundaries to get one jail. Instead let the outer VM *be* the capsule: the
design's shape survives, the boundary just moves up a level.

```
macOS host                        Linux VM (aarch64 NixOS)
  capsule-host                      agent user, no default route
    tinyproxy   :3128  <──────────── HTTPS_PROXY
    git daemon  :9418  <──────────── origin (clone / push capsule/*)
    doctrine.git mirror + update hook
  ssh ────────────────────────────>  sshd
```

### The load-bearing requirement: the VM must have no route out

Everything else is detail. Two ways to get it, neither needing nested virt:

**A1 — host-only networking.** UTM's QEMU backend "Host Only" mode, i.e.
qemu's `-netdev vmnet-host`. No NAT, no default route, a stable host↔VM address
pair — the direct analogue of the `10.99.0.0/30` link, so `capsule-host` binds
the host end and nothing else is reachable. Costs: `vmnet-host` wants root or
the `com.apple.vm.networking` entitlement, which is a real adoption speed bump.

**A2 — restricted user-net (no privilege at all).** Plain qemu:

```
-netdev user,id=n0,restrict=on,\
  guestfwd=tcp:10.0.2.100:3128-cmd:nc 127.0.0.1 3128,\
  guestfwd=tcp:10.0.2.100:9418-cmd:nc 127.0.0.1 9418,\
  hostfwd=tcp:127.0.0.1:2222-:22
```

`restrict=on` isolates the guest completely — no host contact, no packets
routed out — *except* explicitly configured forwards. So the two `guestfwd`
channels are the entire egress surface, enforced by the VMM rather than by a
routing table, and `hostfwd` gets you ssh in on 2222. No root, no vmnet, no
entitlement. This is the better default for a FOSS project; A1 is the tidier
one if you already run UTM.

Either way the guest keeps its half of the current design verbatim: no
resolver, `HTTPS_PROXY` pointed at the proxy address, `origin` on the git
daemon, `agent` user with no sudo, `/work` on a disk.

**Lima and anything vfkit-backed are disqualified** — user-mode NAT only, no
`restrict` knob exposed, so the guest gets a default route and the perimeter
evaporates (see [MACOS.md](./MACOS.md)).

### The guest image

`vm/capsule.nix` minus the `microvm` block, built by nixos-generators to qcow
for `aarch64-linux`. Users, seed service, motd, `/work`, proxy env, git config
all carry over unchanged; the disk replaces the volume, and root stops being
tmpfs (so the RAM-sizing rationale goes away).

### Provisioning, without shipping a VM from your desktop

The one genuinely awkward part, and it has three answers, best first:

1. **Build it in CI, publish as a release artifact.** An arm64 Linux runner
   builds the qcow; users `curl` it. Checksum in the repo. This is the only
   option that is low-barrier for someone who doesn't already have nix.
2. **Build it on the Mac via a one-shot Linux builder.** Correct but recursive
   — the builder is itself a VM — and it drags in nix-darwin, which you already
   flagged as an adoption turnoff.
3. **`nix build` it on any Linux box and copy it over.** Fine for you, not a
   distribution story.

### The perimeter on macOS, without nix-darwin

`capsule-host` needs de-Linux-ing, and that's the whole of it:

- `ss -lnt` → `lsof -nP -iTCP -sTCP:LISTEN`. Only used for the port preflight.
- `ip -brief addr show` → not applicable (A2 has no host interface to check;
  A1 checks the vmnet address).
- `sudo ip tuntap` → gone entirely. No tap on macOS, which is also why
  `capsule-net` disappears in this shape.
- tinyproxy and git: `nix profile install nixpkgs#tinyproxy` (nix alone, no
  nix-darwin) or `brew install tinyproxy`; git-daemon ships with git.
- `pkill -f`, `sed`, `install -m755` are all fine as-is.

The mirror, the `update` hook, and `perimeter/egress-allow.txt` need no changes
at all. That is the point of the split.

### What Shape A costs relative to the real thing

UTM/qemu is a large VMM next to firecracker's five devices, and the guest is a
disk-backed general-purpose NixOS rather than a tmpfs-rooted microVM. Boot is
seconds not milliseconds. The boundary is still hardware virtualisation, just a
fatter implementation of it — and on a Mac the alternative is Shape B, so it
remains the hardened tier.

## Shape B — seatbelt, native, no VM

The low-barrier tier, and the one to ship as the macOS default. The insight
worth building on: **the perimeter needs no sandbox at all.** The proxy and the
git mirror are ordinary local services, and the ref guard — the strongest single
control in this whole design — is a server-side hook that works identically on
macOS with no confinement technology involved. So Shape B reuses the entire
perimeter and asks seatbelt for exactly two things: *don't talk to anything but
the proxy*, and *don't read anything you weren't given*.

```
macOS, one user, no VM

  capsule-host (unchanged)          sandbox-exec -f capsule.sb
    tinyproxy  :3128   <─────────────  the only permitted egress
    git daemon :9418   <─────────────  clone / push capsule/*
    doctrine.git mirror + update hook
                                     workspace:  ~/capsules/<name>  (rw)
                                     home:       ~/capsules/<name>/home
                                     credential: one file, ro
```

### Network: the part that actually fits

SBPL's network primitive is a good match for this design, because the proxy
lives at a literal address:

```scheme
(deny network*)
(allow network-outbound
  (remote ip "localhost:3128")
  (remote ip "localhost:9418"))
```

That is *kernel-enforced* "no egress but the proxy" — structurally the same
guarantee as no-default-route, and categorically stronger than the guest-side
`HTTPS_PROXY` env vars in the current VM, which an agent could simply ignore if
it had a route. Hostname policy stays where it already is, in the tinyproxy
allowlist, since SBPL filters addresses and ports rather than names.

Pleasant side effect: **no DNS is needed inside the sandbox.** The agent dials
`localhost:3128` by literal address and the proxy resolves on its behalf, so
`(deny network*)` costs nothing and no resolver access has to be granted.

### Filesystem: allowlist, not denylist

The temptation is `(allow default)` with targeted denies. Resist it — that
posture cannot enumerate what it's missing, and this is the tier most likely to
be pointed at a real `$HOME`. Write it deny-default:

```scheme
(version 1)
(deny default)
(import "system.sb")                      ; the unavoidable base

(allow file-read*
  (subpath "/nix/store")                  ; the whole toolchain
  (subpath "/usr/lib") (subpath "/System")
  (literal (param "CREDENTIAL")))         ; ONE file, not ~/.claude

(allow file-read* file-write*
  (subpath (param "WORKSPACE"))           ; the clone, $HOME, caches, tmp
  (subpath "/private/var/folders"))       ; macOS TMPDIR

(deny file-read* (subpath (param "HOME_SSH")))   ; belt: absent by omission,
                                                  ; denied again explicitly
(deny mach-lookup)                        ; then allow back what breaks
```

`sandbox-exec -D KEY=value -f capsule.sb` supplies the params, so one profile
serves every capsule instance. Three things worth saying plainly about this
posture:

- **Absence beats denial.** Every deny above is a second belt; the primary
  mechanism is that the path was never allowed. `~/.ssh`, the keychain, the
  real repo, other capsules and the rest of `~/.claude` are simply not in the
  allow list.
- **`(deny mach-lookup)` is where the fiddling lives.** A modern toolchain
  wants a handful of mach services; each one you allow back is a channel out of
  the sandbox to a system daemon. This is the honest weak point of Shape B and
  it needs a written record of which services were allowed and why.
- **Credentials get *better* than in the VM.** One ro-allowed file instead of
  a bootstrap tarball, and no whole-`~/.claude` exposure. The no-shares problem
  that shapes half of NOTES simply doesn't exist here.

### The git tier is unchanged, and it's the best part

Clone from the local mirror over `localhost:9418`, push to `capsule/<name>`,
`update` hook refuses everything else, you fetch from the mirror. Identical
script, identical guarantee, no sandbox involvement. Worth noting because it
means the *coordination* safety property is platform-independent — only
containment-while-working degrades on macOS.

### What Shape B is not

- **Not a kernel boundary.** A macOS LPE, a mach-service escape, or an allowed
  daemon is a way out; the VM shapes don't have that class of hole.
- **Deprecated-but-load-bearing.** `sandbox-exec` has been formally deprecated
  since 10.14 and still ships, because the agent CLIs (Codex's profile being
  the clearest precedent) depend on it. SBPL is undocumented. Apple could
  break it.
- **Fails open, silently.** A misspelled rule doesn't error; it permits. Which
  is why the checklist below is not optional for this shape.

### Verification checklist (Shape B's credibility rests on it)

Run these before believing the profile. Each is one command and each has a
required verdict:

| probe | must |
| --- | --- |
| `curl https://example.com` (not allowlisted) | fail — no route |
| `curl -x localhost:3128 https://example.com` | fail — proxy 403, logged |
| `curl -x localhost:3128 https://api.anthropic.com` | succeed |
| `cat ~/.ssh/id_ed25519` | fail |
| `cat` the one allowed credential file | succeed |
| write outside the workspace | fail |
| `git clone git://localhost:9418/doctrine.git` | succeed |
| `git push origin HEAD:refs/heads/capsule/x` | succeed |
| `git push origin HEAD:refs/heads/edge` | fail — update hook |
| `dig api.anthropic.com` | fail — and irrelevant |

The negative controls matter more than the positive ones: a profile that
allowed everything would pass all four "succeed" rows.

## Refactor: what to factor out

Both shapes consume the same perimeter, so it should stop being inlined in
`flake.nix`:

```
perimeter/            proxy conf template, allowlist, mirror + update hook,
                      port preflight — no tap, no hypervisor, no Linux-isms
vm/                   firecracker guest (Linux + KVM)
image/                nixos-generators qcow guest (Shape A)
seatbelt/             capsule.sb + the launcher (Shape B)
```

Egress enforcement is the leg that differs, and it's worth naming as one
concept with four implementations: routing (no default route), VMM (`restrict=on`),
sandbox rule (SBPL `network-outbound`), and — if you ever want a no-VM,
no-namespace Linux tier — **Landlock ABI ≥ 4, which restricts TCP connect by
port** and is already active on this host (`lsm=landlock,yama,bpf` in
`/proc/cmdline`). Same trick as the SBPL rule, no root, no tap, no netns.

## Recommendation

Ship **B** as the macOS default: one `.sb` file, one shell script, tinyproxy
from nix or brew, no VM, no root, no reboot, and the git tier at full strength.
Document **A** as the hardened tier, with A2 (`restrict=on` user-net) as its
default because it needs no privilege, and CI-built images as the only
provisioning story that scales past your own desktop. Keep firecracker on Linux
as the real thing.
