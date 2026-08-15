# NOTES item 50 — a quarantine is keyed by a slot, and a slot outlives an assignment

*State: **open, and the sharper half is unhit.** Moved here from
[Plan D](../plan-d-fleet.md) S10, where retention was one clause of a user story
and cited nothing. The retention half is known and has been dealt with by hand;
the half underneath it is read from source and has never been reached by a run —
successive assignments to one slot share one quarantine and one ref namespace,
and both collect refspecs are forced.*
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

## The half nobody has reached: the namespace is the slot's, not the assignment's

Read from source rather than run:

- `host/quarantine.nix` keys both halves on the slot alone —
  `refs/capsule/<name>/heads` and `refs/capsule/<name>/state`.
- `host/git-channel.nix`'s collect fetches `+refs/heads/*` and
  `+refs/capsule/state/*` — **forced**, both of them, and `--atomic`.

A slot outlives an assignment: reprovisioning is a run-time verb costing seconds,
which is the one axis this design deliberately made cheap
([item 18](./018-git-channel-direction.md), Plan C item 2). So the second
assignment's collect lands in the first assignment's quarantine and **overwrites
its refs by name**, non-fast-forward included. The objects survive, unreferenced,
until something gcs them; the names that reach them do not.

Forcing is right *within* one assignment, and that is why this is a question
rather than a bug: a guest chooses its own ref names and the quarantine is a
mirror of what it sent, so refusing a non-fast-forward there would make a capsule
able to wedge its own channel. The question is whether **slot** is the right key,
and the record already carries the thing that would be a better one — a
`generation` integer, written and so far never read
([item 29](./029-the-record-is-front-end-written.md)).

## And the human's repository is the accidental archive

`capsule <slot> fetch` lands the quarantine's refs into the human's repo under
the *same* namespace. So a ref that a later collect overwrites in the quarantine
survives in `~/dev/<target>` if it was fetched before the overwrite, and does not
if it was not. Whether a past assignment's result still exists is therefore a
property of when somebody happened to run a verb.

That is item 42's own objection — *an accidental chain is an archive nobody
decided to keep* — pointed at a different object, and it is the reason to decide
this rather than to reap on a timer.

## Two things not to conflate

- **Reaping** is policy: a human deciding an artifact is spent. It wants a verb
  and a refusal, not a schedule, and it deletes the only copy of what a capsule
  sent back once its slot has moved on.
- **Keying** is a name: whether one slot's successive assignments share a
  namespace at all. It is decidable now, costs a path component, and is
  retrofittable only while the number of quarantines on any host is small.

The first is what [Plan D](../plan-d-fleet.md) S10 noticed. The second is what
makes the first urgent, because a shared namespace means retention has already
been silently decided in one direction.

## Which verb the evidence covers

**Read.** Nothing has collected twice across a reprovision of one slot and then
gone looking for the first result. That run is cheap and is the thing to do
before any of this is built: collect, reprovision, collect again, and read what
`refs/capsule/<slot>/heads/work` points at.

## Related

[Item 15](./015-things-that-only-grow.md) is the other two things that only grow.
A quarantine differs from both: it is not capped by a declaration, and the reason
it grows is that somebody has to decide it is finished with.
