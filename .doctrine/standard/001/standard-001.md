# STD-001: Ask which verb your evidence covers

## Statement

**Before recording anything as done, name which of these your evidence actually
covers:**

    build → run → start → trigger → take → exercise → compare → reach → read back

The list is ordered by how easy each is to mistake for the one before it. Say the
verb out loud in the commit message and in the completion note — *"shellchecked
and evaluated; never started"* is a finished piece of work, and *"done"* is not.

This is `required`, and it is deliberately finer than doctrine's three
verification modes. VT / VA / VH say **who or what** checks a claim; this ladder
says **what a check is worth**. A VT that only ever builds a derivation and a VT
that triggers the refusal it names are the same mode and different evidence.

The nine rungs, each earned by a finding that was green everywhere anyone had
looked (`NOTES item 1`):

| rung | what was missing | item |
| --- | --- | --- |
| **build** | a program nothing built — no flake output named it, so shellcheck had never run | 37 |
| **run** | an assertion nothing ran | 38 |
| **start** | a unit nothing started | 39 |
| **trigger** | a refusal nothing had triggered | 40 |
| **take** | a branch nothing had taken | 41 |
| **exercise** | a grant nothing had exercised | 43 |
| **compare** | a grant exercised against a command nobody had compared | 44 |
| **reach** | a *step of a program* nothing had reached — not a branch untaken, but everything below one line, skipped in silence on every run this repo had ever done, while the run reported success | 47 |
| **read back** | a conclusion nothing had read back — reasoning correctly from a refspec and getting the answer wrong, found only by running the two commands it had itself named | 50 |

It does not bottom out at "branch". Item 47 is the proof: a program can be
shipped, built, shellchecked, started and run daily with most of its text never
executed.

Two rungs are worse than a plain gap, which is why this is a ladder and not a
checklist. **A first run is the least likely to expose an accident of
environment** — item 41's passed on a warm sudo ticket. And **a control can be
correct in every artifact that describes it and never have started** — item 39's
unit had been switched, proven and asserted.

## Rationale

### Four instruments that lie, all earned

- **A refspec's `+` is a permission, not an account.** It says a fetch *may*
  clobber; never that one did. Item 50 read `+refs/capsule/state/*`, concluded
  overwrite, and the actual fetch was a fast-forward — the forcing had nothing to
  engage on. **Read the fetch's own output, not the refspec.**
- **`sudo -n -l` is not evidence.** It printed a command back three times across
  items 43 and 44 and meant nothing each time: it answers *some rule permits
  this*, never *which matching line won*, and never *whether it would run free*.
  **Only a call answers about a call.**
- **A pairing is worth only what its two halves are independent.**
  `hostModuleUnits`' `unrestartable` was green through both of those faults
  because both sides of its question came from `host/services.nix` — it paired
  the module against itself, and the program issuing the command was never in it.
  There are four such pairings, and item 43's reads the *rendered*
  `security.sudo.configFile`, so it is vacuous in a standalone eval and fires
  only at a switch. Read `NOTES item 44` before adding a fifth.
- **A conditional probe's total is part of its verdict.** `probe-netns-egress`
  skips to 27 and still reads green; 33 is what says stage 2b ran.
  `probe-two-capsules` skips to 28, which is exactly what runs 1 and 2 scored —
  so a vacuous run agrees with its own history. **Read the count, not the
  colour.**

### Why a ladder at all

Items 37–50 are one finding at nine depths. Every one of them was found by asking
a narrower question than the last, and every one was green in every artifact that
described it. The generalisation is that *green* is a claim about the check, not
about the thing — so the useful question is never "is it green" but "what would
still be green if this were broken".

## Scope

**Applies to** every completion claim in this repo: commit messages, an ADR's
Verification section, a backlog item's resolution, a slice phase's exit, and the
`*State:*` header of any archived ledger item that gets resolved in place.

**Also applies to** the standing assumption it replaces: *anything documented in
this repo but not named as run is reviewed rather than run.*

**Excluded**: nothing. A claim too small to name a rung is a claim that did not
need making.

## Verification

**VH** — read the commit message and the completion note. There is no mechanical
check and there probably cannot be one: the ladder's whole subject is the gap
between what a mechanism proves and what a human concludes from it.

The partial mechanical support that does exist, and what each rung of it buys:

- `just check` — parses and formats. Does not evaluate. **Below build.**
- `hostModuleUnits` — *forces* the module's derivations. Proves they evaluate.
  **Below build**: forcing is not building, and shellcheck is a build.
- `hostModulePrograms` — makes each `ExecStart`, activation script and wrapper a
  build input. **build.**
- the `*Cases` suites — run a shipped program's own text against a substitute for
  the one thing tying it to this host. **run**, and for the refusal cases,
  **trigger**.
- `probe/` — needs root and a live host. **start** and above, and the only thing
  here that reaches them.

Nothing in `just build` reaches *exercise*, *compare*, *reach* or *read back*.
Those are a human on a live host, which is why most of this repo's backlog is
chores that say "exercise X once".

## References

- `NOTES item 1` — the source, in the frozen ledger (`ADR-002`). Items 37–50 are
  the nine findings; 11, 16 and 18 are cited from its *what has actually been
  run* section.
- `ADR-002` — records this ladder as the piece this repo earned that doctrine
  could take back: nine rungs is finer than three modes, and the two axes are
  orthogonal.
- `CLAUDE.md` — *there are three kinds of check here, and they are not
  interchangeable*, which is the Verification section above stated operationally.
