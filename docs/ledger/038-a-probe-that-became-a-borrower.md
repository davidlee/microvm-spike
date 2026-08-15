# NOTES item 38 — a probe that became a borrower without changing

*State: **fixed, enforced and run.** `probe/netns-egress.sh` shared its
namespace, both link names, both addresses and its whole /16 with the live
aggregator, and `probe/netns.sh` shared the addressing in the **root** namespace
— neither by borrowing anything, but because `capsules.nix` was written from
those probes' map afterwards. netns-egress's teardown deletes `eg-rt` by name,
which on a module-path host is the fleet's uplink. The fabric is now
`probe/harness.sh`'s, on names and addressing that `flake.nix`'s `probeFabric`
**refuses at eval** to share with `capsules.nix` — watched going red on six
mutations, across all three probes that build one. **Both VM probes have since
run green on it**, and doing so turned up a third instance one level down: an
assertion written against a ref convention that moved (below). The fix also
costs the probes the host's DoT resolver until `~/flakes` names the new
address.*

One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What happened

`sudo probe-netns-egress` on this host refuses to start:

```
probe-netns-egress: namespace cap-egress is left over — 'ip netns del cap-egress'.
```

It is not left over. `capsules.nix` declares `cap-egress` as *the* aggregator
every capsule's proxy leaves through and `host/netns.nix` creates it, so on a
module-path host that message names a production namespace and instructs you to
delete it. Someone did. The guard saw `table capsule-egress is not loaded in
cap-egress`, logged `the perimeter changed under us. Tearing down egress.` and
exited 1, while `capsule-egress-ns.service` still read `active (exited)` —
a oneshot with `RemainAfterExit` cannot notice its own namespace being deleted.

That was recorded as a name collision. It is not.

## What it actually was

The probe shared **everything**, and the refusal above is the third of three
accidents that stopped it mattering:

| the probe added | the live fabric | same? |
| --- | --- | --- |
| `cap-egress` (ns) | `capsules.egress.ns` | yes |
| `eg-up` / `eg-rt` (veth pair) | `egress.dev` / `egress.peer` | yes |
| `10.101.0.2` / `10.101.0.1` | `egress.addr` / `egress.peerAddr` | yes |
| `10.100.0.0/16` (root route) | `capsules.uplinkNet` | yes |
| `10.100.<i>.{1,2}` per capsule | each instance's `uplink` | yes |

So the cleanup trap's `ip link del eg-rt` deletes the live aggregator's uplink,
taking `eg-up` inside `cap-egress` and both root routes with it. That is not
advice a human can decline to follow; it is the probe doing it. It never fired
only because the namespace refusal, the route-overlap refusal and an EEXIST on
the link all sit ahead of it, and the trap is installed *after* the refusals.

**Nothing in the probe changed.** Its header still says its additions are "on
addressing of its own", which was true when it was written: it predates
`host/netns.nix`, it verified the shape, and then `capsules.nix` was written
**from its map** — that file's own header says so, "That map is
`probe/netns-egress.sh`'s, which is where it was verified". The probe became a
borrower of live addressing by standing still while the declaration moved onto
it.

That is the general shape, and it is why the rule needed an enforcer rather than
a sentence: **a probe that verifies a shape before the shape is declared becomes
a borrower the moment the declaration copies it.** Every review of the probe
after that point reads a file whose comment is accurate about the day it was
written and false about the host it runs on. There is no diff to notice.

**And there was a third instance, which is what settles that it is a class.**
`probe/netns.sh` — the VM-less model, the oldest of the three — was never
suspected, because its links and namespaces really are its own (`spk-*`,
`capspk-*`). Its *addressing* is not: it carves `10.100.<i>.{1,2}` per capsule
and its stage 2 puts `10.101.0.1/30` on a link and a route for `10.100.0.0/16`
**in the root namespace**. It is the file `capsules.nix`'s per-index scheme was
copied from. Nothing about it looks borrowed at a glance, which is the point —
the name check that would have been the "obvious" fix passes it cleanly. All
three now take their addressing from `probeFabric`, so all three are covered by
one assertion.

## What was done

The fabric moved into `probe/harness.sh` — the aggregator, a veth per capsule by
index, the host's NAT and route, the resolver detection, both nft tables and the
proxy verbs — because [`probe/two-capsules.sh`](../../probe/two-capsules.sh)
needs the same one for its policy round and two copies of an egress fabric are
two answers the first time one is edited. That is the same reason the harness
already carries the capsule boot.

Its names and addressing come from `flake.nix`'s `probeFabric`:

```
probe-egress / probe-peer   namespaces
pr-up / pr-rt               the aggregator's uplink veth
pr-out<i> / pr-wan<i>       one veth per capsule
10.110.0.0/16               capsule <-> aggregator
10.111.0.0/30               aggregator <-> root
```

and beside it, `borrowed = intersectLists (attrValues probeFabric) liveNames`,
where `liveNames` is every namespace, link, address and network `capsules.nix`
declares. A non-empty intersection **throws at eval**, so a future copy in
*either* direction — the probe reaching for a live name, or the declaration
reaching for the probe's — is a build failure rather than an incident. The
addresses each probe derives per index are covered by the /16 differing, exactly
as `capsules.nix` derives its own from `uplinkNet`.

Checked the way this repo checks a check: six fields set to their live values one
at a time, six refusals, naming the borrowed string. `netBase` is the one worth
having — setting it to `10.100` is caught through the *derived* `net`, and a base
that moves is what would silently relocate every per-index address at once.

`probe-netns-egress` also joined `just build`. It was a flake output that no
recipe named, so nothing built it routinely — the same family as
[item 37](./037-a-teardown-that-only-unnames.md)'s finding, one notch milder,
and found by the same question: *what builds this?*

## What running it then found, one level down

Both probes came back green on the new fabric — `probe-netns-egress` as a
regression check, and `probe-two-capsules` at **40/42**. The two reds are the
same class as this item, pointed at an *assertion* instead of a fabric:

> `capsule A collects into its own quarantine` — PASS
> `what came out of A is what went into A` — FAIL

The probe looked for `refs/capsule/<name>/<branch>`. `capsule-collect` has
fetched into `refs/capsule/<name>/heads/<branch>` since
[item 32](./032-the-sideband-channel.md) split the code half from the state half,
so that assertion has been wrong since the day the convention moved and nothing
noticed — **nothing runs a probe.** Item 37 found programs nothing *built*; this
finds an assertion nothing *ran*, and the shape is identical: a file that is
correct about the day it was written, in a language nobody compiles.

Fixed the same way as the fabric, for the same reason: `flake.nix` binds
`quarantine = import ./host/quarantine.nix` and injects
`quarantine.codeRefsOf pairA`, so the probe reads the construction that *decides*
where a collect lands rather than this repo's memory of it. Unrun.

## What the fix cost

**The host's resolver.** `~/flakes` puts `DNSStubListenerExtra` on `10.101.0.1`,
which is the live capsule-facing address — so moving the probe fabric to
`10.111.0.1` moved it off the stub, and every probe now reports

```
NOTE  no host resolver on 10.111.0.1 — fell back to 1.1.1.1, which LOSES the host's DoT hop.
```

No assertion depends on it: an allowlist is matched on the name before anything
resolves, and the probe's own fallback is designed to be loud for this reason.
But it is a host-config edit the fix created — a second `DNSStubListenerExtra`
and a port-53 input allow on the probe's link — and until it lands, probe traffic
resolves publicly. Recorded rather than fixed here, since `~/flakes` is not this
repo (README, "Host requirements").

## What this does not fix

The refusal covers what `capsules.nix` declares. It does not know about
`/etc/netns`, nft table names (the probe's `capeg-*` against the module's
`capsule-*`, which have never collided and are asserted by nobody), or anything
a *third* file might declare later. The check is one declaration wide, which is
the width the fault had.

The `probe-netns-egress` re-run's **count was not captured** — only its colour.
For that probe the total is part of the evidence, since a skipped stage 2b lands
at 27 and still reads green, so the number is worth re-taking.

## What was considered and rejected

- **Refuse to run on a module-path host**, the way `capsule-host` refuses while a
  `capsule-proxy-*` unit is active (*two shapes, one at a time*). It fixes the
  incident and forfeits the probe: this host runs the module path, so the probe
  becomes unrunnable exactly where its evidence is wanted — and
  `probe/two-capsules.sh`'s policy round would have inherited the same refusal,
  which is what makes it the wrong answer rather than merely the weaker one.
- **Rename the namespace only.** That is what the fault looked like from the
  outside and it would have left `eg-rt`, both addresses and the /16 shared —
  i.e. it would have removed the refusal that was *protecting* the live fabric
  and left the `ip link del` behind it.
- **A comment in both files.** The fault's whole mechanism is that a comment
  which was true when written stopped being true without an edit.
