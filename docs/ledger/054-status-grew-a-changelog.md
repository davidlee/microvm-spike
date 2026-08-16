# NOTES item 54 — status.md grew a changelog, and it grew where the commit stopped

*State: **resolved by construction.** status.md is 2463 → ~250 lines with four
named sections and a stated eviction rule for each; "Where it got to" and "Do not
re-derive these" are deleted rather than moved, and the commit-message discipline
that the changelog was standing in for is written into
[CLAUDE.md](../../CLAUDE.md). What is not resolved is whether the eviction rule
holds without a check — nothing enforces it, and the thing it replaces took
fourteen sessions to reach 2463 lines.*

## What was found

[docs/index.md](../index.md) says, and said throughout: *"There is no changelog.
`git log` is the record, and the ledger's resolved items carry the reasoning a
changelog would lose."* status.md's first **720 lines** were a reverse-chronological
changelog of fourteen sessions, most recent first, and nothing had noticed
because it grew one entry at a time at the top of a file whose contract is the
present tense.

Four sections, four different lifetimes, one file:

| lines | share | section | lifetime |
| --- | --- | --- | --- |
| 1–720 | 29% | the changelog | one session |
| 721–1963 | 50% | "Where it got to", 50 bullets | closed work |
| 1964–2203 | 10% | "Next, in order" | mostly struck-through done steps |
| 2204–2445 | 10% | "Open" | ten of twenty-four struck as fixed |
| 2446–2463 | 1% | "Do not re-derive these" | duplicate, self-declared |

Only one of those lifetimes is the file's own.

**This is [item 15](./015-things-that-only-grow.md)'s third member**, and it is
the one that shows what that item is actually about. The volume and the proxy
log grow because a filesystem cannot return blocks — measured, given a rate,
accepted, and not arguable. This one grew because **nothing ever said what
leaves**, which costs a sentence to fix. Two kinds, one shape; check which kind
the next one is before accepting it.

## Why it grew there, which is the part worth keeping

**The changelog is the shadow of the commit message.** The house style was good
and is in the log:

```
7ffb71d doc: item 36 is built, and two contracts lose a field each
cd5dd2c fix: a teardown that only unnames, and the programs nothing built
7c7bfbd feat: two capsules on two policies at once, on a fabric that is nobody's
```

The last ten are item numbers — `053`, `053.2`, `052.3`, `51.6`, `docs`. And
**448 of the 720 changelog lines, 62%, are items 51, 52 and 53**: exactly the
window in which the messages degraded. Content has to land somewhere. When the
commit stopped taking it, the top of status.md did.

So the index's convention was not violated by an unwanted feature. It **stopped
being true**, and status.md compensated silently. The corollary is the general
one: *a discipline that is not enforced anywhere will be paid for in the nearest
file that has no size bound.*

The reduction found the same failure in flight. At the moment this item was
written, status.md's top entry described item 53's verb 1 in 28 lines of prose —
and that work was **uncommitted**. The file was the only record of it. It was
committed an hour later, as `053.4`, which is the pattern rather than a
counterexample: the prose stayed in status.md and the commit carried the number.

## Is a changelog worth anything to an agent?

That was the first question asked and the answer is *yes, and it is about fifteen
lines.* Three things an agent gets that neither `git log` nor a ledger item's
`*State:*` header gives it:

1. **Recency ordering with content.** [ledger/index.md](./index.md) is 54 rows
   with no time axis. The strongest prior for "what is half-built, what is likely
   broken" is *what moved this week*, and nothing else in the repo answers it.
2. **Cross-item sequencing** — which item unblocked which. A relation between two
   items cannot live in either one's header without both drifting.
3. **Negative evidence** — "nothing live was touched", "the verify has run in a
   sandbox and nowhere else". This is per-*session*, not per-item, so no item
   owns it. It is also the repo's own largest open seam (build / run / start /
   trigger / take, status.md's **Open**).

And three things it costs:

1. **It inverts the file's contract.** 720 lines of history in front of the
   present state. An agent reading top-down spends its budget on closed work; the
   section saying what is true now started 30% of the way in.
2. **A third copy drifts silently.** Item 53's `*State:*` header and status.md's
   opening were near-verbatim on the day both were written, and nothing kept them
   so.
3. **No eviction rule, so it only grew.** An entry's value is near zero once its
   item is closed and switched. Nothing removed one, ever.

So the answer is not "delete the changelog" and not "move it to its own file" —
a `docs/history.md` would formalise the thing the index forbids and would resume
growing the same afternoon. It is **bounded and evicting**: five entries, one
paragraph each, and the eviction rule written into the file so the next session
knows a sixth entry costs the oldest one.

## What was rejected

- **A `docs/history.md` or `docs/journal.md`.** Cheapest — zero triage — and it
  makes the convention false in a second file instead of one. The growth driver
  is the absence of an eviction rule, not the absence of a home.
- **Keeping "Where it got to" as a one-line-per-item table.** It would be a
  fourth copy of [ledger/index.md](./index.md)'s `state` column, which is the
  exact defect being fixed. 33 of its 50 bullets already cited the item that
  holds the reasoning.
- **Folding the 720 lines into their ledger items first.** Checked instead: all
  54 items carry a `*State:*` header, and the ones the changelog cites carry it
  at length. The prose was a copy, not an original.
- **A line ceiling on every doc.** [probes.md](../probes.md) is *supposed* to
  grow — figures accumulate and none of them expire — so a bound there would mean
  something different and would be wrong.

## What "Do not re-derive these" was

Eight lines that opened by naming where their long forms live. Every one was
checked to have another home before the section was deleted: five in
[CLAUDE.md](../../CLAUDE.md), and the forward-drop reading, the per-instance
kernel cmdline and the probe-methodology pair in Plan C's
[traps](../plan-c-implementation.md#traps-already-paid-for). Nothing moved,
because nothing needed to.

## What is still open

**Nothing enforces the bound.** A line ceiling on status.md in `just check` was
considered and is the obvious mechanical proxy — this repo's habit is to enforce
rather than ask ([item 38](./038-a-probe-that-became-a-borrower.md)'s
`borrowed` throw, the newline refusal in `serviceConfig`) — but the rule that
matters is *no past tense outside the five*, and a line count does not check it.
It is a proxy for a shape, and a proxy that can be satisfied by writing longer
lines. Left unenforced deliberately; if status.md is over 400 lines the next time
somebody looks, the proxy was worth having and this paragraph is the evidence.
