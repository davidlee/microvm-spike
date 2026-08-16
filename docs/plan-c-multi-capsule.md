# Plan C — more than one capsule at a time

Not a plan yet: the list of things a plan has to settle, and what the answers
cost. Written after the single-target parameterisation (NOTES item 16), which is
the prerequisite — one capsule that names its target in one file.

Scope: *N capsules on one host, same target repo.* Mixed targets is
[deferred, deliberately](#mixed-targets-defer-but-keep-it-possible), and agent
task-assignment is [somebody else's problem](#no-daemon).

Two scales, both real, and they are not the same design: **3-4 on a dev
machine**, which is about what one human can supervise, and **an agent ranch**,
where N is "it depends". The ranch is mid-to-long term and is not being built
here, but nothing below may design it into implausibility — which is mostly a
constraint on how much of the instance list has to live in the host's own
config.

## Where this stands

Where the *work* is up to is `doctrine backlog list`, and the probe results and
figures this plan reasons from are [probes.md](./probes.md) — neither is
repeated here. What is specific to this plan:

**Settled, with evidence.** The netns shape holds, in the model
(`probe/netns.sh`), in a real boot (`probe/netns-boot.sh`,
[the boot](#the-last-unknown--run-and-it-holds)) and now with the real perimeter
in it (`probe/netns-egress.sh`,
[egress](#egress-under-netns--run-and-it-holds)). All three are kept rather than
thrown away: they are the evidence behind the addressing and isolation decisions
below, and they are what to point at when this shape is proposed somewhere else.
Re-run them after any change to the netns machinery.

**Decided.** Per-capsule proxy. Netns on the host-module path only, with the
foreground path staying at N=1. Units generated per instance rather than
templated. Reasons are with each decision, not here.

**Two of this document's problems no longer exist — NOTES item 18 deleted
them.** The git channel is host-initiated in both directions now, so there is no
git daemon to replicate N times: everything below about per-capsule gitd uids,
per-capsule mirrors, whether one daemon can serve N safely, and the second port
in the host's accept rule is describing a service that is gone. Read those
sections as history. And the **base commit is already a runtime value** — the
guest boots with an empty repository and `capsule-provision <ref>` fills it — so
the only per-instance value still in the guest's closure is the address, which
netns handles. What survives here unchanged is the netns work, the addressing,
the image measurement and `capsules.nix`.

**Nothing in the shape is unverified any more**, so what remains is
[order of work](#order-of-work) from item 4 on.

**Do not re-derive these.** Three claims in earlier drafts of this document were
wrong, and are corrected in place rather than deleted: the forward drop does not
stop cross-capsule reach, one git daemon cannot serve N capsules safely, and a
per-instance kernel cmdline does not buy one guest image. Each is explained
where it does its damage. Likewise two probe methodology traps that cost three
runs — a denial-only network test needs a return path, and a probe borrowing
production addressing tests production — are in
[traps](./plan-c-implementation.md#traps-already-paid-for).

## The cost that shapes everything else

Each capsule needs its own tap and — unless [netns](#netns-per-capsule) holds —
its own /30 and its own MAC. Today all three reach the guest through its
*config*: `systemd.network` matches on `net.mac`, `microvm.interfaces` names the
tap, and the guest's store image is generated per config.

Be exact about what N configs cost, because the obvious reading is wrong in both
directions:

- The **closure** is ~99% shared. A `dev-tools` bump builds the tools once. It
  does not rebuild N toolchains.
- The **store image** is a per-config erofs blob and does not dedupe. So the
  real cost is N × disk, plus N × *pack* time on every bump. Pack time, not
  build time — which is a much smaller number than "rebuild all of them".

Getting every per-instance value out of the guest closure buys **one image plus
N small runners**. MAC and tap name already live only in the runner's
firecracker JSON. Two things are in the closure and have to come out:

- **the guest's address**, and
- ~~**the base commit.**~~ **Out already.** A capsule is usually pinned to one,
  not to "whatever happens to be on the branch", and `capsule-clone` baked the
  remote into the closure and would have baked the ref the same way. Both went
  with the git channel inverting (NOTES item 18): the guest boots with an empty
  repository and the ref is an argument to `capsule-provision`, so nothing about
  it is an eval-time value and nothing has to be persisted on the volume. Only
  the address is left, which makes (4) below cheaper than it looked.

**Measured, and it is not small.** The whole closure is 11.9 GiB but ~99% of it
is shared; the number that costs per instance is the erofs blob it names, which
does not dedupe. Figures and how each was taken are in
[probes.md](./probes.md#figures) — the split that matters here:

| per instance | | shared across instances | |
| --- | --- | --- | --- |
| `microvm-store-disk.erofs` | **3.0 GiB** | guest kernel (`vmlinux`) | 381 MiB |
| the volume, after one build | **7.4 GiB** | initrd | 25 MiB |
| | *(32 GiB sparse, never shrinks)* | the rest of the closure | ~8 GiB |

So N closures is **3.0 GiB of disk and one 3.0 GiB erofs pack per capsule**, on
every tool-set bump — 9 GiB extra at N=4, against 180 GiB free on this host. Not
fatal, and not free either. Since the netns machinery is now verified rather
than speculative, mechanism (4) is cheaper than the thing it replaces on both
axes, and this section stops being a trade-off.

**But the image is the smaller half, which was not obvious until it was
measured.** A capsule that has done no real work carries a few hundred MiB of
volume, and one `just web-build test` took it to **7.4 GiB** — 6.9 GiB of it
`/work/doctrine`, i.e. `target/` and `node_modules`. Firecracker's virtio-block
has no discard (NOTES item 15), so that is a high-water mark: deleting the build
tree in the guest returns nothing to the host. And 7.4 is a floor — cargo's
`target/` keeps growing with every profile, feature set and toolchain change, so
a worked-in capsule trends toward its 32 GiB cap. One image saves 3.0 GiB per
capsule; nothing saves the volume, and the volume is what decides N. See
[disk](#disk-is-the-practical-limit).

Four mechanisms:

1. **N closures.** Simplest and most honest. Pay per image; every tool-set bump
   repacks all of them.
2. **DHCP on the tap**, served by the host's networkd (`DHCPServer=yes`). The
   guest becomes a plain DHCP client, identical in every capsule, and the
   per-instance value moves host-side where it belongs. **Must verify no default
   route can be emitted** (`EmitRouter=no` and whatever else networkd offers) —
   this mechanism touches the one invariant that matters, so it needs a test
   that fails loudly rather than a config that looks right.
3. **Boot-time unit in the guest** reading the address from a kernel param.
   *Does not work as stated.* `microvm.kernelParams` takes `boot.kernelParams`
   into `toplevel` and so into the closure, so a per-instance cmdline is a
   per-instance image — zero sharing, which was the entire point. Getting one
   image this way needs a hand-rolled runner patching the firecracker JSON
   outside the nix config. The same defect kills `systemd.hostname=` as the
   answer to the hostname regression below. A systemd credential has the same
   problem for the same reason.
4. **[A netns per capsule](#netns-per-capsule).** Every capsule uses the same
   /30 and the same MAC, because they are no longer in one routing domain, so
   the guest is bit-identical for free. Probed, and it holds — see below.

Of 1-3, only DHCP preserves a bit-identical guest — and its own cost note below
admits it degenerates into a boot script deriving `.1` from `.2`, i.e. exactly
the guest-side moving part that (3) was rejected for. It does at least fix the
hostname for free (`UseHostname=true`).

**Recommendation: (4), and now with the numbers behind it.** It was probed, it
booted, and identical addressing in every capsule means the question this whole
section asks stops being asked. (1) stays the fallback, but it is a 3.0 GiB
fallback per capsule rather than a free one, and the netns machinery it was
hedging against is one oneshot unit and two drop-ins.

## Netns per capsule

Put each tap in its own network namespace, with that capsule's proxy joined to
it (`NetworkNamespacePath=`), and firecracker launched inside it too. It was the
proxy *and* a git daemon when this was written; there is no daemon now (NOTES
item 18), so the namespace has one service in it and the human's
`capsule-provision`/`capsule-collect` reach the guest the same way `just ssh`
does — over the unix socket, from outside.

It dissolves three of the hardest problems here at once:

- **Addressing.** Every capsule uses the identical /30 and the identical MAC.
  The guest config becomes bit-identical — one image, no DHCP, no boot-time
  address arithmetic, no hostname regression, and the guest's proxy URL can go
  on naming `net.host` at eval time. There is no git remote in the guest to
  worry about. Most of the section above evaporates.
- **Cross-capsule reach.** A cannot address B's tap, because B's tap is not in
  A's namespace. Structural rather than firewall-dependent — and it is the only
  clean answer to the
  [weak host model problem](#cross-capsule-reach-is-not-what-the-forward-drop-does).
- **The forward drop.** `net.ipv4.ip_forward` is **per-netns**. Set it to 0 in
  the capsule's namespace and it is *ours* — docker and tailscale cannot flip
  it. That global sysctl being someone else's is the whole reason the current
  control lives in `~/flakes` and has to be read back out of the running kernel
  (NOTES item 7).

### Probed. It holds.

`probe/netns.sh` — two capsules with identical addressing, no VM, a simulated
guest that already has root and has added the default route. 14 assertions green
on the default run, and stage 2's further three green when it was run. What it
establishes:

- **Identical /30 and identical MAC in two namespaces is fine.** Nothing
  complains, nothing collides. The one-image argument survives its first test.
- **A guest with root and a default route cannot reach the upstream**, and the
  control proves it is the namespace's `ip_forward` doing the work rather than a
  missing route: flip it to 1 and the guest gets straight out, flip it back and
  it stops. That pair is the whole result; the negatives alone would have meant
  nothing without it, which the first two runs demonstrated by passing while
  wrong.
- **Nothing upstream can reach a guest even holding a route to it** — the return
  path exists and the capsule namespace still refuses to carry it. Confirms both
  the isolation and the need for a per-capsule socket proxy to get ssh in.
- **Cross-capsule is blocked** at both the other capsule's upstream link and its
  inside address.
- **Real egress works**: a process in the namespace reaches the internet over
  the veth, while the guest still cannot with every upstream hop forwarding.
- **A tap moves into a namespace and stays bindable**, and **a unix socket gets
  ssh in without privilege** — see
  [plumbing](#plumbing--settled-by-the-same-probe).

Three costs it also found, none fatal, all needing to be designed in rather than
discovered later:

1. **A guest reaches its own capsule's egress address.** `10.100.<i>.2` is a
   local address of the capsule namespace, so a packet arriving on the tap is
   INPUT there, not forward — the same weak-host-model mistake as the host-side
   one, one scope down. Services in the namespace must bind their tap address
   explicitly, and the namespace wants an input drop on its own egress veth.
   Cheap, but silent if missed.
2. **The shared upstream is a capsule-to-capsule path.** Every capsule's proxy
   needs egress, whatever aggregates them forwards, and once it forwards,
   capsule 0 reaches capsule 1's inside address. Not guest-to-guest — this is
   proxy-to-proxy — but it is the netns shape's version of the cross-capsule
   problem. Wants an explicit drop between the upstream's capsule-facing links.
   Note this one *is* a clean wildcard: `iifname "spk-*" oifname "spk-*" drop`
   matches interface pairs, not destination addresses, so it enumerates nothing
   — the property the tap shape wanted for its accept rule and could not have.
3. **DNS does not survive the move unchanged.** Loopback is per-namespace, so
   the host's resolver stub on `127.0.0.53` is not there, and an inherited
   `/etc/resolv.conf` naming it resolves nothing. Confirmed blocked; an explicit
   reachable resolver works. The fix keeps the chain rather than dropping to a
   public resolver, which would silently lose the DoT hop: give resolved an
   extra stub address on the capsule-facing link
   (`services.resolved.settings.Resolve.DNSStubListenerExtra`) and each
   namespace an `/etc/netns/<ns>/resolv.conf` naming it. Two lines, and the
   proxy still does lookups as the host through the host's own chain.

### What it does to the host-config dependency

The largest consequence, and it was not what the probe was for. Today the
perimeter's weakest documented point is that half of it lives in `~/flakes`
(NOTES item 7): the forward drop is in someone else's config, rests on a global
sysctl docker and tailscale both write, and therefore has to be read back out of
the running kernel at run time through a sudoers rule, with a `latent` state for
when it cannot be.

Under netns essentially all of that relocates in-repo:

- The control becomes `ip_forward=0` **inside a namespace this repo creates**.
  Nobody else writes it, so there is nothing to lose a race with.
- The host's *input* chain stops being involved in the guest path at all — the
  services are in the namespace with the guest, so the interface-scoped port
  accept is not needed for them either.
- Stage 2 does need the host to forward and masquerade for the upstream, so host
  config does not vanish. But it changes character completely: it is the
  *proxy's* egress, not the guest's, and nothing about the guest's confinement
  rests on it.

Which also inverts a current refusal: `capsule-net` refuses to start when
`net.ipv4.ip_forward` is on. Under netns the host is *required* to forward, and
the check has to move to the thing that now matters — the capsule namespace's
own forwarding, plus the drop between capsule-facing upstream links.
`host/perimeter-check.nix` gets rewritten rather than adjusted, and the `latent`
state disappears with the sudoers rule.

Cost of collecting that: namespace creation is root-side, so the host module
(item 11) stops being optional for this shape.

### Plumbing — settled by the same probe

- **The tap does not need microvm.nix to cooperate.** A tap created in the root
  namespace moves into a capsule namespace cleanly, is then gone from the root
  namespace entirely (a move, not a clone — nothing in root can delete it out
  from under the guest), and a process inside can bind an address on it. So
  `microvm-tap-interfaces@%i` can stay exactly as it is: create, move, then
  start the VMM. Moving is only unsafe under a VM that is already running, which
  is the existing CLAUDE.md gotcha and unchanged. Creating the tap directly
  inside the namespace also works, if ordering turns out to be easier that way.
- **ssh gets in over a unix socket, and needs no privilege.** `ip netns exec`
  wants CAP_SYS_ADMIN, so a sudo per `just ssh` was never acceptable. The
  filesystem is not namespaced: a relay inside the capsule namespace listening
  on `/run/capsule/<name>/ssh.sock` and connecting to the guest's port 22 is
  reachable from the human's shell, and verified end-to-end here. So `just ssh
  <name>` becomes an `ssh` with a `ProxyCommand` against that socket —
  host→guest only, no host-side port allocation, no guest egress added, and none
  of the cross-namespace fd-passing subtlety that socket activation would have
  needed. It also sidesteps identical guest addresses making a mess of
  known_hosts: the socket path is the identity.

### The host-module question, answered from source

Verified against the pinned microvm.nix — `nixos-modules/host/default.nix` and
`nixos-modules/microvm/interfaces.nix`. **Yes, and it needs no patch.**

- **`microvm@` and `microvm-tap-interfaces@` are ordinary `systemd.services`
  attributes**, so `serviceConfig.NetworkNamespacePath` merges in from the
  host's config like any other option. Better: microvm.nix *already* emits a
  per-name drop-in for each of them (`systemd.services."microvm@${name}" =
  {overrideStrategy = "asDropin"; …}`), so a per-instance namespace uses a
  mechanism the module itself uses in-tree — and there is no `%i` specifier
  expansion to gamble on.
- **`tap-up` is namespace-agnostic**: `ip tuntap add name <id> mode tap user
  <user>`, then `ip link set <id> up`; `tap-down` is the matching `ip link
  delete`. Nothing about addresses, nothing about namespaces. So put the
  namespace on *that* unit as well and the tap is created and destroyed inside
  it — **no tap ever moves**, and stop is symmetric with start. The probe's
  "created directly inside a capsule ns" is therefore the result that matters;
  the move result is the fallback, not the plan. `tap-up`'s idempotency guard
  (`if [ -e /sys/class/net/<id> ]; then ip link delete`) is namespace-local and
  stays correct.
- **`User = microvm` is not an obstacle.** systemd sets namespaces up as PID 1,
  before dropping privilege.
- **One new unit, and that is the whole addition:** `capsule-netns@` — root,
  oneshot, `RemainAfterExit`, `ip netns add` / `ip netns del`, ordered `before`
  `microvm-tap-interfaces@%i`.

Two things the source turned up while checking, both worth knowing before the
first boot rather than after:

- **`ExecStartPost` / `ExecStopPost` on `microvm@` carry the `+` prefix**, which
  by design bypasses the unit's sandboxing — so those run in the *host*
  namespace, not the capsule's. They do nothing unless `registerWithMachined` is
  set, which this config does not, but anything added there later lands silently
  on the wrong side of the boundary.
- **`Restart = "always"` with `RestartSec = 5s`**, and `ExecStop` is
  `microvm-shutdown`, i.e. a `SendCtrlAltDel` this guest cannot receive at all
  (NOTES item 11). Both take a drop-in: `Restart = "no"`, and an `ExecStop` that
  asks the guest to reboot over ssh before handing back to microvm.nix's own
  command, whose `socat` is the wait for the VMM to exit.

### The last unknown — run, and it holds

**Firecracker comes up with its tap inside a namespace.** Measured, not read:
`sudo probe-netns-boot` (`probe/netns-boot.sh`), 9 assertions, green. A
namespace with `ip_forward=0`, `vm-capsule` created inside it, the existing
runner started in there as the human — the VMM comes up, the guest boots to a
login prompt, and its NIC carries traffic on the namespaced tap. The last
unknown in the shape is gone, and nothing about the netns plan changes as a
result.

Answering it did **not** mean the host module. An earlier reading of this
section said the only way was step 5 — declare the VM in `~/flakes` and rebuild.
Wrong, and expensively so: the unknown was firecracker's, not systemd's, so a
namespace, a tap and the runner answered it with no host config at all. The
host-module wiring is now bookkeeping against a known-good result rather than
the experiment itself.

It is the one probe that uses the live tap name, the live /30 and the live
volume, which is otherwise the trap in
[traps](./plan-c-implementation.md#traps-already-paid-for) — the
guest image has `net.nix` baked into it, so a probe on other addressing would
boot a different guest and answer a different question. Hence its refusals: it
will not start beside the devshell tap or a running VM.

What it asserts, both directions:

- the VMM starts, the guest answers ssh *inside* the namespace, and the NIC is
  live on the namespaced tap;
- the tap, the guest and the guest's ssh port are all unreachable from the root
  namespace — the isolation is structural, exactly as `probe/netns.sh` modelled
  it with veths;
- a socat relay on a unix socket carries ssh *and* git across unprivileged. That
  closes NOTES item 18's "git over the netns unix-socket `ProxyCommand`, not
  measured" — `git ls-remote --symref` over the socket, which is the call
  `capsule-provision` itself makes before it pushes. Throughput over the socket
  is still unmeasured; the tap did 100 MiB/s each way.

What it deliberately does not assert is egress: there is no upstream in the
namespace at all, so a denial there would pass for the wrong reason. That half
is [below](#egress-under-netns--run-and-it-holds), and it did **not** wait for
the module — same mistake as the paragraph above, caught before it cost anything
this time.

**One host-side fact it cost a run to find, and the probe now encodes:** a
root-side program cannot borrow your ssh agent. `sudo` strips `SSH_AUTH_SOCK`,
and the key the guest authorises is `~/.ssh/id` — not a filename ssh tries by
default — so ssh offered the wrong key and three checks failed while ping
passed. Every ssh-shaped path here runs as the human for a reason; anything that
ever runs one as root needs an identity handed to it, not inherited. The probe
finds the agent socket itself (a socket is a file, so it crosses into the
namespace unchanged) and refuses before booting if there is none.

Two consequences to handle in the same pass, neither of them unknowns:

- `just status` needs rewriting. `pgrep` still works (the PID namespace is
  untouched) but "is the tap there" stops being answerable from the root
  namespace at all. `ConditionPathExists=/sys/class/net/<tap>` inside a unit is
  evaluated in that unit's namespace, so the units keep working while the
  human's status command does not.
- `vm-stop`'s ssh poweroff moves onto the unix socket, same as `just ssh`.

### Egress under netns — run, and it holds

`sudo probe-netns-egress` (`probe/netns-egress.sh`), 27 assertions, green on the
first run — the results are in [probes.md](./probes.md). It is the same real
capsule in the same real namespace as the boot probe, with the real
`capsule-proxy` joined to it and an aggregating namespace behind that. The
allowlist answers 200 for a host on it and 403 for one off it; guest root
holding the default route it can always add reaches nothing; each denial is
paired with a control that deletes the rule or flips the sysctl and watches the
wall fall over.

**So nothing about the guest's confinement is unverified under netns any more.**
What the order of work has left is assembling this out of systemd units instead
of a probe's `ip` and `nft` calls.

Two corrections it makes to this document, both cheap now and expensive later:

- **The addition is not "one oneshot unit and two drop-ins."** That is the
  namespace. The perimeter also needs a veth per capsule into an aggregating
  namespace, that namespace's own forwarding plus the interface-pair drop and an
  RFC1918 drop, NAT and forwarding on the host, and an input drop on each
  capsule's tap for any destination but the tap address. Every one of them is
  host-side and none is in the guest image, so the one-image claim is untouched
  — but the host module is a module, not a unit.
- **DNS is a `~/flakes` edit, and it is load-bearing.** The three costs above
  called `DNSStubListenerExtra=` a two-line fix; the probe found this host has
  neither the stub address nor the firewall allow that a namespaced client would
  need on it, and fell back to a public resolver to finish the run. A capsule
  resolving outside the host's resolved → stubby → ControlD chain is a quiet
  weakening of exactly what NOTES item 7 built, so it lands with the units
  rather than after them.

### Where netns applies, and where it does not

A convention this repo holds: *the devshell path keeps working with no rebuild
and no root*. Namespaces need root, so netns cannot be on that path.

That is not a conflict, it is the split that already exists between
`capsule-host` and `host/services.nix`. **The foreground path stays the current
tap shape at N=1** — one capsule, no namespace, no privilege beyond the existing
single sudo, which is what makes it usable for development. **Netns exists only
on the host-module path**, which is the real posture and is where N capsules
live anyway. The convention survives verbatim.

Worth being explicit about, because the other reading — netns everywhere, and
`sudo` in the dev loop — silently kills a convention that is there for a reason.

Netns is Linux-shaped, so it belongs at the call site and never in `perimeter/`
— same rule as the nftables check.

## Enumeration — yes, somewhere

`nix run .#<attr>`, NixOS users and non-templated units are all eval-time, so
*something* must list the instances. Two rules make it cheap:

- **One list, several consumers** — `capsules.nix`, the pattern `net.nix` and
  `target.nix` already establish. Consumed by the runners here and by the host
  module through the flake input.
- **Names, not a count.** `["alpha" "beta"]`, not `maxCapsules = 2`. The index
  falls out of position, the addresses fall out of the index, and a name is what
  a human types. An instance record is `{name, index, target}` — see
  [mixed targets](#mixed-targets-defer-but-keep-it-possible) for why `target` is
  in there from day one.

Then keep enumeration out of the three places it hurts:

- **The nftables drop:** one wildcard rule, `iifname "vm-cap*" drop` /
  `oifname "vm-cap*" drop`, covering every current and future tap. Adding a
  capsule then never touches `~/flakes`. Same table, same name, so
  `host/perimeter-check.nix` keeps working — but the check's *rule* match has to
  learn the wildcard form, and that check is fail-closed, so get it wrong and
  nothing starts.
- **The firewall's accept side:** *not* a bare wildcard — see
  [cross-capsule reach](#cross-capsule-reach-is-not-what-the-forward-drop-does).
  The rule has to match the interface **and the destination address together**
  (`iifname . ip daddr @capsule_taps`), or capsule A reaches capsule B's proxy
  and git daemon on B's tap address, granted by the very rule that was supposed
  to be written once. A *named nftables set* is how the rule itself still stays
  fixed: declared once in `~/flakes`, its elements added at run time by whatever
  brings a tap up, so adding a capsule remains not-a-host-rebuild. That costs a
  second sudoers rule (`nft add element`), which is the price of not enumerating
  in someone else's config — and it is the ranch case that makes the price worth
  paying. `networking.firewall.interfaces` can express neither the wildcard nor
  the daddr pairing, so this moves to `extraInputRules` either way, and the
  allow side cannot be installed from this repo at all (NOTES item 7). Moot
  under [netns](#netns-per-capsule), which is a large part of that option's
  appeal.
- **The proxy's uid:** `DynamicUser = true` works — it writes only its
  `StateDirectory` — so no per-instance user declaration. The **git daemon's uid
  cannot** be dynamic: the mirror needs stable ownership and `owner` needs group
  access to fetch `capsule/*` back out, which an ephemeral gid breaks. Static
  and enumerated there.

## Addressing

Only if capsules share a routing domain. Under [netns](#netns-per-capsule) every
capsule gets today's addresses and `net.nix` does not change at all.

`net.nix` becomes a function of the index rather than a record:
`tap = "vm-cap-<name>"`, `host = 10.99.<i>.1`, `guest = 10.99.<i>.2`, prefix 30,
`mac = 02:00:00:00:99:<i>`.

**Ports stay 3128/9418 for every capsule** — uniqueness comes from the bind
address, not from a port allocator. That keeps the guest's proxy URL and remote
identical everywhere (helping the one-closure goal), keeps the firewall rule a
fixed port set, and means no allocation state to persist.

Tap names must stay inside the wildcard the drop matches, which makes the
prefix load-bearing: `vm-cap-*`. Worth a comment at both ends.

## Isolation boundaries — the decisions with teeth

Everything above is plumbing. These are the ones that decide whether N capsules
are N jails or one jail with N doors.

### Cross-capsule reach is not what the forward drop does

The obvious reading — "the forward drop stops A reaching B" — is wrong, and it
is wrong in the direction that matters.

B's tap address is a **host** address. A packet from A to `10.99.1.1` arrives on
`vm-cap-0` and is an INPUT packet, not a forwarded one. Linux is weak-host-model
by default: an address on any interface is accepted from any interface, and the
host answers ARP for it. The forward chain never sees the packet, so the drop is
not involved at any point.

The precondition is guest root — the agent needs to add a route to B's /30 —
which is the same precondition as the default-route attack the drop exists for.
So it is inside the threat model, not beside it.

What actually stops it today is one layer, and only on the unit path:
`capsule-gitd`'s `IPAddressAllow=<guest>/32` and `capsule-proxy`'s
`10.0.0.0/8` deny (`host/services.nix`). Both are per-instance systemd BPF
filters. The foreground `capsule-host` path has nothing equivalent, and never
did.

Two consequences, both already applied above:

- the accept rule must pair iifname with daddr, so the wildcard cannot stand
  alone;
- "adding a capsule never touches `~/flakes`" survives only via a named set
  populated at run time, not via a rule that ignores the destination.

Or the whole problem goes away with [netns](#netns-per-capsule), which is the
one shape where A cannot address B *because there is no path*, rather than
because two BPF filters and a firewall rule are all correct simultaneously.

### One mirror or N?

Separate mirrors are the isolated answer: a compromised `receive-pack` in one
capsule cannot write another's objects. Cost is a full clone each. Git
alternates share the object store and give most of the disk back, at the price
of a shared read path — acceptable only if the shared store is not writable by
any daemon uid. A single mirror with `refs/heads/capsule/<name>/*` is cheapest
and is shared-fate on exactly the process the uid split was created to contain.

Settled by the gitd decision below: per-capsule gitd makes **N mirrors** the
default rather than a choice. Alternates are the optimisation to reach for if
disk bites, subject to the same no-daemon-uid-may-write constraint.

Whichever way that goes, **the instance name belongs in the ref** — otherwise
you cannot tell whose branch is whose, and `just branches` is a guessing game.

### One gitd or N?

**N. Decided.** `git daemon --listen` may be repeated, so one daemon *could*
serve every tap, and it is cheaper. It also fails
[verification item 3](./plan-c-implementation.md#verification-checklist) by
construction: one daemon must allow every guest as a peer, and `--strict-paths`
whitelists paths without binding a path to a source address. A then clones
`git://…/B.git`, reads B's `capsule/*` — and pushes to it, since the update hook
checks the ref namespace and not who asked. Read access alone breaks the claim;
write access makes one agent able to rewrite another's work.

Note the shape of that: the daemon holding every capsule's *work* is the one
that must be per-instance, while the proxy — the larger *parsing* surface, C
over guest-authored HTTP — holds no cross-instance asset and would have been the
defensible one to share. The reverse of the obvious answer.

**Per-capsule both**, in the end: the resource cost is a few hundred MB and two
uids, which is small next to an isolation argument that would otherwise need
re-deriving every time someone notices the proxy is stateless.

**One guard** still suffices, if the drop is wildcarded: it verifies the table,
not the taps, and per-capsule tap existence is already a `ConditionPathExists`.
`BindsTo` from every instance keeps the fail-closed property — one refusal takes
all egress down, which is the correct blast radius for a host-wide control.

## Ceilings stop being optional

N × `target.sizes` is where the host dies — though **not** in the way this
section claimed until the pair probe ran. Memory is a ceiling the guest
converges on, not a charge at boot: two booted capsules cost ~1.5 GiB between
them, so the binding term is what N capsules *touch* at once, which is
workload-dependent and unmeasured ([probes](./probes.md), NOTES item 12). vCPU
shares are a charge from the first busy thread. Item 12 is still open. This
is the strongest argument for doing **the VMM half of item 11 together with this
work**: microvm.nix's host module gives per-instance units, `MemoryMax`,
`CPUQuota`, the uid drop off your account, and root-side tap creation — which
also retires `capsule-net up`'s sudo. Doing N capsules first and the host module
second means building the instance machinery twice.

Note where enumeration lands if you take it: declarative `microvm.vms` puts the
instance list in `~/flakes`; imperative `microvm -c` keeps it here and puts
state in `/var/lib/microvms/<name>`. Both are fine; pick one deliberately, since
it decides whether adding a capsule is a rebuild or a command.

## Disk is the practical limit

One 32 GiB sparse volume per capsule, no discard, high-water mark only (NOTES
item 15), plus a duplicated cargo/bun cache each, and, under mechanism (1) only,
a 3.0 GiB guest image each
([measured](#the-cost-that-shapes-everything-else)).

**One real number, and it moved once the capsule had build config.** One `just
web-build test` used to take the volume from a fresh capsule's few hundred MiB —
nearly all of it empty filesystem — to **7.4 GiB**, 6.9 GiB of that
`/work/doctrine`. That was an *untuned* build: nothing had ever told the capsule
what machine it was, so cargo's defaults applied. With `target.nix`'s
`guestConfig` (`debug = 0`, `incremental = false`) the same workload leaves
**1.1 GiB** in `/work/doctrine` and 144 MiB of crate cache — components summing
to roughly **1.5 GiB** of volume, though the image itself has not been
re-measured at that state. Either way, no discard means it never comes back.
[probes.md](./probes.md#figures) has both ends and how each was taken.

**Read that as a floor, not a figure.** It is n = 1, on one target, and cargo in
particular does not level out after a build: `target/` keeps accreting across
profiles, feature sets, dependency bumps and toolchain changes, and an agent
iterating is the case that grows it fastest. A rust target repo's volume trends
toward its 32 GiB cap rather than toward its first build's size, whichever
number that is. What is target-independent is the
*shape* — the volume dominates the image, and nothing reclaims it — so:

| | mechanism (1), N images | mechanism (4), one image |
| --- | --- | --- |
| per capsule, one build in, tuned | ~1.5 GiB + 3.0 GiB | ~1.5 GiB |
| per capsule, worked in | → 32 GiB + 3.0 GiB | → 32 GiB |

Which makes the honest planning number the **cap**, not the sample: N capsules
is N × 32 GiB of eventual disk, and 3.0 GiB per image is noise beside it. Five
or six is what 180 GiB free actually holds, not the twenty the first measurement
suggested.

Three consequences, none of them CPU: **freshness (REQ-450) is a disk policy**,
because deleting capsules is the only reclaim there is; `target.sizes.volume`
becomes a per-instance knob rather than one constant, since a capsule that only
edits web assets needs nothing like 32 GiB; and cache sharing, if it ever
happens, aims at `/work/doctrine`, which is where the duplication is — a
read-only shared volume plus per-capsule overlay, real machinery, and a shared
*writable* volume across two VMs is corruption, not a shortcut. Note it; don't
build it. **Weaker now than when it was written**: the duplicated term is 1.1
GiB per capsule rather than 6.9, so the config that costs nothing bought most of
what the machinery would have.

## No daemon

The premise needs one correction: nix isn't running anything at run time today.
`vm capsule` is build-then-exec and the only other invocation is `vm-stop`'s
fallback. With prebuilt runners under systemd there is no nix in the loop at
all, so there is no load for a dispatcher to take off it.

Everything a dispatcher would do — start/stop, per-instance state, ordering,
restart policy, ceilings, logs — is systemd's job and microvm.nix's host module
already models it. What is actually wanted is three thin things, none of them
daemons:

- templated units (`capsule-proxy@`, `capsule-gitd@`, one guard),
- a pure `name -> index -> {tap, host, guest, mac}` function, one definition,
- a `capsule` CLI wrapping the systemctl verbs plus a status table — `just
  status` for N.

The real dispatcher question hides underneath: *which capsule gets which task.*
That is a scheduler over agents, not over VMs. It sits on top of `capsule
start/stop/status` and changes nothing here, so keep it separable and out of
this plan.

## Mixed targets: defer, but keep it possible

The mechanism is already there — `repo` and `allowlist` are values (NOTES item
16). What gets expensive:

- A different target means a different tool set means **a different guest
  image**, which is exactly the sharing the whole design above buys.
- Each target needs its own literal flake input, since an input url cannot be
  computed. Mixed targets is N inputs spelled out; `--override-input` no longer
  covers it.
- Per-target allowlists, mirrors and uids follow, and none of them may be shared
  across targets.

Cheap insurance, taken now: the instance record carries its own `target`,
defaulting to the single global one. Mixed-target then becomes a relaxation
rather than a rewrite, and costs nothing today.

## Secrets and home at N

Per-capsule volumes mean per-capsule `$HOME`, so the shared-mutable-state
problem does not arise by construction — N agents already work against one
shared persistent home, and N separate ones is strictly easier. The residual
risk is *drift* between them (settings, MCP config, anything the agent writes to
its own home and then depends on). That is a fix-in-post problem, not a fork in
the road: the floor requirement is a writable home, and every shape here has
one.

Credentials are the part with an actual constraint. `op` (1Password CLI) injects
env vars by talking to a **host** unix socket at bind time, and firecracker has
no shares, so the guest can never reach that socket. The direction is therefore
fixed: `op` runs on the *host*, and the rendered environment goes in — it does
not get fetched out.

Two supported shapes, one interface:

- `op inject` on the host, result written to the capsule's `/work/.env` over ssh
  at start;
- a plain `.env` the human supplies, for hosts with no `op`.

`/work/.env` is already sourced at login and already persists on the volume, so
both land on the same file and nothing new is needed guest-side. At N this
becomes a per-capsule step, which means it belongs in the `capsule` CLI's start
verb rather than in a ritual someone has to remember N times.

**Built, and it cost no mechanism** — the interface is `setup.nix`'s `produce`
fragment, which both shapes already are
([item 22](./ledger/022-secrets-at-start.md), [status](./status.md)).

Two things not to do: secrets on the kernel cmdline (world-readable in the guest
and, per the addressing note above, in the closure), and secrets in the guest's
nix config for the same reason.

Still open and now sharper: NOTES item 2 asks whether OAuth tokens tolerate
concurrent use from two places. At N that stops being hypothetical — it is
literally N simultaneous sessions on one credential. Answer it before the ranch
case, not before the dev-machine case.

## Human workflow, once N > 1

- `just status` becomes a table: instance, tap, units, guest reachable, mirror,
  `capsule/*` count.
- `just fetch` and `just branches` aggregate, or take an instance.
- `vm-stop` takes an instance (it already derives the guest address).
- known_hosts gains N entries. Host keys already live per volume, so this is
  noise, not a problem.
- `capsule-push` includes the instance in the ref.

## Order of work

1. ~~Spike the netns.~~ ~~One boot with a real guest.~~ ~~The perimeter in
   one.~~ **All three done — it holds**: the namespace, the tap and the
   unix-socket way in ([results](#probed-it-holds)), the host module taking the
   namespace without a patch
   ([from source](#the-host-module-question-answered-from-source)), and
   firecracker booting with its tap inside one, 9/9
   ([the boot](#the-last-unknown--run-and-it-holds)), and the real proxy serving
   the real guest in one, 27/27
   ([egress](#egress-under-netns--run-and-it-holds)). Nothing in the shape is
   unverified now, and that is a measured statement rather than a hopeful one.
2. ~~Make the base commit a runtime value.~~ **Done, as a side effect of NOTES
   item 18.** The guest boots with an empty repository and
   `capsule-provision <ref>` puts history in it, so the ref never reaches the
   closure and nothing has to be persisted on the volume for it.
3. ~~Measure the guest image.~~ **Done: 3.0 GiB of erofs per instance**, the
   rest of the 11.9 GiB closure being shared
   ([the numbers](#the-cost-that-shapes-everything-else)). Prices (1) at 3.0 GiB
   and one pack per capsule per bump, which is what makes netns worth its unit.
4. `capsules.nix` + the instance record. Under netns that is a name list and
   little else; without it, the index function, the wildcard drop and the
   daddr-paired accept rule. The single capsule becomes instance zero either
   way.
5. The VMM half of item 11, with per-instance ceilings — and namespace creation
   if (1) held, since that wants root anyway. Adding capsules after this is a
   unit start, not a design change.
6. Per-instance perimeter units: the proxy, generated per capsule. There is no
   gitd to generate — the git channel is host-initiated and per-capsule only in
   which URL it is pointed at (NOTES item 18).
7. ~~The `capsule` CLI~~, ~~the aggregate `just` recipes~~ and ~~per-capsule
   secret injection at start~~ — **all three done** ([status](./status.md)); the
   injection needed a declaration and two changes around it rather than a
   mechanism ([item 22](./ledger/022-secrets-at-start.md)). **The naming half
   was settled ahead of the CLI**, because the four host programs needed it
   before N=2 could work at all: `--capsule <name>`, `CAPSULE_NAME`, else
   `capsules.default`, with the transport derived from the name rather than
   baked into a store path (NOTES item 20). That left the CLI the systemctl
   verbs and the table, both of which it now has — it resolves a name and execs,
   rather than owning the name.
8. ~~Only then: a second target, if it is still wanted.~~ **Done, and green.**
   panopticon on branch `second-target`: `target.nix`, one allowlist file, one
   flake literal, and one export added *in the target*. Outside those, the port
   changed exactly one thing — `programs.nix-ld` in the guest, which no target
   parameterises — so the claim item 16 could only make is now a diff
   ([item 23](./ledger/023-second-target.md)). Cold `just check` in **3 s**
   against doctrine's 109, which is the finding that outlives the port: the
   largest term in time-to-interactive is target-shaped
   ([probes](./probes.md#the-cold-build-on-a-second-target)). What it did *not*
   do is run on the module path, or run beside doctrine — the second is this
   document's much larger job, since a second tool set is a second guest image.

