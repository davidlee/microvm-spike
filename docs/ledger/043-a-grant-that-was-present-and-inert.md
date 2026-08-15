# NOTES item 43 — a grant that was present and inert

*State: **fixed, asserted and switched — and it was not the only thing wrong**.
Both halves landed, the blanket is gone and the grant is last in the rendered
file; the verb **still** prompted, for a second and unrelated reason, which is
[item 44](./044-a-rule-matches-a-path-not-a-name.md): the rule names a path the
program does not run. This item's finding stands and its fix holds. What follows
is the shadow.*

*The rule
[item 41](./041-a-delegable-verb-that-ends-in-root.md) added was in the rendered
sudoers, matched the command, and was listed back by `sudo -n -l` — and a
`%wheel ALL=(ALL:ALL) ALL` one line below it took every match, because sudoers
is last-match-wins. The module's rule is `lib.mkAfter` now, which says what was
always meant, and `hostModuleUnits` reads the **rendered** file and throws when a
later line covering the owner matches untagged. The shadowing line belongs to
`~/flakes`, so the second half is a recommendation and not a commit here.*

*The finding is not the sudoers rule. It is that item 41's rollback **fired for
real**, on this host, and the only reason anyone looked is that it fired. Every
instrument this repo owns reported the grant as healthy.*

One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What happened

The switch carrying items 39, 40 and 41 landed. The one thing no test here can
prove is whether the `policy` verb reaches root without asking for a password, so
with the ticket deliberately cold:

```
$ sudo -k
$ /run/current-system/sw/bin/capsule b policy sealed
…
[sudo] password for david:
sudo: a password is required
capsule: capsule-proxy-b would not restart, so the selection was undone.
```

Two facts in four lines. The verb's rollback is **correct and proven live** — the
link went back, no document was written, and the refusal says exactly what is
true. And the grant that was supposed to make the prompt impossible did nothing.

`sudo -n -l` says the rule is there:

```
$ sudo -n -l /run/current-system/sw/bin/systemctl restart capsule-proxy-a
/run/current-system/sw/bin/systemctl restart capsule-proxy-a
```

So the path is right — sudo resolves against its own `secure_path` before
matching, and a store-path rule would have fallen through to the blanket and
printed nothing specific. The rendered file says why anyway:

```
root     ALL=(ALL:ALL)    SETENV: ALL
%wheel   ALL=(ALL:ALL)    SETENV: ALL
david    ALL=(ALL:ALL)    NOPASSWD: /run/current-system/sw/bin/systemctl restart capsule-proxy-a, … -b
%wheel   ALL=(ALL:ALL)    ALL
%wheel   ALL=(ALL:ALL)    NOPASSWD:SETENV: …/rtcwake
david    ALL=(ALL:ALL)    NOPASSWD: …/nft list table inet capsule-forward
```

Line 4 matches the same command, carries no tag, and is below line 3.

## Why every instrument said yes

**A rule is *granted* by being in the file and *effective* by being the last line
that matches.** Three readings of the same rule, all of them true, none of them
the question:

| instrument | what it answers |
| --- | --- |
| `hostModuleUnits`' `unrestartable` | a rule naming this unit's restart is **declared** |
| `sudo -n -l <cmd>` | this command is **permitted** — never which matching line won |
| the rendered `/etc/sudoers` | the answer, and nothing read it |

`sudo -l` is the trap worth naming. It prints the command back, which reads as
*this rule is what applies* and means only *some rule permits this*. On a host
where the human also has blanket `(ALL : ALL) ALL` it would print the same thing
with our rule deleted entirely — which is precisely the state item 41 was written
from, and precisely how item 41's own before/after evidence fails to
discriminate.

## Where the shadow comes from, and why it is not a bug over there

`~/flakes` contributes its own `%wheel ALL=(ALL:ALL) ALL` with this comment:

> ORDER IS LOAD-BEARING: sudoers is last-match-wins, so the broad wheel/ALL rule
> has to come first or it clobbers every NOPASSWD rule after it. (It is also
> redundant — the NixOS sudo module emits `%wheel ALL=(ALL:ALL) ALL` itself at
> mkOrder 600.)

Right about the mechanism, and wrong about the scope: **"first" orders it within
that list only**. nixpkgs emits its defaults at `mkOrder 400` and `600`; a plain
definition lands at priority 1000, where *module merge order* decides — not
declaration order, and not anything either module can see. Two modules both
contributing at 1000, one of them a blanket, is a coin toss whose result is a
security property.

The comment's parenthesis is the other half of the fix: the copy is redundant, so
its only effect on this host is to shadow every `NOPASSWD` rule any other module
contributes.

## The fix, both halves

**`lib.mkAfter` on the module's rule.** `mkOrder 1500`, which outranks anything
at 1000 whatever the merge order. It is not a workaround; it is the rule stating
its own nature — *this grant is narrower than any blanket and outranks one* —
where before it stated nothing and got 1000 by default.

**An assertion over the rendered file.** `mkAfter` loses to a definition ordered
later still, and precedence is a property of the whole file, so the check has to
read the file. The module's third assertion splits
`security.sudo.configFile`, finds the last line granting a
`restart capsule-proxy-`, and throws if any line below it covers the owner — by
name, or by a group the host's own `users.users.<owner>.extraGroups` puts them in,
read rather than assumed, the same way [item 39](./039-a-bind-is-not-a-traversal.md)
reads a unit's user — with `ALL` as the command spec and no `NOPASSWD` tag.

It is **vacuous in `hostModuleUnits`' standalone eval and fires at the switch**,
which is the honest place for it: the shadowing rule belongs to a config this
repo does not own, and there is no fixture here that could contain it. Watched
both ways against a fixture that adds one (`mkOrder 1600` red with the offending
line quoted back; `mkOrder 1000` green, which is what proves `mkAfter` does the
work at the real priority; absent, green).

The counterpart it does not replace: `unrestartable` still answers *is there a
rule at all*, which is a different failure with a different message.

## What this belongs to

The sixth of the family, and the first one an earlier item's fix caught rather
than a probe. [37](./037-a-teardown-that-only-unnames.md) a program nothing
built, [38](./038-a-probe-that-became-a-borrower.md) an assertion nothing ran,
[39](./039-a-bind-is-not-a-traversal.md) a unit nothing started,
[40](./040-no-doors-is-not-the-other-shape.md) a refusal nothing had triggered,
[41](./041-a-delegable-verb-that-ends-in-root.md) a branch nothing had taken —
and this is **a grant nothing had exercised**: present, matched, listed, inert.

Item 41's own lesson generalises one step. It said *a check for whether root will
be available is a prediction and a rollback is an observation*, and gave
authority-is-not-authentication as the reason. The reason is broader than sudo
tickets: **`sudo -l` answers about the ruleset and only a call answers about the
call.** Which is also the standing method rule pointed at a grant — build, run,
start, trigger, take, and now *exercise* — and the argument for the exercise this
one owes: a `policy` verb run by someone who is not the owner, which is the only
test of delegability that exists.
