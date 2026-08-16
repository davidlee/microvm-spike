# NOTES item 1 — what has actually been run, versus reviewed

*State: **standing caveat, and the most productive one here.** The question
generalised: items 37–50 are one finding at nine depths, and the ladder below is
what to ask before recording anything as done.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Assume anything documented in this repo but not named as *run* is reviewed
rather than run.** That was this item's whole content for fifty items. What
follows is what fifty items taught it.

## Ask which verb your evidence covers

Nine findings, each green everywhere anybody had looked, each found by asking a
narrower question than the last:

| item | what was missing |
| --- | --- |
| [37](./037-a-teardown-that-only-unnames.md) | a program nothing **built** — no flake output named it, so shellcheck had never run |
| [38](./038-a-probe-that-became-a-borrower.md) | an assertion nothing **ran** |
| [39](./039-a-bind-is-not-a-traversal.md) | a unit nothing **started** |
| [40](./040-no-doors-is-not-the-other-shape.md) | a refusal nothing had **triggered** |
| [41](./041-a-delegable-verb-that-ends-in-root.md) | a branch nothing had **taken** |
| [43](./043-a-grant-that-was-present-and-inert.md) | a grant nothing had **exercised** |
| [44](./044-a-rule-matches-a-path-not-a-name.md) | a grant exercised against a command nobody had **compared** |
| [45](./045-a-brief-is-an-origin-not-a-top-up.md) | a case that arrived before the verb built for it could **serve** it |
| [47](./047-a-script-on-stdin-and-the-command-that-eats-it.md) | a *step of a program* nothing had ever **reached** — not a branch untaken but everything below one line, skipped in silence on every run this repo had ever done, while the run reported success |
| [50](./050-a-quarantine-outlives-its-assignment.md) | a conclusion nothing had **read back** — an item that reasoned correctly from a refspec and got the answer wrong, found only by running the two commands it had itself named |

**Before recording anything as done, ask which of build / run / start / trigger /
take / exercise / compare / reach / read back your evidence actually covers.**
The list is ordered by how easy each is to mistake for the one before it, and
[item 47](./047-a-script-on-stdin-and-the-command-that-eats-it.md) is the proof
that it does not bottom out at "branch": a program can be shipped, built,
shellchecked, started, and run daily, with most of its text never executed.

Two of these are worse than a plain gap, and are the reason this is a ladder
rather than a checklist. Item 41's *first* run passed on an accident of
environment — a warm sudo ticket — which is what a first run is least likely to
expose. And [item 39](./039-a-bind-is-not-a-traversal.md)'s unit had been
**switched, proven and asserted** and had never once come up: a control can be
correct in every artifact that describes it and never have started.

## Three instruments that lie, all earned

- **A refspec's `+` is a permission, not an account.** It says a fetch *may*
  clobber; it never says one did. Item 50 read `+refs/capsule/state/*`,
  concluded overwrite, and the actual fetch was a fast-forward — the forcing had
  nothing to engage on, because the divergence it reasoned about happens on a
  guest's volume one step earlier. **Read the fetch's own output, not the
  refspec.**
- **`sudo -n -l` is not evidence.** It printed a command back three times across
  items 43 and 44 and meant nothing each time: it answers *some rule permits
  this*, never *which matching line won*, and never *whether it would run free*.
  **Only a call answers about a call.**
- **A pairing is worth only what its two halves are independent.**
  `hostModuleUnits`' `unrestartable` was green through both of those faults
  because both sides of its question came from `host/services.nix` — it paired
  the module against itself, and the program issuing the command was never in
  it. There are four such pairings, and item 43's reads the *rendered*
  `security.sudo.configFile`, so it is vacuous in a standalone eval and fires
  only at a switch. Read [item 44](./044-a-rule-matches-a-path-not-a-name.md)
  before adding a fifth.

A fourth, of the same family, from the probes: **a conditional probe's total is
part of its verdict.** `probe-netns-egress` skips to 27 and still reads green;
33 is what says stage 2b ran. `probe-two-capsules` skips to 28, which is exactly
what runs 1 and 2 scored — so a vacuous run agrees with its own history. Read
the count, not the colour.

## What has actually been run

The guest boots and the agent works over ssh; the perimeter has been exercised
in both shapes — `capsule-host` in the devshell, and the units under dedicated
uids on Sleipnir ([item 11](./011-host-side-runs-as-you.md)), including the
guard's teardown against a live guest — though the unit path's git channel has
since stopped serving, and [item 18](./018-git-channel-direction.md) is why.
The fleet has run at N=2 through the module path, and a capsule six hours into a
unit of work has been handed whole to another slot.

**Not exercised**, and each is somebody's next step rather than a doubt: a
second host; a **second target repo** ([item 16](./016-target-agnostic.md)),
which is what three build-time-only refusals are waiting for; the VMM half of
[item 11](./011-host-side-runs-as-you.md); and the sideband arc's refusals —
[the arc has only ever run forwards](../status.md).
