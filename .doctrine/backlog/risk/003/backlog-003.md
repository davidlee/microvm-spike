# RSK-003: A namespace teardown is instrumented as a program, not a unit

`probe/netns-restart.sh` runs `capsule-netns` directly, 33/33 (`NOTES item 37`).
What sits **outside** that instrument is all systemd:

- ordering,
- the fact that a unit failing in `ExecStart` **never runs `ExecStop`**,
- the start limit.

Two of those are what turned that bug from a failed restart into a recovery — so
the untested surface is precisely the surface that made the incident expensive.

That is a **live-host claim and probably not a probe's shape**, which is why this
is a tracked risk rather than a chore: the honest options are a live exercise, or
accepting the gap and saying so.

Related and already paid for: **a newline in a unit directive silently deletes
the rest of the drop-in**, and everything else looked fine while it did — the one
witness is `journalctl -u microvm@<name>`. `just build` now refuses a newline in
any of the module's `serviceConfig` values, which is a build-rung guard against
one instance of this class, not the class.

Evidence rung (`STD-001`): **run** as a program; nothing at **start** for the
unit-level behaviour.
