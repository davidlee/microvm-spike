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

## Closed 2026-08-17

Both dependents have run against a switched host, which is this item's own
closing condition:

- `CHR-003` found `ISS-004` — the profile pin was inert on the module path — and
  the fix's live proof was taken on slot `c` after a further switch.
- `CHR-002` exercised `land`'s report, `--branch`'s create and its refusal, the
  stale exhibit and the tracked-file refusal on slot `d`, all through
  `/run/current-system/sw/bin/capsule`, and produced `ISS-006`.

The second trap above was paid again on the way: `ISS-004`'s first three
readings came from the devshell's `capsule`, which shadows the module's inside
this checkout, and read as the fix having broken the drift marker
(`mem.fact.oubliette.devshell-programs-shadow-the-modules`).

Recurring by nature, so this closes as an item and not as a habit: the host will
lag HEAD again at the next commit, and the next exercise that needs the module
path starts with a switch.

Evidence rung (`STD-001`): a switch is **start** for the units and no more.
