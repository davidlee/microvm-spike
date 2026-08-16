`NOTES item 41` granted `capsule <slot> policy <name>` its one root step —
`NOPASSWD: /run/current-system/sw/bin/systemctl restart capsule-proxy-<slot>`,
one literal per declared slot — and that grant is live and correct. It is still
not enough to run the verb, and `sudo -n -l` will tell you otherwise.

Three gates, in the order a call hits them, all declared in `host/services.nix`:

1. `${stateDir}/slot/<n>/.lock` — `0644 owner:users` in a `0750` directory. The
   record's `flock` (`host/record.nix`) needs **write**, so a non-owner dies
   here, with a bash redirection error naming a store path and a line number.
2. `${allowlistDir}/` — `0755 owner:users`. No group write, so `recordAlso`'s
   `ln -sfT` could not re-point the link either.
3. `security.sudo.extraRules`, `users = [cfg.owner]`. The grant, and it is the
   *last* thing in the way rather than the first.

So the verb is **delegable in shape and owner-only in fact**: item 36's assigner
— someone who may say which declared policy a slot holds and may not widen the
set — does not exist as an OS principal on this host. Exercised: `EVD-008`.
Open: `ISS-005`, which is a decision (grant a second principal, or stop calling
it delegable) and not a patch.

The trap for a future agent is the instrument. `sudo -n -l` lists the ten
proxy-restart literals and reports the verb authorised; that listing is true and
describes a verb no assigner can invoke. Third time it has meant nothing
(`STD-001`, after `NOTES` items 43 and 44). Only a call answers about a call —
and the caller has to be someone who is not the owner, because the owner holds
blanket `(ALL : ALL) ALL` and would have got there anyway.
