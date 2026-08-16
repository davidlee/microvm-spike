# NOTES item 45 — a brief is an origin, not a top-up

*State: **half answered.** The composite this item argued for is built and has run
— `capsule-provision --state-from-host`, delivered on slot `e` on 2026-08-16
([item 47](./047-a-script-on-stdin-and-the-command-that-eats-it.md),
[probes](../probes.md#the-delivery-and-what-a-provision-that-carries-its-own-state-costs))
— and item 47 supplied a second, sharper reason for it than this item's: on a
target whose refresh writes tracked files there is no moment *after* a provision
when a brief can land at all. **Still open: whether a top-up is a scoped additive
verb or a refusal**, which the delivery does not settle either way, since it
removes the window rather than serving a capsule already inside it.*

*Originally: **open, and hit before the verb it belongs to had ever run.** Capsule `c`
was two hours into doctrine's `SL-251` when the state half
[item 42](./042-a-state-half-no-capsule-has-held.md) exists to deliver turned out
to be missing from it. `capsule-brief --from-host` could not deliver it, for four
reasons that compound, and the fix was a hand `tar` over the door with no
`code-oid` binding — the shape item 42 rejected `rsync` for. The verb's delivery
half is **still unrun**: this event did not exercise it, it found the case it
cannot serve.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What happened

[Item 42](./042-a-state-half-no-capsule-has-held.md) was written from exactly this
situation and predicted it correctly: a capsule taking on a fresh unit needs
out-of-band state that has never been inside anything. On 2026-08-15 slot `c` was
provisioned at `de32c856b` for `SL-251`, an agent was started in it, and the
state half was not there. Two hours of work had happened by the time anyone
looked.

The gap was narrower than "no state", which is worth recording because the
reflex is to assume the whole tier is missing. `c` **had** the authored files —
`.doctrine/slice/251/{design.md,notes.md,plan.md,plan.toml,render-sample.md,slice-251.md,slice-251.toml}`,
byte-identical to the host's, because they are committed and rode in on the code
half. It **had** `.doctrine/state/slice/251/phases/`, seven empty sheets
regenerated in the guest by `doctrine boot` ([item
33](./033-provision-is-a-sequence.md)'s refresh, working as designed). What it
did not have was the ignored tier: `.doctrine/slice/251/research/` (92 KiB, five
files), `.doctrine/state/slice/251/design.toml` (234 KiB) and
`design-journal.toml` (2 KiB).

So the missing set was **exactly the paths a code push cannot carry**, which is
item 42's whole subject, and the parts that had arrived were the parts two other
mechanisms already covered.

## Why the verb could not deliver it, in four compounding steps

Each of these is correct behaviour. That is the finding: nothing here is a bug,
and the verb still cannot serve the case.

1. **`code-oid` refuses.** The host checkout was at `f49314de8`, two commits
   ahead of the guest's `de32c856b` (an ancestor, so no divergence). The
   host-side precheck compares the two and refuses. Fixable by detaching the
   human's checkout back to `de32c856b` — which is item 42's sequencing price
   paid backwards, and is survivable here only because the host tree was clean.
2. **The guest's checkout was dirty.** One tracked file modified:
   `.doctrine/slice/251/slice-251.toml`, a single line, the agent's own status
   bookkeeping. [Item 35](./035-briefing-a-capsule-with-state.md)'s rule — *a
   brief may replace the code's version of a file and never a person's* — refuses
   on exactly that.
3. **Had it not refused, it would have overwritten that line.** The file is
   under a declared `statePaths` directory, so it is inside the tree a brief lays
   out. The refusal in (2) is not incidental to this case; it is aimed at it.
4. **A brief is whole-tree.** It would also have rewritten `phases/`. That was
   harmless on the day only by luck — both sides held the same seven empty sheets
   — and stops being harmless the moment the agent writes phase-01, which it was
   doing while this was being read.

Note that (1) and (2) are individually escapable and jointly are not. Committing
the agent's edit clears (2) and moves the guest's HEAD off `de32c856b`, onto a
commit the host does not have; matching it would then require collecting `c`'s
code half and putting the human's checkout on a guest-authored commit. The window
in which a brief into a given capsule is possible is **the window before its
agent starts working**, and it closes on the first commit or the first edit to a
tracked file under a declared path.

## What was done instead, and what it cost

Host-initiated `tar` over the existing ssh door, scoped to the three absent
paths, with `-k` so the extractor would refuse rather than trust the listing:

```
tar -C ~/dev/doctrine -c .doctrine/slice/251/research \
    .doctrine/state/slice/251/design.toml \
    .doctrine/state/slice/251/design-journal.toml \
  | capsule c ssh 'tar -C /work/doctrine -xk'
```

Seven checksums matched either side, nothing was overwritten, and the guest's
checkout was unchanged afterwards — same HEAD, same one dirty file. It is
additive by construction: every path in it was absent in the guest, so no
composition of a worktree that never existed took place, which is the only reason
this was defensible at all.

What it cost is the binding. There is no `code-oid`, so nothing records which
commit that state was the state of, and nothing downstream can refuse it —
precisely the objection item 42 raised against `rsync or tar over the ssh
channel` and rejected the shape for. Doing it by hand does not make the objection
smaller; it makes it unrecorded. Hence this item.

It also went in over `capsule <name> ssh`, which takes argv rather than
interpolating text, so the `just ssh` quoting trap ([CLAUDE.md](../../CLAUDE.md))
did not apply. A recipe would have needed quoting.

## The decision this leaves open

**Whether a top-up is a verb or a refusal.** Two readings, and they are not
compatible:

- **A refusal.** A brief is an *origin*: it composes a capsule's starting state,
  and composing state into a worktree an agent is mid-edit in is the same class
  of thing `code-oid` refuses one level up. Under this reading the answer is not
  a new verb but a better-timed one — and the fix for this event is that the
  brief should have happened before the agent was started, which nothing enforces
  and nothing reminds anyone of.
- **A scoped, additive verb.** What was actually needed was *deliver the paths
  this capsule does not have*, which is decidable without touching anything the
  agent wrote, and which the hand `tar` performed safely. Under this reading the
  missing thing is a `--only-absent` mode with the same validation and the same
  `code-oid` line, refusing on any path that already exists.

The first reading is cleaner and the second is what the day actually wanted. They
are separable in one respect worth noting: the additive verb is only safe because
*absence* is checkable, whereas a brief's ordinary job is replacement. A mode
that refuses on collision is not a weaker brief, it is a different operation
wearing its name — which is the argument for making it one, and against making it
a flag.

**This is the argument for `capsule-provision --state-from-host`**, which item 42
deliberately did not build ("build it if the delivery makes you want it, not
before"). The delivery makes you want it. Two separately retryable commands is
what a *step of a sequence* wants, and this is a sequence whose second step is
easy to forget and impossible to take late — which is the case for the composite
command rather than against it. It does not replace the two-command form; it
removes the window.

## What this event is *not* evidence of

`capsule-brief --from-host` remains **unrun past the snapshot**. Nothing here
pushed, laid out a tree, or reached `briefDeliver`'s exhibit checks. The
host-side `code-oid` precheck was not run either — the mismatch was established by
reading both HEADs by hand, not by taking the refusal. Item 42's delivery is owed
exactly as much as it was before this happened, and the slot it was going to be
taken on is now the slot that cannot host it: `c` is working, and re-provisioning
it would either be refused as a dirty push or move HEAD under a running agent.

That is items 37–44's question asked once more. *Which verb does the evidence
cover?* This covers **hit** — the case is real and arrived in the wild. It does
not cover **deliver**.

## Considered and rejected

- **Re-provision `c` at `f49314de8` and brief it**, which is what
  the handover note in force said to do, written when `c` was idle. A
  provision is a push into the live checkout: `updateInstead` refuses while the
  guest's worktree is dirty, and on a clean one it moves HEAD under the agent.
  The first is a wasted attempt and the second is the failure a capsule exists to
  prevent, performed by the host.
- **Detach the human's checkout to `de32c856b` and brief.** Clears (1) and leaves
  (2), (3) and (4). It also moves the checkout another process may be working in,
  which is the same crime one paragraph up with the roles swapped.
- **Commit the agent's edit in the guest first.** Clears (2) by making (1)
  unfixable: the guest's HEAD becomes a commit that exists nowhere else until it
  is collected.
- **Have the agent fetch it.** [Item 18](./018-git-channel-direction.md)'s
  inversion, re-proposed for the third time. The host initiates both directions.
