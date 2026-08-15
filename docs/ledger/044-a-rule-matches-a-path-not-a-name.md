# NOTES item 44 — a rule matches a path, not a name

*State: **fixed, switched and exercised — the verb reaches root unattended**.
`sudo -K`, then `capsule b policy sealed` and `capsule b policy build` back to
back: both restarted the proxy with no prompt, generations 21 and 22. Nothing
warm carried it — no password was typed after the `-K`, and a `NOPASSWD` match
records no timestamp — and it was the module's own copy, a new store path
carrying `sudo /run/current-system/sw/bin/systemctl restart "$1"`, not a
devshell one. That also takes [item 36](./036-a-policy-is-selected-not-named.md)'s
last owed exercise, the **in-place restoration**: one slot, out and back, nothing
moving but the proxy. What follows is the fault. With
[item 43](./043-a-grant-that-was-present-and-inert.md)'s shadow gone and the
grant genuinely last in the rendered sudoers, `capsule b policy sealed` **still
asked for a password**. The rule permits
`/run/current-system/sw/bin/systemctl restart capsule-proxy-b`; the front end ran
`sudo systemctl restart capsule-proxy-b`, and sudo on this host resolves that
against the **caller's** `PATH`, which `writeShellApplication` starts with
`${pkgs.systemd}/bin`. Two commands, not one. The command is now a single value —
`host/proxy-restart.nix` — imported by the program that runs it, the module that
grants it and the eval check that pairs them, so the three cannot disagree.*

One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What happened

Both halves of item 43's switch landed. The rendered sudoers is now what it was
supposed to be all along:

```
root     ALL=(ALL:ALL)    SETENV: ALL
%wheel   ALL=(ALL:ALL)    SETENV: ALL
%wheel   ALL=(ALL:ALL)    NOPASSWD:SETENV: …/rtcwake
david    ALL=(ALL:ALL)    NOPASSWD: …/nft list table inet capsule-forward
david    ALL=(ALL:ALL)    NOPASSWD: /run/current-system/sw/bin/systemctl restart capsule-proxy-a, … -j
```

The blanket is gone and the grant is last. Then, on a cold ticket:

```
$ sudo -K
$ /run/current-system/sw/bin/capsule b policy sealed
  restarting capsule-proxy-b — egress is down for the length of it
[sudo] password for david:
sudo: a password is required
```

Item 41's rollback fired correctly for the second time. The grant, again, did
nothing.

## Why

**This host's sudoers sets no `Defaults secure_path`.** So sudo resolves an
unqualified command name against the caller's `PATH` — and `writeShellApplication`
prepends `runtimeInputs` to it, which is the seam this whole repo is built on
(CLAUDE.md: a case cannot stub `ip`, or `systemctl`, by putting one in front).
The front end's `systemctl` is therefore a store path, and that is the command
sudo is asked to authorise:

```
$ sudo -n -l /run/current-system/sw/bin/systemctl restart capsule-proxy-b
/run/current-system/sw/bin/systemctl restart capsule-proxy-b
$ PATH=/nix/store/…-systemd-261.1/bin:$PATH sudo -n -l systemctl restart capsule-proxy-b
/nix/store/mc901k2s1n3v1disrj0356l7lwz7l6vg-systemd-261.1/bin/systemctl restart capsule-proxy-b
```

Same words, two commands. The second matches only `%wheel ALL=(ALL:ALL) SETENV:
ALL`, which needs a password.

Note the instrument, for the third time in three items: `sudo -n -l` printed the
store-path command back without complaint, though the rule matching it is not
`NOPASSWD`. It reports **what would run**, not whether it would run *free*. Item
43 said `sudo -l` answers about the ruleset and only a call answers about the
call; this is that sentence again, and it was found the same way — by making the
call.

## Item 41 wrote the reason down backwards

Item 41 chose `/run/current-system/sw/bin/systemctl` for the rule and explained
it as *sudo resolves the command against its own `secure_path` before matching, so
a store-path rule reads correctly and never fires*. Every clause of that is
wrong on this host, and it is wrong in the direction that makes the rule inert:
there is no `secure_path`, resolution is the caller's, and it is the `/run` rule
that never fires while the caller is a `writeShellApplication`.

The **choice** it made is still right, for a reason it did not give: a store path
pins the grant to one systemd build, so the rule would lapse at the next bump of
an input unrelated to this repo — silently, and fail-open. So the fix is to make
the *program* say the same absolute path, not to make the rule say a store one.

## The fix is one value, not three careful ones

The command was spelled three times — in `host/cli.nix`'s `proxyControl`, in
`host/services.nix`'s `security.sudo.extraRules`, and in `flake.nix`'s
`unrestartable` check. Two of the three agreed, which is why the check was green:
**it paired the module against itself.** `unrestartable` asks *does a rule name
this unit's restart*, and both sides of that question came from the same file.
The program that actually issues the command was never in the pairing.

`host/proxy-restart.nix` is now the single spelling and all three import it.
That is CLAUDE.md's own rule applied where it had not been — *anything built at
two call sites needs one construction, not two careful ones* — and it is
preferable to an assertion here: with one value there is no divergence to detect.

What it does **not** fix, and cannot: whether the resolved path is one sudoers
matches. That remains a property of the host, and the only instrument is the
call.

## What this belongs to

The seventh, and the second in a row where **the fix for the previous item is
what exposed it**. 37 a program nothing built, 38 an assertion nothing ran, 39 a
unit nothing started, 40 a refusal nothing had triggered, 41 a branch nothing had
taken, 43 a grant nothing had exercised — and 44 **a grant exercised against a
command nobody had compared**. Item 43's exercise was the right one and it was
run twice; the first run found a shadow, the second found this, and neither was
visible to anything that reads a declaration.

Worth stating plainly because three items have now each cost a switch: **every
question about a sudoers grant is a question about the whole host at the moment
of the call** — precedence over the rendered file, resolution over the caller's
environment, authentication over the ticket. This repo can make its own two
spellings one. It cannot answer any of the three, and should stop trying to
imply that it has.
