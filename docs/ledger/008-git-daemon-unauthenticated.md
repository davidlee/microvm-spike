# NOTES item 8 — git-daemon is unauthenticated

*State: resolved by deletion ([item 18](./018-git-channel-direction.md)).*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

~~**git-daemon is unauthenticated**~~ **— resolved by deletion
([item 18](./018-git-channel-direction.md)).** It was, and
`--enable=receive-pack` was what made the update hook load-bearing. It had
accumulated `--strict-paths` with the mirror as the sole whitelisted path, a
`git-daemon-export-ok` marker in place of `--export-all`, `IPAddressDeny` on the
unit path, and finally a `safe.directory` exception to work at all. Every one of
those confined a service the host only ran because the guest was the party
initiating. The host initiates now, so there is no daemon, no hook, no mirror
and no port. Kept here because the accretion is the argument: five guards on one
service is what a wrongly-pointed channel costs.
