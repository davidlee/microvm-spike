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

Read this first if you are picking the work up cold.

**Settled, with evidence.** The netns shape holds. `probe/netns.sh` — `sudo
probe-netns`, or `--internet` for the egress stage — models two capsules with
identical addressing and a guest that already has root, in namespaces, with no
VM. 14 assertions, green. It is kept rather than thrown away: it is the evidence
behind the addressing and isolation decisions below, it re-runs in seconds, and
it is what to point at when this shape is proposed somewhere else. Re-run it
after any change to the netns machinery.

**Decided.** Per-capsule proxy *and* git daemon. Netns on the host-module path
only, with the foreground path staying at N=1. The base commit becomes a runtime
value. Units generated per instance rather than templated. Reasons are with each
decision, not here.

**Open, in order.** One real boot with a namespace — the last unverified thing
in the shape — then the guest image measurement, then `capsules.nix`. Full list
under [order of work](#order-of-work).

**Do not re-derive these.** Three claims in earlier drafts of this document were
wrong, and are corrected in place rather than deleted: the forward drop does not
stop cross-capsule reach, one git daemon cannot serve N capsules safely, and a
per-instance kernel cmdline does not buy one guest image. Each is explained where
it does its damage. Likewise two probe methodology traps that cost three runs —
a denial-only network test needs a return path, and a probe borrowing production
addressing tests production — are in [traps](#traps-already-paid-for).

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
- **the base commit.** A capsule is usually pinned to one, not to "whatever
  happens to be on the branch". Today `capsule-clone` bakes the remote into the
  guest's closure and would bake the ref the same way — so if instances differ
  here, identicality is gone whatever the addressing does. The fix is
  independent of everything else and cheap: make the ref a **runtime** argument
  to `capsule-clone`, persisted on the volume, never an eval-time value. Do it
  regardless of which mechanism below wins.

**Measure first:** `nix path-info -Sh .#capsule`. If the image is small this
section is moot and N closures is the right answer for its simplicity.

Four mechanisms:

1. **N closures.** Simplest and most honest. Pay per image; every tool-set bump
   repacks all of them.
2. **DHCP on the tap**, served by the host's networkd (`DHCPServer=yes`). The
   guest becomes a plain DHCP client, identical in every capsule, and the
   per-instance value moves host-side where it belongs. **Must verify no default
   route can be emitted** (`EmitRouter=no` and whatever else networkd offers) —
   this mechanism touches the one invariant that matters, so it needs a test that
   fails loudly rather than a config that looks right.
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

**Recommendation: (4).** It was probed and it holds; identical addressing in
every capsule means the question this whole section asks stops being asked. Keep
(1) as the fallback if the netns machinery turns out to cost more than the image
does — which is what step 3 of the work order measures.

## Netns per capsule

Put each tap in its own network namespace, with that capsule's proxy and gitd
joined to it (`NetworkNamespacePath=`), and firecracker launched inside it too.

It dissolves three of the hardest problems here at once:

- **Addressing.** Every capsule uses the identical /30 and the identical MAC.
  The guest config becomes bit-identical — one image, no DHCP, no boot-time
  address arithmetic, no hostname regression, and the guest's proxy URL and git
  remote can go on naming `net.host` at eval time. Most of the section above
  evaporates.
- **Cross-capsule reach.** A cannot address B's tap, because B's tap is not in
  A's namespace. Structural rather than firewall-dependent — and it is the only
  clean answer to the [weak host model
  problem](#cross-capsule-reach-is-not-what-the-forward-drop-does).
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
  ssh in without privilege** — see [plumbing](#plumbing--settled-by-the-same-probe).

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
   extra stub address on the capsule-facing link (`DNSStubListenerExtra=` via
   `services.resolved.extraConfig`) and each namespace an
   `/etc/netns/<ns>/resolv.conf` naming it. Two lines, and the proxy still does
   lookups as the host through the host's own chain.

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
  `microvm-tap-interfaces@%i` can stay exactly as it is: create, move, then start
  the VMM. Moving is only unsafe under a VM that is already running, which is the
  existing CLAUDE.md gotcha and unchanged. Creating the tap directly inside the
  namespace also works, if ordering turns out to be easier that way.
- **ssh gets in over a unix socket, and needs no privilege.** `ip netns exec`
  wants CAP_SYS_ADMIN, so a sudo per `just ssh` was never acceptable. The
  filesystem is not namespaced: a relay inside the capsule namespace listening on
  `/run/capsule/<name>/ssh.sock` and connecting to the guest's port 22 is
  reachable from the human's shell, and verified end-to-end here. So
  `just ssh <name>` becomes an `ssh` with a `ProxyCommand` against that socket —
  host→guest only, no host-side port allocation, no guest egress added, and none
  of the cross-namespace fd-passing subtlety that socket activation would have
  needed. It also sidesteps identical guest addresses making a mess of
  known_hosts: the socket path is the identity.

### The host-module question, answered from source

Verified against the pinned microvm.nix — `nixos-modules/host/default.nix` and
`nixos-modules/microvm/interfaces.nix`. **Yes, and it needs no patch.**

- **`microvm@` and `microvm-tap-interfaces@` are ordinary `systemd.services`
  attributes**, so `serviceConfig.NetworkNamespacePath` merges in from the host's
  config like any other option. Better: microvm.nix *already* emits a per-name
  drop-in for each of them (`systemd.services."microvm@${name}" =
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
  `microvm-shutdown`, i.e. the `SendCtrlAltDel` this guest ignores (NOTES item
  11). Both already need a drop-in; the namespace work is the natural time to
  write it.

### The one thing still unverified

**That firecracker comes up with its tap inside a namespace.** Everything says
it will — it opens `/dev/net/tun` and `TUNSETIFF`s by interface name, both
resolved in its own namespace — but nothing here has run it, and reading source
is not running code. That is one boot, and it is the last unknown in the shape.

Two consequences to handle in the same pass, neither of them unknowns:

- `just status` needs rewriting. `pgrep` still works (the PID namespace is
  untouched) but "is the tap there" stops being answerable from the root
  namespace at all. `ConditionPathExists=/sys/class/net/<tap>` inside a unit is
  evaluated in that unit's namespace, so the units keep working while the human's
  status command does not.
- `vm-stop`'s ssh poweroff moves onto the unix socket, same as `just ssh`.

### Where netns applies, and where it does not

A convention this repo holds: *the devshell path keeps working with no rebuild
and no root*. Namespaces need root, so netns cannot be on that path.

That is not a conflict, it is the split that already exists between
`capsule-host` and `host/services.nix`. **The foreground path stays the current
tap shape at N=1** — one capsule, no namespace, no privilege beyond the existing
single sudo, which is what makes it usable for development. **Netns exists only
on the host-module path**, which is the real posture and is where N capsules live
anyway. The convention survives verbatim.

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
- **The firewall's accept side:** *not* a bare wildcard — see [cross-capsule
  reach](#cross-capsule-reach-is-not-what-the-forward-drop-does). The rule has
  to match the interface **and the destination address together**
  (`iifname . ip daddr @capsule_taps`), or capsule A reaches capsule B's proxy
  and git daemon on B's tap address, granted by the very rule that was supposed
  to be written once. A *named nftables set* is how the rule itself still stays
  fixed: declared once in `~/flakes`, its elements added at run time by whatever
  brings a tap up, so adding a capsule remains not-a-host-rebuild. That costs a
  second sudoers rule (`nft add element`), which is the price of not enumerating
  in someone else's config — and it is the ranch case that makes the price worth
  paying. `networking.firewall.interfaces` can express neither the wildcard nor
  the daddr pairing, so this moves to `extraInputRules` either way, and the allow
  side cannot be installed from this repo at all (NOTES item 7).
  Moot under [netns](#netns-per-capsule), which is a large part of that option's
  appeal.
- **The proxy's uid:** `DynamicUser = true` works — it writes only its
  `StateDirectory` — so no per-instance user declaration. The **git daemon's uid
  cannot** be dynamic: the mirror needs stable ownership and `owner` needs group
  access to fetch `capsule/*` back out, which an ephemeral gid breaks. Static and
  enumerated there.

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
serve every tap, and it is cheaper. It also fails [verification item
3](#verification-checklist) by construction: one daemon must allow every guest
as a peer, and `--strict-paths` whitelists paths without binding a path to a
source address. A then clones `git://…/B.git`, reads B's `capsule/*` — and
pushes to it, since the update hook checks the ref namespace and not who asked.
Read access alone breaks the claim; write access makes one agent able to rewrite
another's work.

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

N × 8 vCPU / 16 GiB is where the host dies, and NOTES item 12 is still open. This
is the strongest argument for doing **the VMM half of item 11 together with this
work**: microvm.nix's host module gives per-instance units, `MemoryMax`,
`CPUQuota`, the uid drop off your account, and root-side tap creation — which
also retires `capsule-net up`'s sudo. Doing N capsules first and the host module
second means building the instance machinery twice.

Note where enumeration lands if you take it: declarative `microvm.vms` puts the
instance list in `~/flakes`; imperative `microvm -c` keeps it here and puts state
in `/var/lib/microvms/<name>`. Both are fine; pick one deliberately, since it
decides whether adding a capsule is a rebuild or a command.

## Disk is the practical limit

One 32 GiB sparse volume per capsule, no discard, high-water mark only (NOTES
item 15), plus a duplicated cargo/bun cache each. Sharing caches across VMs means
a read-only shared volume plus a per-capsule overlay — real machinery, and a
shared *writable* volume across two VMs is corruption, not a shortcut. Note it;
don't build it. In practice this, not CPU, sets the useful N.

## No daemon

The premise needs one correction: nix isn't running anything at run time today.
`vm capsule` is build-then-exec and the only other invocation is `vm-stop`'s
fallback. With prebuilt runners under systemd there is no nix in the loop at all,
so there is no load for a dispatcher to take off it.

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
start/stop/status` and changes nothing here, so keep it separable and out of this
plan.

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
the road: the floor requirement is a writable home, and every shape here has one.

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

1. ~~Spike the netns.~~ **Done — it holds**, along with the tap and the
   unix-socket way in ([results](#probed-it-holds)), and the host module takes
   the namespace without a patch
   ([from source](#the-host-module-question-answered-from-source)). What is left
   is one boot with a real guest, which means step 5 in practice — there is no
   cheaper way to answer it.
2. **Make the base commit a runtime value** — `capsule-clone <ref>`, persisted on
   the volume. Independent of everything else, needed either way, worth doing
   now.
3. Measure the guest image. It prices how much (1) is worth.
4. `capsules.nix` + the instance record. Under netns that is a name list and
   little else; without it, the index function, the wildcard drop and the
   daddr-paired accept rule. The single capsule becomes instance zero either way.
5. The VMM half of item 11, with per-instance ceilings — and namespace creation
   if (1) held, since that wants root anyway. Adding capsules after this is a
   unit start, not a design change.
6. Per-instance perimeter units: proxy *and* gitd, generated per capsule.
7. The `capsule` CLI, per-capsule secret injection at start, and the aggregate
   `just` recipes.
8. Only then: a second target, if it is still wanted.

---

# Implementation detail

Everything above is the shape. Below is what the implementing agent needs to not
rediscover: exactly which code carries instance identity today, sketches for the
pieces that change, and the traps already paid for once.

## Inventory — where instance identity lives now

Read this before touching anything; it is the whole surface.

| file | what it hardcodes | becomes |
| --- | --- | --- |
| `net.nix` | one tap, one /30, one MAC, two ports | a function of the instance index |
| `flake.nix` `mkVm` | `specialArgs = {inputs, net, target}` | plus the instance record |
| `flake.nix` `vms` | `hello`, `capsule` | `capsule-<name>` per instance, `hello` unchanged |
| `flake.nix` `perimeter` | one import, one bind/client | one per instance, or one taking the set |
| `flake.nix` `capsule-net` | `tap=${net.tap}`, one address | takes an instance, or is retired by the host module |
| `flake.nix` `vm` | `nix run "$root#$name"`, cwd `.vm/$name` | unchanged if instances are attr names |
| `flake.nix` `vm-stop` | `root@${net.guest}`, `name = capsule` | instance's guest address |
| `host/perimeter-check.nix` | `iifname "${net.tap}"` rule match | wildcard match; **fail-closed, so verify**. Or a per-netns read, if the drop moves there |
| `host/services.nix` | three units, two uids, one mirror, one state dir | 2N+1 generated units, per-instance state |
| `vm/capsule.nix` | `net.mac` match, `net.guest` address, `net.tap` id | per the addressing mechanism chosen |
| `vm/capsule.nix` `capsule-clone` | the remote, at eval time — and would bake the ref the same way | the ref becomes a runtime argument, or one image is impossible |
| `justfile` | `_net`, `_mirror`, `status`, `fetch`, `ssh`, `admin` | instance argument, or aggregate |
| `perimeter/default.nix` | **nothing** — bind, client, ports, repo, allowlist are all values | unchanged, and keep it that way |

That last row is the point of the existing structure. If a change to support N
capsules wants to edit `perimeter/`, something has gone wrong: the perimeter has
one instance's worth of parameters and should be *instantiated* N times, not
taught about N.

## `capsules.nix` sketch

```nix
# The instances. One list, two consumers: the runners in flake.nix and the
# host-side units through the flake input.
#
# Names, not a count — but the index is *declared*, not positional. Deriving it
# from list position means deleting a name renumbers its neighbours, and an
# existing volume, mirror, tap and known_hosts entry all silently change hands:
# `beta` moves from 1 to 0 and inherits `alpha`'s state. The one property this
# is supposed to have — instance 0 keeps the single-capsule addresses, so
# today's state survives — is the first casualty.
{
  instances = {
    alpha = {index = 0;}; # 0 keeps the addresses the single-capsule design used
    beta = {index = 1;};
  };
}
```

and the derivation of a net record, which replaces `net.nix`'s flat attrs — only
needed if capsules share a routing domain. Under [netns](#netns-per-capsule)
every capsule is `netOf 0` and this is a record again, not a function:

```nix
netOf = i: {
  # IFNAMSIZ is 15 and "vm-cap-" spends 7 of it, so an instance *name* longer
  # than 8 chars fails at `ip tuntap add`. Indexed for that reason; if names are
  # wanted here, the length limit is load-bearing and belongs in an assert.
  tap = "vm-cap-${toString i}"; # must stay inside the wildcard drop
  host = "10.99.${toString i}.1";
  guest = "10.99.${toString i}.2";
  prefix = 30;
  # Hex, so it reads as a MAC rather than as a decimal that happens to look like
  # one: `netOf 10` must be :0a, not :10. (fixedWidthNumber is decimal and was
  # wrong here — injective for i < 100, so it would have worked and confused.)
  mac = "02:00:00:00:99:${lib.fixedWidthString 2 "0" (lib.toHexString i)}";
  proxyPort = 3128; # same everywhere; the address is what differs
  gitPort = 9418;
};
```

Keep `net.nix` as `netOf 0` for one release if that makes the transition
readable, or delete it and update the two justfile recipes. Do not leave both as
sources of truth.

## Per-instance units, not templates

`host/services.nix` grows from three units to `2N + 1`:

```
capsule-perimeter-guard.service      one, root, verifies the table (not the taps)
capsule-proxy-<name>.service         DynamicUser, per-instance StateDirectory
capsule-gitd-<name>.service          static uid, per-instance mirror
```

`@`-templates plus `EnvironmentFile=/etc/capsule/%i.env` was the obvious shape,
and it does not work. An environment file supplies the *program's* environment.
Every per-instance value here is a **unit directive** — `IPAddressAllow`,
`IPAddressDeny`, `ConditionPathExists`, `BindReadOnlyPaths`, `StateDirectory`,
`NetworkNamespacePath`, `MemoryMax` — and none of those read env vars. The
settings a template cannot carry are precisely the security-relevant ones, which
is disqualifying rather than inconvenient.

So generate N concrete units from the instance list with `listToAttrs`. It is
what `host/services.nix` already does for one, every unit's configuration stays
visible in `systemctl cat` — which matters for a boundary — and adding a capsule
is a rebuild. That last part is a real cost in the ranch case; take it anyway
until something forces otherwise, because the alternative hides the perimeter's
configuration inside a generated helper.

Both `BindsTo` the single guard and keep `ConditionPathExists` on their own tap,
spelled out rather than derived from `%i`.

Per-instance paths, all derived, none new in kind:

```
/var/lib/capsule/<name>/<target>.git       mirror        (group capsule-git, setgid)
/var/lib/capsule-proxy/<name>/             conf, log, pid
```

`logrotate` gains a wildcard glob rather than N stanzas. Its `su` directive names
the owning uid, so a `DynamicUser` proxy changes what that has to say — check
before assuming rotation still works.

## What the guest looks like under each addressing option

Option 1 (N closures) is a no-op on `vm/capsule.nix` beyond threading the
instance record instead of `net`.

Option 2 (DHCP) removes the two things that make guests differ:

```nix
systemd.network.networks."10-capsule" = {
  matchConfig.Type = "ether";        # was: MACAddress = net.mac
  networkConfig.DHCP = "ipv4";       # was: static address
  dhcpV4Config.UseRoutes = false;    # belt: the host must not send one either
  linkConfig.RequiredForOnline = "carrier";
};
```

and the guest's proxy URL and git remote must then stop naming `net.host`, which
they currently do at eval time. Either the host end of every /30 is reachable at
a name the guest resolves (it has no resolver — so no), or the guest learns it
from DHCP (option 121 / a route-less gateway field, ugly), or **the /30 is chosen
so the host end is derivable from the guest's own address** — `10.99.i.2` implies
`10.99.i.1` with a two-line script at boot. That last one is the honest answer,
and it is also the point where option 2 stops being obviously cheaper than option
1. Cost it properly before committing.

`hostname` is in the closure too (`networking.hostName = name` in `mkVm`), so
one-image sharing means the hostname is generic and the *prompt* stops telling
you which capsule you are in. That is a usability regression worth pricing:
`systemd.hostname=` on the kernel cmdline may cover it — verify, don't assume.

## Verification checklist

The single-capsule claims all have to hold *per instance*, plus three that only
exist once N > 1:

1. Per instance: no default route in the guest; egress only via that instance's
   proxy; allowlist denial logged; push to `capsule/*` accepted, anything else
   refused; `git://` unreachable from the host.
2. **Cross-capsule:** from capsule A, the guest cannot reach B's proxy port, B's
   git daemon, or B's tap address at all. This is the new claim and the one that
   justifies the work. Test it with `nc`/`curl` from inside A **after adding the
   route by hand as guest root** — without the route it passes for the wrong
   reason and proves nothing. And know what is being tested: the forward drop is
   *not* involved
   ([why](#cross-capsule-reach-is-not-what-the-forward-drop-does)). On the tap
   shape this exercises the units' `IPAddressAllow`/`Deny` plus the
   daddr-paired accept rule; on the netns shape it exercises the namespace.
3. **Cross-capsule git:** A cannot read or write B's mirror. If you took the
   shared-alternates option, prove the shared store is not writable by either
   daemon uid.
4. **Fail-closed still fails closed:** delete the wildcard table, set
   `ip_forward=1`, and confirm *every* instance's services stop, not just the
   first. One guard, `BindsTo` from 2N units — a `BindsTo` that only tears down
   some of them is worse than no guard, because the survivors look healthy.
5. The guard's rule match understands the wildcard. Test by renaming a tap
   outside the pattern and confirming the check refuses rather than passing.

## Traps already paid for

All of these are in CLAUDE.md; they cost time once and will cost it again at N.

- **A tap cannot be swapped under a running VM**, and firecracker does not exit
  when the guest powers off. At N, `capsule-net down` must refuse per instance,
  and a stale VMM holding tap 2 makes capsule 2 specifically unstartable with
  EBUSY. `pgrep -af 'microvm@'` is the inventory; make the status table read it
  per instance.
- **`wait -n` must name its pids** — the foreground path silently outlived both
  its dead children until this was fixed. N foreground compositions is N chances
  to hit it.
- **The unit path is invisible to connect probes.** `capsule-proxy` denies
  RFC1918 and `capsule-gitd` allows only its guest, so the foreground path's port
  check reads every port as free. Hence the `systemctl is-active` refusal in the
  injected preflight — which at N must check *that instance's* units, not any.
- **Group membership needs a fresh login.** Two groups already; per-instance
  `capsule-git-<n>` uids would mean N. That alone is an argument for one gitd
  uid, or for a single `capsule-git` group holding the human.
- **Untracked files are invisible to a flake build.** `git add` new files before
  building, in this repo and in `~/flakes`.
- **`environment.variables` is login-shell scope** in the guest; anything
  daemon-side needs its own `Environment`.
- **A negative network test needs a return path, or it passes for the wrong
  reason.** The netns probe's first two runs were green on every "the guest
  cannot reach X" assertion while proving nothing: with no route back to the
  simulated guest, those pings could not have succeeded whatever the namespace
  did. Only the deliberately-inverted control (turn the switch on, watch the
  wall fall over) caught it. Any test of this perimeter that only asserts
  denials is untrustworthy; pair each with the same test against the control
  disabled.
- **A probe that borrows the production addressing tests production.** The same
  run reused `10.99.0.0/30` while a capsule was live, so the root namespace held
  a connected route to the real guest and replies to the simulated one went to
  the running VM. Two results came back wrong in opposite directions. The probe
  now uses `10.98.0.0/30` and refuses to start on an overlapping route.

## Explicit non-goals

Say no to these in the plan, so they don't arrive as scope:

- **N agents in one capsule.** The cheap alternative to this entire plan — one
  VM, N worktrees, N agents — is vetoed. Interleaved commits, and a worktree
  provides no isolation worth the name. Agent-vs-agent isolation may be outside
  the threat model, but the *workflow* wants one checkout per agent with its own
  history, and that is reason enough. Recorded so it is not re-proposed as a
  saving.
- **A scheduler.** Which capsule gets which task is a layer above `capsule
  start/stop/status`.
- **A bridge.** Point-to-point taps are what make the per-instance drop
  meaningful; one subnet for all capsules would let them reach each other by
  construction.
- **Shared writable caches.** Two VMs, one writable volume, is corruption.
- **Per-capsule allowlists while single-target.** One target, one allowlist; a
  per-instance allowlist is a per-instance *policy*, which is only coherent once
  targets differ.
- **Mixed targets.** [Deferred](#mixed-targets-defer-but-keep-it-possible), with
  the instance record shaped so it stays possible.

## Open questions to answer before coding

1. ~~Does the netns survive contact with microvm.nix?~~ **Answered from source:
   yes, no patch.** The namespace, the tap and the way in are
   [settled by probe](#probed-it-holds); the module's own per-name drop-ins carry
   the namespace ([detail](#the-host-module-question-answered-from-source)). What
   remains is not a question but a boot: does firecracker come up with its tap in
   a namespace.
2. How big is the guest image? (`nix path-info -Sh .#capsule`) — prices how much
   the netns machinery is worth versus simply paying for N closures. At 3-4
   capsules on a dev machine, N closures may still be the better trade.
3. ~~Host module now or later?~~ **Now.** Namespace creation is root-side, so
   the netns shape needs it. The remaining question is only whether `~/flakes`
   grows the instance list (declarative `microvm.vms`) or state stays here
   (imperative `microvm -c`).
4. How does a capsule learn its **base commit**, concretely: the human at start
   time, or a field in the instance record? A field is eval-time, which puts it
   back in `~/flakes` for the ranch case; runtime is one more thing to pass. The
   *mechanism* (runtime arg, persisted on the volume) is settled either way.
5. Do capsules ever need to be *heterogeneous in size* (a big one and three small
   ones)? If yes, `sizes` moves from `target.nix` to the instance record, and the
   one-image goal survives it — sizes live in the runner, not the closure.

Answered, no longer open: **what N is** (3-4 on a dev machine; open-ended on a
ranch, which is the constraint rather than a target) and **one gitd or N** (N,
[decided](#one-gitd-or-n)).
