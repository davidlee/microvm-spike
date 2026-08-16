# CHR-004: Run the policy verb as a user who is not the owner

`NOTES item 41`. The policy verb has one exercise left, and it is the one that
matters: **the owner holds blanket `ALL`, so the owner's success is the weakest
form of that evidence.** A delegable verb that ends in root proves nothing about
delegation when the caller could have done it anyway.

Two instruments that will lie here, both from `STD-001`:

- **`sudo -n -l` is not evidence.** It answers *some rule permits this*, never
  *which matching line won*, and never *whether it would run free*. Only a call
  answers about a call.
- Item 41's *first* run passed on **an accident of environment** — a warm sudo
  ticket. Clear the ticket before the run, or the first run is the one least
  likely to expose the fault.

Evidence rung (`STD-001`): currently **exercise** by the owner. This buys
**compare** — the rung item 44 was found at.

## Outcome

Ran. `EVD-008` is the record and `ISS-005` is what it opened.

`sudo -K` then `sudo -u assigner /run/current-system/sw/bin/capsule b policy
sealed`, where `assigner` is a plain user in group `users`. It failed at
`/var/lib/capsule/slot/b/.lock: Permission denied` — the record's `flock`, two
gates before the sudoers grant, so **the grant was never reached**. Nothing
moved and the composite refusal was true.

The rung is **compare**, as the chore predicted. What it compared was not what
the chore expected: the difference between the owner and an assigner is the two
`systemd.tmpfiles.rules` in `host/services.nix`, not the
`security.sudo.extraRules` entry anybody was looking at. Both instruments named
above lied on cue — `sudo -n -l` reports the verb authorised, and it is a verb
no assigner can invoke.
