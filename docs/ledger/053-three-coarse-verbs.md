# NOTES item 53 — three coarse verbs, and the words that must not enter them

*State: **all four questions decided; the first prerequisite is built and green,
and so is the gap below.**
`capsule <slot> fetch` now answers for the code and state halves separately and
prints the archive that unblocks a refusal, which is
[item 50](./050-a-quarantine-outlives-its-assignment.md)'s third finding and the
half of decision 3 a human can run by hand — the automatic rename, and the three
verbs themselves, are still unbuilt. The interception `setup)` did not have is
now `unitScope`, one function at four call sites, and the four steps a provision
is are `provisionSlot`, which `setup)` calls instead of repeating — so verb 1
works without spelling the token twice. Nine rounds in `policyCases`, four
mutations each red on its own rounds. Proposed the day the hand-run sequence failed
in production. doctrine drove `SL-251` in slot `d`, and the work was landed from
a collect four hours stale: three commits short of `d`'s head, so the review body
it had already committed never crossed, the reconcile re-derived the review
host-side under a second id, and the slice closed carrying two divergent reviews
of itself. Nothing refused, because nothing compares an exhibit against the guest
it came from. The sequence itself is right and was executed by hand end to end
that day, which is what makes this a composition item rather than a design one.*
One item of the [ledger](./index.md) — the number is the citation, and it never
moves.

## What was asked

Three things doctrine does to a capsule, on the happy path, each of which it
thinks of as one act:

1. push a unit of work to a capsule for implementation;
2. begin a second capsule's review of what the first produced;
3. accept the reviewed work into the repo the human works in.

Each is several verbs and a habit today. The habit is the part that failed.

## The failure this item is written from

`capsule <slot> fetch` moves what the last *collect* took, not what the guest
has now. Both figures are already printed — `capsule <slot> status` gives the
guest's head, `capsule <slot> branches` gives the quarantine's tip — and no verb
compares them, so a stale exhibit and a current one are indistinguishable at the
point somebody merges. Four hours of divergence cost a review body, its backlog
item, and a second review of the same code under a second id; both reviews are
real, neither is wrong, and reconciling them is now governance work that only
exists because of a missing comparison.

It is [item 50](./050-a-quarantine-outlives-its-assignment.md)'s neighbour and
not its instance: 50 is about a quarantine outliving the assignment that filled
it, this is about a quarantine *lagging* the guest that fills it. Same
observation underneath — **a quarantine is a snapshot, and nothing says how old
one is against its source.**

## The vocabulary question, which is already answered

The guinea-pig rule ([CLAUDE.md](../../CLAUDE.md)) is the first thing to apply,
and it costs nothing here because both target words already have generic homes:

- doctrine's **slice** is the assignment record's `unit` — a bounded opaque token
  that scopes a state path's hole ([item 32](./032-the-sideband-channel.md)),
  which is exactly what a slice id is to it.
- doctrine's **audit** is `purpose` — free text, displayed and never parsed
  ([contract-assignment.md](../contract-assignment.md)).

So no program learns `slice`, `audit`, `review` or `accept`. A verb named for
doctrine's workflow would be `target.nix` values arriving as code, which is the
smell the contract names.

## The three verbs

| the act | verb | composition |
| --- | --- | --- |
| push a unit for implementation | `capsule <slot> setup <ref> --unit <token> --purpose <text> --state-from-host` | record writes, then provision carrying the state half, inject, baseline |
| begin a second capsule on it | `capsule <dst> handoff <src> --purpose <text>` | collect `src` and verify, archive `dst`, provision `dst` at `src`'s tip carrying `--state <src>`, copy `src`'s `unit` |
| accept the result | `capsule <slot> land` | collect and verify, fetch into the target repo, report divergence |

Only the middle one is machinery that does not exist. The first is `setup` plus
two record writes it should have taken as arguments; the third is `collect &&
fetch` plus the comparison whose absence is this item.

`handoff` is the name to argue about, not the shape. What it means is *stand this
slot up on that slot's finished exhibit*, and the two candidates it beats are
`clone` — which is [Plan D](../plan-d-fleet.md) D4's word for a volume and means
something else — and anything naming what the second agent is for.

## What each verb must own

Every one of these is a rule some hand-run step supplied on the day, and a
composite that drops it is worse than the three commands it replaces, because a
habit that is written down is auditable and one that is compiled away is not.

- **Verify the exhibit against its guest.** Collect, then refuse unless the
  guest's head equals the quarantine's tip. This is the whole of the failure
  above, and it belongs to `handoff` and `land` alike — one reads the exhibit,
  the other ships it.
- **Archive before forcing.** `handoff`'s provision is a `--force` that discards
  the destination's branch. The force is correct and the *order* is what makes it
  safe: collect and fetch the destination first, so its history is in the human's
  repo under `refs/capsule/<dst>/…` before anything overwrites it. A force a
  human remembers is a force that is sometimes forgotten.
- **Clear the destination's stale stage ref, or refuse naming it.** A slot that
  has collected before holds `refs/capsule/state/<stage>` on its volume, which a
  provision does not touch, and the incoming state chain is rooted elsewhere — so
  the push is refused for a reason that reads as a bug ([item
  50](./050-a-quarantine-outlives-its-assignment.md) found the fast-forward half
  of the same fact).
- **Carry `unit`, require `purpose`.** The token is the source's and copying it
  is mechanical; the sentence is the human's and guessing it would be the front
  end deciding something nobody asked it to
  ([item 29](./029-the-record-is-front-end-written.md)).
- **One provision, carrying its state.** On a target whose refresh commits there
  is no moment after a provision when a brief can land
  ([item 47](./047-a-script-on-stdin-and-the-command-that-eats-it.md)), so the
  state half is a flag and never a second command.
- **`land` stops at refs.** Which branch a result belongs on, whether a closed
  unit reopens, and how two reviews reconcile are the target's governance. A
  `--branch <name>` argument is a value and is fine; a default branch name is
  `target.nix` leaking back ([item 36](./036-a-policy-is-selected-not-named.md)'s
  direction, one contract over).

## Where they live

The **front end**, in `host/cli.nix`, and not three new programs. It already
composes — `setup` is provision plus inject plus baseline — and composition there
is what keeps [item 20](./020-which-capsule-a-program-means.md) intact: the front
end reads this host's state to resolve slots, profiles, policies and tokens, and
the programs it calls read none of it. A `handoff` program would have to know
which slot is a source, which quarantine holds it and which record carries the
token, which is three readings of host state inside a thing that must not do one.

## The gap found while reading for this — **built**

`provision)`, `collect)` and `brief)` each filled `--unit` from the record when
the slot's document has a hole for one, and **`setup)` did not** — so `capsule
<slot> setup <ref> --state-from-host` reached the state snapshot with no token
and was refused, where the same flags on `provision` succeeded. Verb 1 did not
work without spelling the token twice.

The fix was not a fourth copy. Three call sites of one construction were already
one too many when step 6 of
[item 51](./051-the-target-in-four-store-paths.md) made the predicate a question
about a document; a fourth is the point at which it becomes a function. Two of
them, because the duplication had a second layer:

- **`unitScope <slot> <carrier> …argv`** is the interception, at all four call
  sites. It **prints** the two words rather than mutating argv, which is what
  lets a caller keep the argv it was handed — the record reads the ref that was
  *asked for*, and a flag prepended for the program's benefit would be recorded
  as the base a slot is pinned to. `carrier` is the argv word meaning *this
  invocation carries host-side state*: `--state-from-host` for a provision,
  `--from-host` for a brief, `-` for a collect, where it is unconditional. The
  three answers of `slotNeedsUnit` are unchanged and the document still decides.
- **`provisionSlot <slot> …argv`** is the four steps a provision *is* — scope,
  the profile it is taken under, the push, the record — because `setup` is a
  provision with two steps after it. `setup)` had its own copy of those four
  minus the scope, which is exactly how the drift arrived; it now calls this and
  reads the document `provisionSlot` leaves loaded for its baseline question.

Nine rounds in `policyCases`, over the fourth call site: a setup that carries
state is scoped from the record, one that carries none is not, an explicit
`--unit` wins and is not doubled, and a setup on a target with no hole is not
scoped even with a stale token on the record. Four mutations, each red on its own
rounds — carrier ignored, document predicate skipped, nothing ever prepended, and
an explicit flag not honoured. A fifth, dropping the array from the `work` call,
was **rejected by shellcheck before the suite ran**, which is the failure that
reads exactly like nothing went red (item 50 hit the same one).

Not built, and still verb 1's: `setup` does not yet take `--unit <token>` or
`--purpose <text>` as record writes of its own.

## The four questions, decided

### 1. `land` writes no branch unless it is handed a name

The default is refs and a report. `refs/capsule/<slot>/…` is the landing zone the
git channel already owns and a name no target's governance uses; a branch is a
name in the *target's* namespace, and choosing one is choosing which line the
result belongs on — which is the half of this arc that is not oubliette's
([item 18](./018-git-channel-direction.md)'s direction applies to naming as well
as to transport).

`--branch <name>` is permitted, because a name arriving as an argument is a
value. Two rules keep it a value: it **refuses an existing name** rather than
updating it — additive-only, so nothing a `land` does can lose a commit — and
there is **no default**, since a default branch name is `target.nix` leaking back
through a program ([item 28](./028-a-slot-has-no-default.md),
[36](./036-a-policy-is-selected-not-named.md)).

The report is the part that earns the verb, and it can be written without knowing
anything: **the target repo's current `HEAD`** is a fact about that repo rather
than a value of ours, so `land` prints the divergence against it — ahead/behind
counts and the conflicting paths a merge would produce — naming the branch it
found without ever having chosen it.

### 2. `handoff` refuses on a **modified tracked file**, and only that

"Dirty" is two classes with two different fates, and `host/state-snapshot.nix`
already separates them:

- **untracked-but-not-ignored** files are staged as *content* into the state tree
  (`scope = all`, which is what a capsule collect uses), so they travel and the
  destination really holds them;
- a **modified tracked** file cannot travel — it is in no code ref and no path
  list — so it is captured as `.capsule/dirty.diff`, and the header says exactly
  what that is: *a record of a worktree rather than part of one*.

So a handoff from a source with modified tracked files stands the second capsule
up on code its source has already moved past, with the difference present as a
diff nobody applied. That is the same class of trap as the stale exhibit this
item exists for — a plausible checkout nobody ever had — and it gets the same
answer: **refuse, naming the count and the remedy** (commit in the source, then
hand off).

The check is read **from the exhibit, not from the guest**: the state commit
carries `dirty:` in its message and the tree carries the diff blob, so `handoff`
decides from what it already fetched, needs no second round trip, and gives the
same verdict if the source goes down between the collect and the provision.
Untracked-only dirt is not a refusal — it travelled.

### 3. The archive is generation-keyed, in the human's repo, and item 50 is a prerequisite

`handoff` makes a **second assignment to a slot routine**, which is precisely the
motion [item 50](./050-a-quarantine-outlives-its-assignment.md) measured: the
collect's refspecs are forced, so a slot's new assignment overwrites the old
one's refs in its own quarantine, and the human's `fetch` is *unforced*, so the
code half is rejected while the state half fast-forwards and the repository ends
holding **assignment 1's code beside assignment 2's state** under names that say
they belong together. A composite that runs that sequence for you would produce
that outcome silently, on purpose, every time.

Both halves were observed again on the day this item was written, without
trying: `capsule e fetch` printed `! [rejected] refs/capsule/e/heads/work
(non-fast-forward)` and exited 1 having half-succeeded, and doctrine's checkout
was left holding `refs/capsule/e/heads/work` at the *first* assignment's head
beside `refs/capsule/e/state/implementation` at the *second* assignment's chain —
two names that claim to belong together, describing different assignments. Item
50 measured this from a deliberate reassignment; here it arrived as a side effect
of setting a capsule up.

So item 50's minimal half is a prerequisite of this item's middle verb, and the
shape it needs is the one 50 already identified — the `generation` the record
carries and nothing reads. Localised to the motion that needs it: before the
force, `handoff` **renames the destination's existing refs in the target repo**
to `refs/capsule/<dst>/gen/<n>/…`, reading `<n>` off the record it is about to
supersede. The front end does it because reading a record is a front end's job
([20](./020-which-capsule-a-program-means.md),
[29](./029-the-record-is-front-end-written.md)); the programs stay as they are.

**And the archive's destination is the repository, not the quarantine.** The
quarantine's copy of the superseded assignment is lost to the forced collect and
that is correct: a quarantine is what a capsule sent back, not a place state
lives ([item 42](./042-a-state-half-no-capsule-has-held.md)), so the durable
copy belongs where the human works. What stays open in 50 is retention *policy* —
whose the old generations are and when they go — which this decides nothing
about beyond giving them a name that does not collide.

### 4. The verify is a refusal, with no override, and it needs the guest up

Refusal, per the house style ([item 28](./028-a-slot-has-no-default.md)), and
specifically **no `--stale`**: an override for "I know the exhibit is behind" is
the remembered `--force` again, and the failure this item is written from is
exactly somebody believing an exhibit was current. The remedy is never a flag; it
is a collect, which the verb runs itself.

The corollary is a real constraint and is stated rather than discovered:
**`handoff` and `land` require the source capsule to be running**, because the
comparison is against the guest's own HEAD and there is nowhere else to get it.
A slot that has been stopped since its last collect cannot be verified — nothing
records what its head was at halt — so the refusal is *start it*, not *trust
what we have*. Whether a halt should record that head, which would make an
unverifiable slot verifiable, is a question for the record and not for these
verbs.

## What this still does not decide

- Retention policy for the generation-keyed archives above — item 50's, and
  untouched by naming them.
- Whether `capsule <slot> stop` should record the guest's head, which is what
  would let a stopped slot be handed off without starting it.
