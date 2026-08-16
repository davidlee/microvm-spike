`CHR-004`, and the answer is not the one the chore expected.

`NOTES item 41` granted `capsule <slot> policy <name>` the one privilege it
needed — `systemctl restart capsule-proxy-<slot>`, `NOPASSWD`, one literal per
declared slot — and closed on the owner running it against a cold ticket. The
chore's whole point was that **the owner's success is the weakest form of that
evidence**: the owner also holds blanket `(ALL : ALL) ALL`, so a call that ends
in root proves nothing about delegation.

Run as a non-owner, the verb never reaches the grant.

```
$ sudo -K ; sudo -u assigner /run/current-system/sw/bin/capsule b policy sealed
…/capsule: line 455: /var/lib/capsule/slot/b/.lock: Permission denied
capsule: 'b' still holds build — the
  record, its allowlist link and its proxy move together and
  none of them moved.
```

## Three gates, and the grant is the third

| # | thing | mode | a non-owner in `users` |
| --- | --- | --- | --- |
| 1 | `/var/lib/capsule/slot/<n>/.lock` | `0644 owner:users`, dir `0750` | no write — `flock` fails, **this is where it stopped** |
| 2 | `/var/lib/capsule-allowlist/` | `0755 owner:users` | no write, so no re-point |
| 3 | `sudo systemctl restart capsule-proxy-<n>` | `users = [cfg.owner]` | not granted |

All three are `host/services.nix`: the two `systemd.tmpfiles.rules` and the
`security.sudo.extraRules` entry. Item 41 made the verb **reach root**. It did
not make it **delegable** — the only principal who can take the record's lock is
the same principal whose success the chore called weak evidence.

## What the run does establish

Two things, and they are worth separating from the gap.

**The rollback contract holds for a failure it was not designed for.** Item 41's
hook was built against a proxy that will not restart. Here the failure is a
permission on the lock — earlier, and outside `recordAlso` entirely — and the
verb still ends with the record, the link and the proxy all where they were, and
says so. Fail-closed.

**The instrument the standard warns about was wrong again.** `sudo -n -l` on this
host lists the ten proxy-restart literals and reports the verb as authorised.
That listing is true and it describes a verb no assigner can invoke. Third time
that instrument has meant nothing (`STD-001`, after items 43 and 44) — only a
call answers about a call.

## Rung

`STD-001`: the chore held this at **exercise**, by the owner, and asked for
**compare**. Compare is what it bought — the same verb, two principals, and the
difference is not the sudoers rule anybody was looking at.

Not reached: gates 2 and 3 are still unexercised by a non-owner, because gate 1
stops the call. Slot `b`'s proxy was inactive, so the restart branch would have
been skipped in any case.
