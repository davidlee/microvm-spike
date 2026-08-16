Naming a path under a directory the unit's user cannot **traverse** gives a unit
that starts cleanly and then dies at `open()` — `Permission denied` about a path
that is plainly there, with `systemctl show` reporting the bind exactly as
intended.

Every `capsule-proxy-<slot>` was in that state from the day `NOTES item 36` was
switched: its allowlist link sat under `stateDir` (`0750 owner:users`) and the
proxy runs as `capsule-proxy`.

**The cases cannot catch this class either** — a sandbox has one uid — so
`hostModuleUnits` asserts the second pairing of the same kind: the module's own
`d` tmpfiles rules against each unit's `User`, throwing when a bound path is
unreachable.

**The fix was placement, not permission** (`NOTES item 39`): the link moved to its
own `allowlistDir`, because opening `stateDir` far enough to traverse also opens
`collect/`, which holds every exhibit any capsule has sent back.

**And the general one: a control can be switched and proven and still never have
been started.** Two probes proved a selected policy reaches the wire using their
*own* proxy as the human; the unit that does it on this host had never come up.
When a slot is running, read `capsule all status`'s unit column — it
distinguishes `running` from `auto-restart`, which is a crash loop.