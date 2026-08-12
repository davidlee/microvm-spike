# Plan C — implementation detail

[plan-c-multi-capsule.md](./plan-c-multi-capsule.md) is the shape and the
decisions; this is the half an implementing agent needs and nothing else reads.
It is what not to rediscover: exactly which code carries instance identity
today, sketches for the pieces that change, and the traps already paid for once.

## Inventory — where instance identity lives now

Read this before touching anything; it is the whole surface.

| file | what it hardcodes | becomes |
| --- | --- | --- |
| `net.nix` | one tap, one /30, one MAC, one port | **unchanged** — under netns every capsule has that same link; what differs is in `capsules.nix` |
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

## `capsules.nix`

Written — read the file rather than a sketch of it. What it settles, and why
none of it was free:

- **The index is declared, not positional.** Deriving it from list position
  means deleting a name renumbers its neighbours, and an existing volume,
  socket and uplink /30 all silently change hands: `beta` moves from 1 to 0 and
  inherits `alpha`'s state. The one property this is supposed to have —
  instance 0 keeps the single-capsule addressing, so today's state survives —
  is the first casualty. Two capsules declaring one index is an eval-time
  refusal for the same reason.
- **What an index buys is the uplink, and nothing else.** The aggregator has one
  routing table, so each capsule leaves through its own `10.100.<i>.0/30` out of
  a /16 the host routes and NATs whole. A name is on the wire twice
  (`cap-<name>` in the aggregator, `up-<name>` in the capsule), so an
  11-character limit is load-bearing — IFNAMSIZ is 15 and the prefix spends 4.
  Asserted rather than commented.
- **The aggregator is in there too**, as one record and not a per-capsule one:
  it is the only place the capsules' networks meet, which is why the drops
  between them belong to it. Its `linkPattern` comes from the same prefix the
  per-capsule names do, so the wildcard rule cannot drift from the links it is
  meant to match.
- **`net.nix` is untouched.** The pre-netns plan had it becoming `netOf i`, a
  derivation of tap name, /30 and MAC per instance — kept below, because it is
  what the *tap* shape would still need.

That derivation, kept because it is only dead while the shape is netns — it is
what a shared routing domain would need, and
[under netns](./plan-c-multi-capsule.md#netns-per-capsule) every capsule is
`netOf 0`, which is a record and not a function:

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

There is no transition to manage while that stays dead: `net.nix` is `netOf 0`
already, spelled flat, and the justfile recipes that read it keep working.

## Per-instance units, not templates

First, what the namespace itself costs, because an earlier reading of this — "one
oneshot unit and two drop-ins" — is the namespace and not the perimeter.
`probe-netns-egress` built the whole thing by hand and it holds
([results](./probes.md)); this is that run, translated into units:

```
capsule-netns@<name>       root oneshot, RemainAfterExit: ip netns add/del,
                           net.ipv4.ip_forward=0 inside it, before
                           microvm-tap-interfaces@<name>
capsule-egress-ns          root oneshot, one of them: the aggregating namespace
                           every capsule's proxy leaves through — forwarding on,
                           and the two drops below
capsule-egress-link@<name> root oneshot: the veth pair from the capsule's
                           namespace to the aggregator, and the capsule's default
                           route through it
```

plus, host-side and not in any namespace, NAT for the capsule networks and
`ip_forward` on the host — for the *proxy's* egress, with nothing about the
guest's confinement resting on it (which is the inversion
[here](./plan-c-multi-capsule.md#what-it-does-to-the-host-config-dependency)).

Three rules, and each was verified by deleting it and watching the wall fall
over:

```
# in the capsule namespace: the proxy's way out is a local address there, so a
# guest packet to it is INPUT and no forwarding switch touches it
iifname "<tap>" ip daddr != <tap address> drop
# in the aggregator: capsule to capsule. A clean wildcard — it matches links,
# not addresses, so adding a capsule needs no edit
iifname "cap-*" oifname "cap-*" drop
# in the aggregator: and capsule to the host's own networks, with the resolver
# allowed narrowly ahead of it
ip daddr <resolver> udp dport 53 accept
ip saddr <capsule nets> ip daddr { 10/8, 172.16/12, 192.168/16 } drop
```

And one host-config edit, which is not optional and is not a follow-up:
`services.resolved.settings.Resolve.DNSStubListenerExtra` on the
capsule-facing address, plus an input allow for port 53 on that link. Without it
a capsule namespace has no resolver at all — `127.0.0.53` is the *root*
namespace's loopback — and the tempting fix (a public resolver in
`/etc/netns/<ns>/resolv.conf`) silently drops the host's DoT chain.

Then `host/services.nix` grows from three units to `2N + 1`:

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
   ([why](./plan-c-multi-capsule.md#cross-capsule-reach-is-not-what-the-forward-drop-does)). On the tap
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

Most of 1 and 2 already have an answer under netns — `probe-netns-egress` asserts
them of one capsule and a VM-less sibling, controls included, and it runs in a
couple of minutes. So the unit-side verification is *that probe's list against
units*, not a fresh design: if a claim it makes stops holding once systemd owns
the namespace, the units are wrong. Re-run it after the wiring lands, and treat a
divergence as a bug in the units rather than as a new question.

One claim it cannot make and the units must: **DNS through the host's own
chain.** The probe fell back to a public resolver because this host has no stub
on the capsule-facing address, so "the guest's lookups inherit the host's DoT
chain" is currently true of the tap shape and unproven of the netns one. Assert
it explicitly once the `~/flakes` edit is in — a resolver that answers is not
evidence that the right resolver answered.

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
- **Mixed targets.** [Deferred](./plan-c-multi-capsule.md#mixed-targets-defer-but-keep-it-possible), with
  the instance record shaped so it stays possible.

## Open questions to answer before coding

1. ~~Does the netns survive contact with microvm.nix?~~ **Answered from source:
   yes, no patch.** The namespace, the tap and the way in are
   [settled by probe](./plan-c-multi-capsule.md#probed-it-holds); the module's own per-name drop-ins carry
   the namespace ([detail](./plan-c-multi-capsule.md#the-host-module-question-answered-from-source)). What
   remains is not a question but a boot: does firecracker come up with its tap in
   a namespace.
2. How big is the guest image? (`nix path-info -Sh .#capsule`) — prices how much
   the netns machinery is worth versus simply paying for N closures. At 3-4
   capsules on a dev machine, N closures may still be the better trade.
3. ~~Host module now or later?~~ **Now**, and ~~declarative or imperative~~
   **imperative**, decided by a constraint that already existed: declaring
   `microvm.vms.<name>` makes the host config evaluate the guest closure, and
   `~/flakes` is fetchable from darwin only because it does not (the `git+file:`
   target path exists on one machine). So `microvm.host.enable = true` in the
   host config, `sudo microvm -c <name> -f <flake>` once per capsule, and the VMM
   moves under systemd without `~/flakes` ever learning what a capsule contains.
   It also keeps the one-image property literally rather than by luck: N state
   directories, one runner store path, no `nixosConfigurations.<name>` per
   instance.
4. How does a capsule learn its **base commit**, concretely: the human at start
   time, or a field in the instance record? A field is eval-time, which puts it
   back in `~/flakes` for the ranch case; runtime is one more thing to pass. The
   *mechanism* (runtime arg, persisted on the volume) is settled either way.
5. Do capsules ever need to be *heterogeneous in size* (a big one and three small
   ones)? If yes, `sizes` moves from `target.nix` to the instance record, and the
   one-image goal survives it — sizes live in the runner, not the closure.

Answered, no longer open: **what N is** (3-4 on a dev machine; open-ended on a
ranch, which is the constraint rather than a target) and **one gitd or N** (N,
[decided](./plan-c-multi-capsule.md#one-gitd-or-n)).
