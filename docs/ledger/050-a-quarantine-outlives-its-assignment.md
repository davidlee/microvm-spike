# NOTES item 50 — a quarantine is keyed by a slot, and a slot outlives an assignment

*State: **the third finding is fixed and green; the key is still the slot.**
`capsule <slot> fetch` fetches the two ref namespaces separately and answers for
each on its own line, so the half that landed and the half that did not are both
named, and it prints the archive that unblocks it — `refs/capsule/<slot>/gen/<n>/`,
off the record's own generation — rather than the `+` that would make the first
assignment unreachable where it is durable. A sweep now runs every slot and fails
at the end, which `set -e` on a rejected fetch used to cut short wherever it had
got to. Six rounds in `policyCases`, built from two commits off one base and a
state chain that fast-forwards over them, because reaching it on a host costs two
assignments to one slot; three mutations, each red on its own rounds, and a fourth
was rejected by shellcheck before the suite ran — which reads exactly like nothing
went red. Run on this host against slot `e` both ways: `code: landed / state:
landed` on the current pair, and the refusal naming `refs/capsule/e/gen/7/` with
the divergent one restored under it. **What is not fixed is the key**: a slot's
second assignment still overwrites the first's refs in the quarantine, and the
archive above is a thing a human does after being told to, in the repository
rather than in the quarantine — which is the disposition
[item 53](./053-three-coarse-verbs.md) decided and made a prerequisite of its
`handoff`. Before that: **run, and the reading below it was half wrong.** Two assignments to slot
`e`, one quarantine: the **code** half behaved exactly as predicted — forced,
non-fast-forward, the first assignment's name gone and its commit left
unreachable — and the **state** half did not, because it was never forced at all.
It fast-forwarded, and it chains across the reprovision, because the parent it
takes is a ref on the **guest's own volume** that a provision does not touch. So
the two halves have opposite failure modes, the human's repository ends holding
one of each, and the archive nobody decided to keep turns out to already exist
somewhere this item was not looking. Moved here from
[Plan D](../plan-d-fleet.md) S10, where retention was one clause of a user story
and cited nothing.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What [item 42](./042-a-state-half-no-capsule-has-held.md) decided, and what it left

A quarantine is **what a capsule sent back** — not a place state lives. That was
the reading item 42 chose rather than inherited, and choosing it is why
`capsule-brief --from-host` keeps *no archive at all*: a host-authored tree has
nowhere in `collect/` to be, the snapshot's ref is dropped either side of the
delivery, and `briefCheckSpec` refuses any source that is not a declared slot.

That decision sharpens retention rather than settling it. If a quarantine were a
store, keeping it forever would be the point. It is an **artifact of one past
collect**, so it has a lifetime, and nothing in this repo says what that lifetime
is or who ends it. Today a retired slot's `collect/<slot>.git` is left behind,
nothing reaps it, and the only mechanism is a human noticing.

## The namespace is the slot's, not the assignment's — and what the run showed

Read from source:

- `host/quarantine.nix` keys both halves on the slot alone —
  `refs/capsule/<name>/heads` and `refs/capsule/<name>/state`.
- `host/git-channel.nix`'s collect fetches `+refs/heads/*` and
  `+refs/capsule/state/*` — **forced**, both of them, and `--atomic`.

A slot outlives an assignment: reprovisioning is a run-time verb costing seconds,
which is the one axis this design deliberately made cheap
([item 18](./018-git-channel-direction.md), Plan C item 2). So the second
assignment's collect lands in the first assignment's quarantine.

**Run, on slot `e`, two assignments and one quarantine**
([probes](../probes.md#two-assignments-one-quarantine)). Collect, reprovision at a
commit that is not a descendant, collect again:

    + 0ab546b6c...592168676 work -> refs/capsule/e/heads/work  (forced update)
      5225687a0..8b62ae0cb  refs/capsule/state/implementation -> refs/capsule/e/state/implementation

**The code half is what this item predicted.** The name is reassigned
non-fast-forward, and `git fsck` afterwards reports `unreachable commit
0ab546b6c…` — the object survives until something gcs it and nothing names it.

**The state half is not, and the error was reading a refspec as a description of
what happens.** `+` says the fetch *may* clobber; it says nothing about whether
it had to. It did not: `5225687a0..8b62ae0cb` is a **fast-forward**, because the
guest parents each snapshot on its own `refs/capsule/state/<stage>`, which lives
on the volume and which a provision — a forced push to `work` — does not touch.
So a reprovision resets the code and leaves the state ref exactly where it was,
and the next snapshot chains onto it.

Forcing is right *within* one assignment, and that is why this is a question
rather than a bug: a guest chooses its own ref names and the quarantine is a
mirror of what it sent, so refusing a non-fast-forward there would make a capsule
able to wedge its own channel. The question is whether **slot** is the right key,
and the record already carries the thing that would be a better one — a
`generation` integer, written and so far never read
([item 29](./029-the-record-is-front-end-written.md)). **It is now two questions
and not one**, because a generation in the ref name fixes the code half and does
nothing at all about the state half, whose divergence happens on the volume
before any refspec is consulted.

## The chain crosses assignments, and it is rooted in a commit this host wrote

The state ref after two collects is three commits deep, and the dates say who
wrote each one:

    8b62ae0cb  2026-08-15 17:03:58 +0000   collect 2   guest
    5225687a0  2026-08-15 17:03:29 +0000   collect 1   guest
    527596740  2026-08-16 01:00:37 +1000   root        this host

The root is `capsule e provision … --state-from-host` — the delivery
[item 47](./047-a-script-on-stdin-and-the-command-that-eats-it.md) made — and
every subsequent collect from that slot descends from it, across a reprovision
that was meant to end the assignment it belonged to.

So **[item 42](./042-a-state-half-no-capsule-has-held.md)'s own objection is
already true, one level down and in a place it was not looking.** *An accidental
chain is an archive nobody decided to keep* was the reason `--from-host` drops
its ref either side of a delivery, and it holds — on the host. The guest keeps
one, and that is where the state half's provenance actually accumulates: not in
`collect/`, which is a mirror, but on a volume, which nothing in this repo reads,
reaps or reports.

**The timezone is a free provenance signal and worth knowing.** `+1000` is this
host and `+0000` is a guest (CLAUDE.md's clock gotcha, pointed the useful way),
so the authorship of any state commit is legible without a tool. Not a control —
a guest can write whatever it likes — but a reliable *tell* when reading a chain
that was written by both sides.

## And the human's repository ends holding a pair that never existed

`capsule <slot> fetch` lands the quarantine's refs into the human's repo under
the *same* namespace — with the refspec `refs/capsule/*:refs/capsule/*`
(`host/cli.nix:798`), which is **unforced**. The collect's are forced and this one
is not, and nothing in either file mentions the other, so the two ends disagree by
construction. The second fetch:

    ! [rejected]           refs/capsule/e/heads/work -> …  (non-fast-forward)
      5225687a0..8b62ae0cb refs/capsule/e/state/implementation -> …

**So the human's repository keeps the first assignment's code beside the second
assignment's state, under two names that say they belong together.** That is
worse than the loss this item was written about: a missing ref is visible, and a
mismatched pair reads as a result. Nothing anywhere records that
`refs/capsule/e/heads/work` and `refs/capsule/e/state/implementation` are now
from different assignments, and `capsule e adopt` would lay the second one out
against a checkout provisioned from the first.

**And the verb reports it as a failure it does not name.** `capsule e fetch`
exits **1** — git's, from the rejected half — having *succeeded* at the other
half, with no line of its own about either. The `fetch)` loop in `host/cli.nix`
does not read that status, so `capsule all fetch` would print the same two lines
per slot and carry on. A partial fetch is exactly the shape
[item 41](./041-a-delegable-verb-that-ends-in-root.md) refuses elsewhere: two
things that must move together, one lock, and a failure defined to leave nothing
moved.

Whether a past assignment's result still exists is therefore a property of when
somebody happened to run a verb — and *which* halves of it exist is a property of
which fetches were rejected.

## Three things not to conflate — it was two before the run

- **Reaping** is policy: a human deciding an artifact is spent. It wants a verb
  and a refusal, not a schedule, and it deletes the only copy of what a capsule
  sent back once its slot has moved on.
- **Keying** is a name: whether one slot's successive assignments share a
  namespace at all. It is decidable now, costs a path component, and is
  retrofittable only while the number of quarantines on any host is small. It
  fixes the **code** half and nothing else.
- **The state ref's lifetime is the volume's**, and no key on the host reaches
  it. A snapshot parents on what the guest already has, so the question there is
  whether a provision should reset `refs/capsule/state/*` in the guest — which is
  a change to what a reprovision *means*, not to how a collect is named.

The first is what [Plan D](../plan-d-fleet.md) S10 noticed. The second is what
makes the first urgent, because a shared namespace means retention has already
been silently decided in one direction. The third is the one the run added, and
it is the only one that cannot be decided in `host/quarantine.nix`.

## Which verb the evidence covers

**Run**, and **taken** — the two verbs this item was short of. Slot `e`,
2026-08-16: `capsule e collect` (assignment 1, `work` `0ab546b6c`, state
`5225687a0`), `capsule e fetch`, `capsule e provision 582300f14 --force`
(assignment 2, refresh commit `592168676`, a **sibling** of `0ab546b6c` and
deliberately not a descendant), `capsule e collect`, `capsule e fetch`. Every ref
above is a reading of that run, and `fsck`'s `unreachable commit` is a reading of
the quarantine afterwards.

**Not built.** Nothing was changed by any of it: no key moved, no refspec, no
reap. What the run settles is which of the three things above is true, not which
of them to do.

**`c`'s quarantine was deliberately not spent on this.** It holds the c→d
migration's only copy of that assignment — code `18e35c2e5`, state `4a54b89f7` —
and `e` was already spent, so the experiment cost nothing that was not already
finished with.

## Related

[Item 15](./015-things-that-only-grow.md) is the other two things that only grow.
A quarantine differs from both: it is not capped by a declaration, and the reason
it grows is that somebody has to decide it is finished with.
