`host/services.nix`'s `wrap` sets its five variables with a bare `export`, not a
default:

```
export CAPSULE_PROFILE_DIR=${cfg.profileDir}
exec ${lib.getExe program} "$@"
```

So a caller that deliberately sets one of them **loses**, on the line before the
program starts — including the caller the module itself installs. `host/cli.nix`'s
`slotProfileName` resolves which document a verb on a slot reads and exports
`CAPSULE_PROFILE_DIR` for it; the wrapper of the program it execs overwrites that
with the host's directory, which is why the profile pin was inert for `collect`,
`provision`, `brief` and `adopt` while working for `baseline` and `refresh` —
those two are wrapped with `PATH` only and inherit the export
(`ISS-004`, found by `CHR-003` step 2).

**The programs are written for the override and the wrapper takes it away.**
`profileDir()` is `"${CAPSULE_PROFILE_DIR:-<default>}"`; `capsule-provision`'s
`src` is `"${CAPSULE_REPO:-$profile_path}"` with a comment claiming *the
environment still wins over both*. It does not win on the module path.

**Nothing here can catch it.** `hostModuleUnits` forces the module's programs, so
it proves the wrapper *evaluates*. The case suites run a program's own text
against stubs and never see a wrapper at all. A wrapper defeating the program it
wraps falls between the three kinds of check — read the installed wrapper, which
is the one time grepping `/run/current-system/sw/bin/<prog>` is the right move
rather than the trap in [[mem.fact.oubliette.module-programs-on-path-are-wrappers]].

Whether each variable is a **default the module supplies** or a **value it
imposes** is a per-variable decision, not one switch:
[[mem.fact.oubliette.capsule-state-moves-the-quarantine-not-the-record]] is why
`CAPSULE_STATE`'s answer is not `CAPSULE_PROFILE_DIR`'s.
