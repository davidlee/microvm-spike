# Plan C — more than one capsule at a time

Not a plan yet: the list of things a plan has to settle, and what the answers
cost. Written after the single-target parameterisation (NOTES item 16), which is
the prerequisite — one capsule that names its target in one file.

Scope: *N capsules on one host, same target repo.* Mixed targets is
[deferred, deliberately](#mixed-targets-defer-but-keep-it-possible), and agent
task-assignment is [somebody else's problem](#no-daemon).

## The cost that shapes everything else

Each capsule needs its own tap, its own /30 and its own MAC. Today all three
reach the guest through its *config* — `systemd.network` matches on
`net.mac`, `microvm.interfaces` names the tap — and the guest's store image is
generated per config. So the naive design costs **N store images**, several GiB
each, all rebuilt on every `dev-tools` bump.

Get every per-instance value out of the guest closure and N capsules cost **one
image plus N small runners**, because nix then sees one derivation. MAC and tap
name already live only in the runner's firecracker JSON. The guest's *address*
is the whole problem.

**Measure first:** `nix path-info -Sh .#capsule`. If the image is small this
section is moot and N closures is the right answer for its simplicity.

Three mechanisms, pick one:

1. **N closures.** Simplest and most honest. Pay per image, rebuild all of them
   whenever the tool set moves.
2. **DHCP on the tap**, served by the host's networkd (`DHCPServer=yes`). The
   guest becomes a plain DHCP client, identical in every capsule, and the
   per-instance value moves host-side where it belongs. **Must verify no default
   route can be emitted** (`EmitRouter=no` and whatever else networkd offers) —
   this mechanism touches the one invariant that matters, so it needs a test that
   fails loudly rather than a config that looks right.
3. **Boot-time unit in the guest** reading the address from a kernel param or a
   systemd credential. One closure, but it puts new moving parts guest-side on
   the network path, which is the worst place for them.

Recommendation: cost (1), design for (2).

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
- **The firewall's accept side:** one `networking.firewall.extraInputRules`
  entry with a wildcard iifname and a port set.
  `networking.firewall.interfaces` cannot wildcard, and the allow side cannot be
  installed from this repo at all (NOTES item 7), so this is the one host-config
  line that has to be right once and then never again.
- **The proxy's uid:** `DynamicUser = true` works — it writes only its
  `StateDirectory` — so no per-instance user declaration. The **git daemon's uid
  cannot** be dynamic: the mirror needs stable ownership and `owner` needs group
  access to fetch `capsule/*` back out, which an ephemeral gid breaks. Static and
  enumerated there.

## Addressing

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

**One mirror or N?** Separate mirrors are the isolated answer: a compromised
`receive-pack` in one capsule cannot write another's objects. Cost is a full
clone each. Git alternates share the object store and give most of the disk back,
at the price of a shared read path — acceptable only if the shared store is not
writable by any daemon uid. A single mirror with `refs/heads/capsule/<name>/*`
is cheapest and is shared-fate on exactly the process the uid split was created
to contain.

Whichever way that goes, **the instance name belongs in the ref** — otherwise
you cannot tell whose branch is whose, and `just branches` is a guessing game.

**One gitd or N?** `git daemon --listen` may be repeated, so a single daemon can
serve every tap with a whitelist of every mirror. Cheaper, but it is one process
for all capsules and needs a restart to add one. The proxy is the larger surface
(C parsing guest-authored HTTP), so a defensible middle is **per-capsule
proxies, one gitd**. State it as a choice, not an accident.

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

## Human workflow, once N > 1

- `just status` becomes a table: instance, tap, units, guest reachable, mirror,
  `capsule/*` count.
- `just fetch` and `just branches` aggregate, or take an instance.
- `vm-stop` takes an instance (it already derives the guest address).
- known_hosts gains N entries. Host keys already live per volume, so this is
  noise, not a problem.
- `capsule-push` includes the instance in the ref.

## Order of work

1. Measure the guest image. It decides the addressing mechanism.
2. `capsules.nix` + the index function + wildcard drop and accept rules. Nothing
   runs differently yet; the single capsule becomes instance zero.
3. The VMM half of item 11, with per-instance ceilings. Adding capsules after
   this is a unit start, not a design change.
4. Templated perimeter units, per-capsule proxies, gitd decided above.
5. The `capsule` CLI and the aggregate `just` recipes.
6. Only then: a second target, if it is still wanted.

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
| `host/perimeter-check.nix` | `iifname "${net.tap}"` rule match | wildcard match; **fail-closed, so verify** |
| `host/services.nix` | three units, two uids, one mirror, one state dir | templated units, per-instance state |
| `vm/capsule.nix` | `net.mac` match, `net.guest` address, `net.tap` id | per the addressing mechanism chosen |
| `justfile` | `_net`, `_mirror`, `status`, `fetch`, `ssh`, `admin` | instance argument, or aggregate |
| `perimeter/default.nix` | **nothing** — bind, client, ports, repo, allowlist are all values | unchanged, and keep it that way |

That last row is the point of the existing structure. If a change to support N
capsules wants to edit `perimeter/`, something has gone wrong: the perimeter has
one instance's worth of parameters and should be *instantiated* N times, not
taught about N.

## `capsules.nix` sketch

```nix
# The instances. One list, two consumers: the runners in flake.nix and the
# host-side units through the flake input. Names, not a count — the index is
# position, and every address derives from the index.
{
  instances = ["alpha" "beta"];

  # Instance 0 keeps the addresses the single-capsule design used, so an
  # existing volume, known_hosts entry and mirror all still work.
  index = name: builtins.head (builtins.filter (i: builtins.elemAt instances i == name)
    (builtins.genList (x: x) (builtins.length instances)));
}
```

and the derivation of a net record, which replaces `net.nix`'s flat attrs:

```nix
netOf = i: {
  tap = "vm-cap-${toString i}";          # must stay inside the wildcard drop
  host = "10.99.${toString i}.1";
  guest = "10.99.${toString i}.2";
  prefix = 30;
  mac = "02:00:00:00:99:${lib.fixedWidthNumber 2 i}";
  proxyPort = 3128;                       # same everywhere; the address is what differs
  gitPort = 9418;
};
```

Keep `net.nix` as `netOf 0` for one release if that makes the transition
readable, or delete it and update the two justfile recipes. Do not leave both as
sources of truth.

## Templated units

`host/services.nix` grows from three units to `2N + 1`:

```
capsule-perimeter-guard.service      one, root, verifies the table (not the taps)
capsule-proxy@<name>.service         DynamicUser, per-instance StateDirectory
capsule-gitd@<name>.service          static uid, per-instance mirror
```

Both templates `BindsTo` the single guard and keep
`ConditionPathExists=/sys/class/net/vm-cap-<i>`, which needs `%i` → index. Two
ways to get per-instance values into a template, and this is a real fork:

- **`EnvironmentFile=/etc/capsule/%i.env`**, generated by the module from
  `capsules.nix`. Declarative, greppable, and adding an instance is a rebuild.
- **A generated `capsule-env` helper** the unit sources, computing addresses from
  the index. Adding an instance is then only a systemctl start — but the unit's
  configuration is no longer visible in `systemctl cat`, which is a real
  debuggability loss for a security boundary.

Prefer the EnvironmentFile. This is a perimeter; being able to read what a unit
was told beats saving a rebuild.

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
   justifies the work — test it explicitly with `nc`/`curl` from inside A, and
   remember the forward drop is what makes it true.
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

## Explicit non-goals

Say no to these in the plan, so they don't arrive as scope:

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

1. How big is the guest image? (`nix path-info -Sh .#capsule`) — decides the
   addressing mechanism, and therefore most of the rest.
2. What is the realistic N? 2 and 8 are different designs: at 2, N closures and
   per-instance everything is fine and simpler; at 8, disk and image sharing
   dominate.
3. Host module now or later? Doing it later means building instance machinery
   twice. Doing it now means `~/flakes` grows the instance list.
4. One gitd or N? Decides whether the git uid question is enumerated.
5. Do capsules ever need to be *heterogeneous in size* (a big one and three small
   ones)? If yes, `sizes` moves from `target.nix` to the instance record, and the
   one-image goal survives it — sizes live in the runner, not the closure.
