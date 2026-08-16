# ISS-005: The policy verb is delegable in shape and owner-only in fact

`EVD-008`, out of `CHR-004`. `NOTES item 36` built `capsule <slot> policy <name>`
so that **an assigner may select within a slot's declared set and may not widen
it**, and `NOTES item 41` closed on granting that verb the one root step it
needed. Exercised by a principal who is not the owner, it fails at the record's
`flock` — two gates before the grant.

Three gates, all `host/services.nix`:

| # | thing | mode | non-owner in `users` |
| --- | --- | --- | --- |
| 1 | `${stateDir}/slot/<n>/.lock` | `0644 owner:users`, dir `0750` | no write |
| 2 | `${allowlistDir}/` | `0755 owner:users` | no write |
| 3 | `systemctl restart capsule-proxy-<n>` | `security.sudo.extraRules`, `users = [cfg.owner]` | not granted |

So the assigner item 36 designed for does not exist as an OS principal, and the
grant item 41 added is reachable only by the one caller who did not need it.

**This wants a decision, not a patch.** Two shapes, and they are not close:

- **Make it delegable.** An `assigners` option beside `owner` — a group that owns
  the two directories (`0770`/`2775`, or a dedicated group rather than `users`)
  and appears in the sudoers rule's `users`. This is the reading `POL-001` points
  at: the assigner may say *which of the declared policies* a slot holds and may
  not say what the declared set is, which is exactly the split the perimeter is
  built on. Cost is a second principal to keep correct, and the state directory
  stops being owner-private — which `NOTES item 49` decided deliberately.
- **Drop the word.** Say the verb is the operator's, and that "delegable"
  describes the *authorisation model* (a slot's declared set bounds the
  selection) rather than a second OS principal. Cheap, and it makes item 36's
  and item 41's prose wrong where they are read most.

Whichever wins is an `ADR`, since `NOTES` is closed (`ADR-002`) and both readings
contradict prose already committed.

Two smaller things the same run surfaced, worth carrying whichever way it goes:

- **The diagnostic is a bash redirection error.** `…/capsule: line 455:
  /var/lib/capsule/slot/b/.lock: Permission denied` names a store path and a line
  number and never says *you are not this host's capsule owner*. The composite
  refusal underneath it is correct and true; the cause line is unreadable to the
  person it is addressed to.
- **Gates 2 and 3 remain unexercised by a non-owner**, because gate 1 stops the
  call. If gate 1 opens, they are the next two runs, and gate 3 needs a slot
  whose proxy is actually running — `proxyActive` is false on every free slot
  today, so the restart branch is skipped.
