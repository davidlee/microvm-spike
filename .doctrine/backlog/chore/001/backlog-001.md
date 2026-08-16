# CHR-001: Switch this host onto HEAD

The host tracks `~/flakes`, which builds this repo via
`--override-input oubliette git+file:///home/david/dev/microvm-spike` — a symlink
to this checkout, reading **committed HEAD**. So the installed programs lag every
commit until `just system-switch` runs, and a lock update alone changes nothing.

Recurring by nature; it is a backlog item because it is the **precondition** for
CHR-002 and CHR-003 being real exercises rather than sandbox ones. Close it when
both of those have run against a switched host.

Two traps, both already paid for:

- **A generation bump is not evidence a code change landed** — four consecutive
  rebuilds here had nothing between them.
- **Ask the program, don't read it.** The module's programs on `PATH` are
  wrappers whose whole text is `CAPSULE_STATE`/`CAPSULE_REPO` and an `exec`, and
  an interactive `PATH` can hold a third, staler copy. Grepping one reports a
  program that does not have the flag, and the two wrong readings corroborate
  each other. Run `/run/current-system/sw/bin/capsule all status`.

Evidence rung (`STD-001`): a switch is **start** for the units and no more.
