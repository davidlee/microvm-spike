# NOTES item 41 — a delegable verb that ends in root, and the half-write when it cannot

*State: **done — the verb reaches root unattended, and the rollback has fired for
real twice on the way there**. `sudo -K`, `capsule b policy sealed`, no prompt,
generation 21; and back to `build` at 22. It took two further faults to get
there, [43](./043-a-grant-that-was-present-and-inert.md) and
[44](./044-a-rule-matches-a-path-not-a-name.md), each found by running this
exercise and each invisible to everything that reads a declaration. On a
cold ticket `capsule b policy sealed` answered `sudo: a password is required` and
then `capsule: capsule-proxy-b would not restart, so the selection was undone.`:
link back, no document, the refusal true rather than nearly true. It fired
because the grant this item added was shadowed in the rendered sudoers, which is
[item 43](./043-a-grant-that-was-present-and-inert.md) — so the exercise that
proves this half is also the one that found the next fault. The restart moved inside the
record's hook, so a proxy that will not bounce undoes the selection instead of
half-applying it; the module grants exactly that one restart per declared slot;
and both halves are pinned — `policyCases` is 44 assertions (was 32) with the
branch and its failure both reachable from a sandbox, and `hostModuleUnits`
throws when a proxy unit has no rule naming its restart. Needs a `~/flakes`
switch to reach this host. What follows is the fault as found.*

*`capsule <slot>
policy <name>` is the verb [item 36](./036-a-policy-is-selected-not-named.md)
built so that an assigner may select within a slot's declared set, and
[item 11](./011-host-side-runs-as-you.md) says everything host-side
runs as you. Its last step is `sudo systemctl restart capsule-proxy-<slot>`, and
this host has no rule permitting it — only `nft list table inet capsule-forward`
and `rtcwake` are `NOPASSWD`. It went unnoticed because that branch had never
run: every previous call found the proxy inactive and took the other one. It ran
today only because a `just up` minutes earlier had left a sudo ticket warm. **The
failure mode is fail-open in the one direction that matters**: the record and the
link move under the lock, the restart fails after them, and a slot narrowed from
`build` to `sealed` reads `sealed` everywhere while the wire still serves
`build`.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What happened

The two owed exercises of item 36 both ran (`probes.md`), and between them:

```
$ sudo -n -l
    (ALL : ALL) SETENV: NOPASSWD: …/rtcwake
    (ALL : ALL) NOPASSWD: /run/current-system/sw/bin/nft list table inet capsule-forward
```

Nothing for `systemctl restart capsule-proxy-*`. The human here also has
unrestricted `(ALL : ALL) ALL` with a password, so at a terminal the verb works
and prompts; from anything without a tty it does not, and for the *assigner* the
verb was designed for — someone who may say which project a slot holds and may
not say what it may talk to — it does not exist at all.

## Why this is not a packaging detail

The verb writes two things and then asks for a third:

1. the allowlist link, re-pointed — **inside** the record's `flock`;
2. the record, `.policy = $want` — the same lock, link first;
3. `systemctl restart capsule-proxy-<slot>` — **outside** it, and outside this
   user's authority.

(1) and (2) are one atomic pair on purpose, so the record and the link cannot
disagree. (3) is what makes either of them true of the wire, because the proxy
renders its config at start and holds it. So the invariant the lock protects is
*the record agrees with the link*, and the thing anyone actually cares about is
*the wire agrees with the record* — which no lock covers.

`writeShellApplication` sets `-e`, so a failed `sudo` aborts the program after
both writes. The output is not silent — the `restarting …` line has already
printed and sudo says its piece — but the *state* is: two halves moved, the third
did not, exit nonzero, and `capsule all status` reports the new policy because it
reads the record.

**Direction decides severity, and it is the wrong way round.**

| selection | record + link | wire until a restart | |
| --- | --- | --- | --- |
| `sealed` → `build` | `build` | `sealed` | fail-closed; confusing, harmless |
| `build` → `sealed` | `sealed` | **`build`** | fail-open; the perimeter is wider than every reader of it says |

A narrowing that half-lands is exactly the case a policy verb exists for.

## Three fixes considered

**Refuse before writing anything.** The verb can ask whether it will be able to
restart — `sudo -n` against the exact unit — and refuse the whole selection
before the lock is taken. This is the repo's own discipline extended one step: a
selection that cannot reach the wire is not a selection, and the existing order
(link first, then record, under one lock) already says the half-state is the
thing to design against. Cheap, no privilege granted, and it converts a
fail-open into a refusal.

**Let the module grant exactly that restart.** The module declares the
`capsule-proxy-<slot>` units, so a `security.sudo.extraRules` naming them —
`systemctl restart capsule-proxy-a`, one literal per declared slot, no wildcard —
belongs in `host/services.nix` and not in `~/flakes`. It is proportionate: an
assigner may already select the policy, and the only new power is bouncing a
proxy, which is a brief fail-closed egress outage. This makes the verb actually
delegable rather than merely shaped that way.

## What was built

The first two — and the first is better done as a rollback than as the
refusal-in-advance it was written up as.

**The restart went inside the hook.** `recordWrite`'s `recordAlso` runs under the
slot's lock and *before* the document, and host/record.nix defines its failure
as leaving nothing moved — which is the same argument that put the link before
the record. Extending it one step makes the wire part of that: the hook
re-points the link, bounces the proxy, and on a failed bounce puts the link back
by hand (nothing else knows what it was) and returns non-zero, so no document is
written and the verb's existing refusal is *true* rather than nearly true. Its
wording moved with it — the record, its link and its proxy move together and
none of them moved.

Better than the check-first this item first recommended, and the reason is worth
keeping: **a check for whether root will be available is a
prediction, and it is racy** — a sudo ticket can expire between the check and the
use — while a rollback is an observation. `sudo -n -l` also cannot answer the
question that matters: on this host it reports the restart as *authorised*,
because the human has blanket `(ALL : ALL) ALL`, and the restart still needs a
password. Authorisation is not authentication, and only trying finds out.

**The module grants the restart.** `security.sudo.extraRules` in
`host/services.nix`, one literal `systemctl restart capsule-proxy-<slot>` per
declared slot, `NOPASSWD`, no wildcard. The path is
`/run/current-system/sw/bin/systemctl` and not a store path, because sudo
resolves against its own `secure_path` before matching — a store-path rule reads
correctly and never fires, which is what the eval check below was watched
catching.

> **This paragraph is wrong, and wrong in the direction that made the rule
> inert** ([item 44](./044-a-rule-matches-a-path-not-a-name.md)). This host sets
> no `secure_path`, so sudo resolves against the *caller's* `PATH` — which
> `writeShellApplication` starts with `runtimeInputs`, so the front end's
> `systemctl` is a store path and it is the `/run` rule that never fires. The
> choice of path stands for a different reason (a store-path rule lapses at the
> next systemd bump, silently and fail-open); what had to change is the
> *program*, which now spells the same absolute path from
> `host/proxy-restart.nix`. Kept in place rather than corrected, because the
> mistake is the item.

**Both are pinned.** `host/cli.nix` gained a `proxyControl` argument with a
default, for the reason `moduleState` has one: `pkgs.systemd` is in
`runtimeInputs`, so `writeShellApplication` prepends it to `PATH` and a case
**cannot** stub `systemctl` in front of it. With two environment variables the
suite reaches all three shapes off one store path — proxy down, proxy
restarted, proxy refusing — and `policyCases` went 32 → 44. Watched going red on
a mutation that is plausible live code (the hook tolerating a failed restart):
four assertions, and the one about the link staying put stays green, which is
what says the halves are separable.

`hostModuleUnits` pairs the proxy units against the sudoers commands and throws
when one has no rule. Fourth instance of that shape after item 30's capability
and item 39's traversal, and it earns its place twice over: nothing else in this
repo reads `security.sudo.extraRules`, so without it a type error there would
surface in a host rebuild.

## Not built: the path unit

**Take the human out of it: a path unit.** `systemd.paths` watching
`allowlistDir` and restarting that slot's proxy would make step (3) systemd's,
triggered by step (1). Attractive and it is *not* the same claim — it makes the
wire eventually agree rather than agree, and it introduces a restart nobody
asked for, on a directory a human can also edit by hand. It also inverts the
direction the perimeter is supposed to flow: a control that reacts to a file is a
control taking instructions from the filesystem, which is a weaker version of
what item 36 refused when it kept the proxy from reading the assignment record.

## What this belongs to

The same family as the four before it, and the one the last of them predicted.
[Item 37](./037-a-teardown-that-only-unnames.md) found programs nothing built,
[38](./038-a-probe-that-became-a-borrower.md) an assertion nothing ran,
[39](./039-a-bind-is-not-a-traversal.md) a unit nothing started, and
[40](./040-no-doors-is-not-the-other-shape.md) a refusal nothing had triggered.
This is a **branch nothing had taken** — `is-active` was false every previous
time — and it was taken today under a borrowed sudo ticket, which is the sort of
thing that makes a first run look like a pass.

`policyCases` cannot catch it: the cases stub the host and run as one uid, and
this is a privilege. It is the fourth instance of *a case suite proves logic and
never authority*, after the guard's `CAP_SYS_PTRACE` (item 30) and the proxy's
traversal (item 39) — both of which were answered by pairing two of the module's
own declarations and throwing at eval. The same answer is available here and is
better than an assertion: if the module grants the rule, the pairing is
`capsule-proxy-<slot>` exists ⇒ a sudoers rule names its restart, and both halves
are in this repo.
