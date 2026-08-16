**Fixed in `4728425` (`ISS-004`), and kept because the class outlives the
instance.** `host/services.nix`'s `wrap` used to set its five variables with a
bare `export`, not a default:

```
export CAPSULE_PROFILE_DIR=${cfg.profileDir}
exec ${lib.getExe program} "$@"
```

So a caller that deliberately set one of them **lost**, on the line before the
program started — including the caller the module itself installs. `host/cli.nix`'s
`slotProfileName` resolves which document a verb on a slot reads and exports
`CAPSULE_PROFILE_DIR` for it; the wrapper of the program it execs overwrote that
with the host's directory, which is why the profile pin was inert for `collect`,
`provision`, `brief` and `adopt` while working for `baseline` and `refresh` —
those two were unwrapped and inherited the export.

**The programs are written for the override and the wrapper took it away.**
`profileDir()` is `"${CAPSULE_PROFILE_DIR:-<default>}"`; `capsule-provision`'s
`src` is `"${CAPSULE_REPO:-$profile_path}"` with a comment claiming *the
environment still wins over both*, which was a false claim in source rather than
a typo.

## What to do about it

`host/wrap.nix` is now the wrapper, all five are `''${VAR:-<default>}`, and the
rule is one sentence: **the module supplies defaults, it imposes nothing.** The
per-variable exception table was considered and rejected — it needs a defensible
reason each and a maintained exception, and both hazards it was for dissolve
(`CAPSULE_STATE` already splits quarantine from record on the devshell path, so
one rule makes that one behaviour; an overridden `CAPSULE_ALLOWLIST_DIR` fails
*closed*, since the proxy unit takes its allowlist from `cfg.allowlistDir` at
build). See [[mem.fact.oubliette.capsule-state-moves-the-quarantine-not-the-record]].

## Why nothing caught it, and what now does

`hostModuleUnits` forces the module's programs, so it proves a wrapper
*evaluates*. The case suites run a program's own text against stubs and never see
a wrapper at all. **A wrapper defeating the program it wraps falls between the
three kinds of check** — which is why item 52 named the gap in the abstract and
it was read as a test nobody had written rather than as a defect.

`wrapCases` (`host/wrap-cases.nix`) is the **fourth kind**: its subject is the
*composition* — the shipped wrapper built against a fixture, around a stub that
prints its environment — and it asks whether a value the caller set survives.
Reach for that shape whenever behaviour depends on something wrapped *around* a
program rather than inside it. To read a live one, grep
`/run/current-system/sw/bin/<prog>`: the one time that is the right move rather
than the trap in [[mem.fact.oubliette.module-programs-on-path-are-wrappers]].
