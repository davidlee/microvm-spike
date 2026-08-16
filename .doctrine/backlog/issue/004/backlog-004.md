# ISS-004: The module wrapper overrides the pin the front end just resolved

**The profile pin is inert for `collect`, `provision`, `brief` and `adopt` on the
module path — the only path a fleet uses.** `NOTES item 52` step 3's central
claim, that every verb after a provision reads the document that slot was
assigned under, is false as shipped.

## The mechanism

`host/cli.nix`'s `slotProfileName` resolves which directory a verb's bytes come
from and exports it:

```
dir=$(profileDirFor "$n" "$profileName")   # the slot's pin when it has one
export CAPSULE_PROFILE_DIR=$dir
```

It then execs `capsule-<verb>`. On the module path that is `host/services.nix`'s
`wrap` (line 177-188), whose text is:

```
export CAPSULE_PROFILE_DIR=${cfg.profileDir}
exec ${lib.getExe program} "$@"
```

An unconditional export, so the wrapper overwrites the front end's answer with
the host's directory on the last line before the program starts. The program's
own `profileDir()` (`host/profile.nix:338`) is written as an override —
`"''${CAPSULE_PROFILE_DIR:-${dir}}"` — and honours whatever it is handed; the
wrapper is what stops the front end from handing it anything.

## Why it is worse than a uniform override

`capsule-baseline` and `capsule-refresh` are wrapped **only** with `PATH`, so they
inherit the front end's export and *do* read the pin. `collect`, `provision`,
`brief`, `adopt` and the `capsule` front end itself get all five variables.

So on one slot, today: `capsule c baseline` reads the pinned document and
`capsule c collect` reads the host's. **Two verbs on one slot disagree about which
document that slot runs**, and nothing says so.

## Observed, 2026-08-17, on slot `c`

`c` was provisioned at generation 5 with `profile_snapshot: sha256:9e1e49e0…` and
a pin at `/var/lib/capsule/slot/c/profile/doctrine.json` holding
`stateMaxBytes: 67108864`. The host document was then edited to
`stateMaxBytes: 65536`.

- `capsule all status` printed `doctrine*` on `c` and on no other slot — correct,
  and it works because `profileCell` compares the two files directly rather than
  through the environment.
- `capsule c collect` reported `capsule-state: 732373 bytes of declared state,
  over the 65536 ceiling`, skipped the state half, and took the code refs. **The
  drifted host value governed a verb on a pinned slot.** The pin's own ceiling
  would have admitted it — the same exhibit collected fine minutes earlier.
- `grep '^export' /run/current-system/sw/bin/capsule-collect` line 12 is the
  override.

The failure this makes possible is the one the pin exists to prevent: a slot
provisioned under one document silently switches to a newer one at the next
`~/flakes` switch, and the marker that is supposed to warn about exactly that
prints `*` while the verbs have *already* moved. The marker is honest and the
behaviour it describes is inverted.

## The fix, and the general shape

`${CAPSULE_PROFILE_DIR:-${cfg.profileDir}}` in `wrap` — a default rather than an
assignment, matching what `profileDir()` already does one layer down.

**The same question applies to the other four variables, and one of them has a
written claim that is false.** `host/git-channel.nix:127-130` says of
`CAPSULE_REPO`: *"what the lookup replaced is the baked default, and the
environment still wins over both."* It does not win on the module path — the
wrapper sets it. `CAPSULE_STATE`, `CAPSULE_POLICY_DIR` and `CAPSULE_ALLOWLIST_DIR`
are the same shape and want the same reading before any of them is changed:
whether each is a *default the module supplies* or a *value the module imposes* is
a per-variable decision, and `CAPSULE_STATE`'s is not obviously the same as
`CAPSULE_PROFILE_DIR`'s (`mem.fact.oubliette.capsule-state-moves-the-quarantine-not-the-record`).

**A wrapper that hard-exports defeats any caller's deliberate override, including
the caller the module itself installs.** That is the finding worth keeping; the
pin is the instance that made it visible.

## What was already known, and what is new

Item 52 named the gap in the abstract and filed it as missing coverage: *"Not
covered, and unchanged from steps 1 and 2: nothing pins that the module's `wrap`
exports the directory the module also creates."* It was read as a test that had
not been written. It is a defect, and the missing test is why it shipped —
`hostModuleUnits` forces the module's programs and so proves the wrapper
evaluates, and `policyCases` runs the front end's text with stubs and so never
sees a wrapper at all. **Neither kind of check can see a wrapper defeating the
program it wraps**, which is a gap in the three kinds, not in one suite
(`CLAUDE.md`, and `mem.fact.oubliette.module-programs-on-path-are-wrappers` is the
reading trap that hid it — the wrapper is what you must read *here*, and grepping
one is the only way to see this).

Related: `RSK-004` is the neighbouring shape — two call sites, one construction —
and `CHR-003`, whose step 2 found this.

Evidence rung (`STD-001`): **taken**. The wrong document governed a real verb on a
real slot, and the override is readable in the installed wrapper.

## Where this stands — fixed in `4728425`, unverified on a live host

**The code is done and green; the evidence rung is back to `reasoned` until this
host is switched, which is why this needs `CHR-001`.**

`wrap` moved to `host/wrap.nix` and all five variables became
`''${VAR:-<default>}`. The per-variable split argued for above was considered
and rejected: it needs a defensible reason each and a maintained exception, and
both hazards it was for dissolve. `CAPSULE_STATE` already moves the quarantine
and not the record on the devshell path, so one rule makes that one behaviour
rather than a path-dependent one; an overridden `CAPSULE_ALLOWLIST_DIR` fails
**closed**, since the proxy unit takes its allowlist from `cfg.allowlistDir` at
build and no environment reaches it. **The module supplies defaults and imposes
nothing** — one sentence instead of a table.

`capsule-baseline` and `capsule-refresh` are wrapped now too. Being bare is what
made the defect visible, but run straight off `$PATH` they read the *store's*
baked documents rather than the ones this host renders, which is what item 52
moved out of the store. `capsule-inject` stays bare: it is not a `profileVerb`
and reads none of the five.

`host/git-channel.nix`'s claim that "the environment still wins over both" was
the false one named above, and is now true on both paths.

### The missing check is written, and it is a fourth kind

`wrapCases` (`host/wrap-cases.nix`, in `just cases` and `just build`) runs the
shipped wrapper — built against a fixture, the way the guard is built against a
stubbed kernel — around a stub that prints its environment. Its subject is the
**composition**, which is the thing neither of the other kinds can see, and
`CLAUDE.md` now says so where it used to say there were three.

Twenty cases: each variable's default, each variable's override, each variable
empty falling back, the exact set the wrapper supplies, argv crossing unsplit,
and a declared path with a space. Red first against `wrap` as it shipped — the
five override cases and the space one, and nothing else.

Then mutated four ways, which reshaped two cases and produced
`mem.fact.oubliette.assignment-context-does-not-word-split`: a fixture with a
space does not discriminate the escaping at all (assignment context is not
word-split, and `escapeShellArg` is a no-op on an ordinary path), so what pins
the count-of-one rule is escaping *twice*; and the honest `"$@"` mutation is one
**shellcheck rejects**, so it fails the build without running a case and reads
exactly like nothing going red.

### What is left

1. `just system-switch` (`CHR-001`, the human's).
2. Re-run the live proof, which is still set up: slot `c`'s host document is
   drifted to `stateMaxBytes: 65536` against a pin at `67108864` and a 732373-byte
   exhibit. **Before the switch** `capsule c collect` refuses the state half at
   the host's ceiling; **after** it must take it, because the pin admits it.
   Activation is the renderer, so the switch *removes the drift* — re-drift by
   hand first (`chmod u+w`, `jq '.stateMaxBytes = 65536'`, `cp` back, `chmod u-w`).
3. `capsule c baseline` and `capsule c collect` must now agree about which
   document `c` runs. That disagreement was the symptom and nothing yet observes
   its absence on a live slot.

## Observed on a live host, 2026-08-17 — evidence rung `taken`

This host is switched and carries the fix: `/run/current-system/sw/bin/capsule-collect`
line 8-12 is five `export V=''${V:-<default>}` lines, and `capsule-baseline` and
`capsule-refresh` now carry the same five while `capsule-inject` carries none.

The drift was re-applied by hand first, since activation is the renderer:
`/var/lib/capsule-profiles/doctrine.json` at `stateMaxBytes: 65536`
(`sha256:c9d0560c…`) against `c`'s pin at `67108864` (`sha256:9e1e49e0…`, which
is also its record's `profile_snapshot`).

- `capsule all status` → `doctrine*` on `c` and no other slot. Unchanged, and
  the marker is now describing something true.
- `capsule c collect` → **took the state half**: `state/implementation (unit
  251) 21c37b151 — 32 files, 732373 bytes`, pushed to
  `refs/capsule/c/state/implementation`. The same command refused that exhibit
  at the host's 65536 ceiling before the fix. **The pin governed the verb.**

**A trap on the way, and it is the recorded one.** The first three readings were
taken from the *devshell's* `capsule`, which shadows the module's inside this
checkout and is unwrapped — so its `hostProfileDir` is the store's baked
document, which matches the pin, and `capsule all status` printed a bare
`doctrine` with no drift marker at all. That reads exactly like the fix having
broken the marker. Run the module path's copy by absolute path from outside the
repo (`mem.fact.oubliette.devshell-programs-shadow-the-modules`).

**Not exercised:** `capsule c baseline` was not re-run. It read the pin before
the fix and reads it now through the same wrapper and the same default, and the
verb that was wrong is the one proven above — but the two-verbs-agree symptom has
not been observed *absent* on a live slot, only its cause removed. A full
baseline is a build in the guest on a slot that is driving work, which is not
worth spending here.
