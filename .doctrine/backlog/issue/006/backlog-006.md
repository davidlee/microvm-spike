# ISS-006: A handoff refusal reports the whole dirty count as the untracked half

**The consolation line in `handoff`'s tracked-file refusal names a number that
counts the thing it is consoling you about.** Observed live on 2026-08-17 while
exercising `CHR-002`.

## The mechanism

`host/cli.nix:1742-1750` refuses a handoff whose source has modified *tracked*
files, and closes with:

```
  (Its uncommitted *untracked* work travelled as content: the
  exhibit's own count is $dirtyTotal.)
```

`exhibitDirty` (`host/cli.nix:1236`) sets the two counts from the exhibit:

- `dirtyTracked` — `grep -c '^diff --git '` over `.capsule/dirty.diff`, which
  `host/state-snapshot.nix:229` writes as `git diff HEAD`, so **tracked only**;
- `dirtyTotal` — the state commit's `dirty:` header, which
  `host/state-snapshot.nix:223` writes as `git status --porcelain | wc -l`, so
  **both classes**.

`exhibitDirty`'s own header says so in as many words. The message presents the
both-classes figure as the untracked one.

## What it says when it is wrong

- Untracked work is zero: the sentence asserts untracked work travelled, and
  gives a count that is entirely the tracked files being refused. **A gloss
  describing a case that did not happen** — `ISS-001`'s class.
- Both classes present: the count overstates the untracked half by exactly the
  number of files the refusal above it just named.

Only when `dirtyTracked` is 0 is the figure right, and that is the branch where
this message never prints.

## Observed, 2026-08-17, slot `d`

One tracked file modified in `d`'s guest (`README.md`), nothing untracked.
`capsule d collect` wrote `dirty: 1` with a `.capsule/dirty.diff` holding one
`diff --git`. `capsule f handoff d --purpose …` refused, correctly, and closed
with *"Its uncommitted **untracked** work travelled as content: the exhibit's
own count is 1."* There was no untracked work. The 1 is `README.md`.

## The fix

The untracked count is `dirtyTotal - dirtyTracked`, and the sentence belongs
only where that is greater than zero. Both numbers are already in scope at the
call site. A `*Cases` suite can pin it: `policy-cases.nix` already builds
exhibits with a chosen `dirty:` header and a chosen diff
(`host/policy-cases.nix:913-931`), so the three combinations — untracked only,
tracked only, both — are a fixture away and need no guest.

Message-only; nothing about what travels changes.

Evidence rung (`STD-001`): the wrong sentence is **taken** on a live host, from
the run above. The fix is **none** — unwritten.
