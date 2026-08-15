# NOTES item 39 — a bind is mounted as root and opened as the user

*State: **fixed, asserted at eval, and switched-owed**. Every `capsule-proxy-<slot>`
unit was unable to start: `BindReadOnlyPaths` named its allowlist under
`stateDir`, which is `0750 owner:users`, and the proxy runs as `capsule-proxy` —
so the mount succeeded as root and the open failed as the unit. The link lives in
its own `allowlistDir` now, outside the directory the human's state is in, which
is [item 36](./036-a-policy-is-selected-not-named.md)'s own separation made true
of the filesystem rather than only of the code. `hostModuleUnits` **throws at
eval** when any unit binds a path under a module-declared directory its user
cannot traverse — watched going red on the pre-fix path, naming both offending
prefixes for all ten slots. Needs a `~/flakes` switch, and one command per
non-default slot after it (below).*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What happened

`just up b`, the first start of any slot since item 36 was switched onto this
host. The guest came up. The proxy did this, every three seconds:

```
capsule-proxy: 10.99.0.1:3128 (allowlist: /var/lib/capsule/slot/b/allowlist)
filter file: Permission denied
capsule-proxy-b.service: Main process exited, code=exited, status=65/DATAERR
capsule-proxy-b.service: Scheduled restart job, restart counter is at 42.
```

The path is there, the bind names it, and `namei -l` shows why anyway:

```
drwxr-x--- david users  /var/lib/capsule
drwxr-x--- david users  /var/lib/capsule/slot/b
lrwxrwxrwx david users  allowlist -> …/perimeter/egress-none.txt
```

`capsule-proxy` is uid 971 in one group, its own. The module puts *the human*
into `capsule-proxy` so a person can read the egress log
(`host/services.nix`); it does not put `capsule-proxy` into `users`, and there is
no reason it should. So the proxy cannot traverse `/var/lib/capsule`.

**The bind is not the access.** systemd sets the mount up as PID 1, so the source
resolves and the unit starts; the process then opens the path as its own user and
the kernel walks the real directory chain. Nothing in `systemctl show` looks
wrong, because nothing there is wrong.

## Why it survived being switched, asserted and proven

The perimeter's controls are exhaustively checked, and every check was pointed
somewhere else:

- **`policyCases`** runs the front end's own text and asserts that the record and
  the link move together. They did. A sandbox has one uid.
- **`hostModuleUnits`** evaluates the module and reads `serviceConfig` strings.
  `BindReadOnlyPaths` was *present and correct* — it named exactly the path
  intended.
- **`probe/netns-egress.sh` and `probe/two-capsules.sh`** put a real guest
  through a real allowlist and proved a selected policy reaches the wire, twice,
  in both directions, with a swap. Both build the proxy through the harness's
  `proxy_up`, in the probe's own namespace with the probe's own state directory,
  **as the human**. They prove the perimeter mechanism. They cannot see this
  unit.
- **The switch itself** materialised the tmpfiles links at each slot's declared
  policy and was read as the module half landing. It landed. Nothing started it.

So item 36 was recorded as *switched, and proven at the wire*, and both halves of
that were true while the unit that does the work on this host had never run once.
**A control can be switched and proven and still never have been started**, and
the gap between those is a slot coming up — which had not happened all day
because both slots were idle.

The witness that existed and was not read: `capsule all status` reports a unit's
`SubState`, and `host/cli.nix` says in a comment that `running` versus
`auto-restart` "are the difference between a capsule and a crash loop". The
column was ready. Nobody looked at it while a slot was up.

## The fix, and why not the two cheaper ones

The link moved to `allowlistDir`, `/var/lib/capsule-allowlist`, `0755
owner:users`, one symlink per slot named for the slot. `stateDir` is untouched.

**Not widening `stateDir` to `0751`.** Traverse-only there looks surgical and is
not: `collect/` under it is already `0755`, and the quarantines inside it are
`0755` too, so `stateDir`'s `0750` is the *only* gate on everything every capsule
has ever sent back. The one directory that must not become traversable is the one
this would have made traversable.

**Not `SupplementaryGroups=users`.** That hands the perimeter's uid the human's
group across the whole host, to read one symlink.

The placement is the argument. Item 36 already says the proxy **never reads the
assignment record** — the front end resolves, and a proxy that read host state to
learn its own perimeter would be a control taking instructions from the thing it
constrains. That was true of the code and false of the filesystem: the file the
proxy must read was *inside the record's directory*, so the two were one
permission decision, and the decision that let the proxy work was the one that
opened the record. Splitting them makes the rule structural: the proxy has no way
to the record, rather than no reason to read it. `stopKey` is already outside
`stateDir` for the shorter version of the same reason, and says so.

## What is asserted now

`hostModuleUnits` pairs two of the module's own declarations — the `d` rules that
say what mode it gives each directory it creates, and each unit's `User` — and
throws when a unit binds a path under a directory its user cannot traverse.
Ownership, declared group membership, then the others `x` bit, in that order.

This is the third of these pairings and they have one shape. `guardCases` proves
the guard's *logic* and cannot prove a privilege, so `hostModuleUnits` asserts
that the guard's unit has `CAP_SYS_PTRACE` (item 30). `probeFabric`'s `borrowed`
refuses at eval rather than asking a comment to stay true
([item 38](./038-a-probe-that-became-a-borrower.md)). Here: **a case suite runs
as one uid and cannot discover a permission, so the permission is checked where
both halves are declared.** The rule each time is that when the two things that
must agree are both in this repo, their agreement is evaluable, and anything
evaluable should throw rather than be remembered.

Watched going red: pointing `allowlistOf` back at the old path fails the eval
with twenty findings — both offending prefixes for each of ten slots — naming the
unit, its user, the path and the directory. `policyCases` gained the assertion
that the link is **not** in the record's directory, which is the one thing every
other case in that file would pass if it came back.

## What it costs to land

A `~/flakes` switch, and then **one command per slot that is not on its declared
default**. tmpfiles' `L` creates the new link at the slot's declared policy and
leaves an existing one alone — which is right, and means a slot whose *record*
says something else gets a link that disagrees with it. Today that is `b`, which
is on `sealed`: after the switch, `capsule b policy sealed` re-points the new
link and the two agree again. The old links under `slot/<name>/` are dead weight
and can be removed by hand.

That divergence is worth naming rather than automating. The record and the link
move together under one lock precisely so they cannot disagree; a *path move* is
the one event that can separate them, because it is the one thing neither the
verb nor the lock is party to.
