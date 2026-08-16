# NOTES item 53 — three coarse verbs, and the words that must not enter them

*State: **built and green — `handoff` and `land` are verbs of the front end, and
the archive before the force is automatic.**
Both compositions are branches of `host/cli.nix` and neither is a program, which
is what "Where they live" below decided. The order is the whole of them and every
step of it is a round: collect the source and **verify the exhibit against its
guest**, refuse on a modified tracked file read from the exhibit, fetch the
source, collect and fetch the **destination** and rename what it held under
`refs/capsule/<dst>/gen/<n>/`, drop the destination's own outbound chain, then
**one** provision carrying its state, then the source's `unit` and the human's
`purpose`. Before them, `capsule <slot> fetch` answers for the code and state
halves separately and prints the archive that unblocks a refusal
([item 50](./050-a-quarantine-outlives-its-assignment.md)'s third finding), and
the interception `setup)` did not have is `unitScope`, one function at four call
sites, with `provisionSlot` as the four steps a provision is. 80 rounds in
`policyCases` over the two verbs, nine mutations each red on its own rounds and a
tenth rejected by shellcheck before the suite ran. **The live fleet was not
touched**: the smoke test is the argv refusals, and the verify, the archive and
the drop have never run on a host. Still unbuilt and verb 1's: `setup --unit` and
`--purpose` as record writes of its own. Proposed the day the hand-run sequence failed
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

Only the middle one was machinery that did not exist. The first is `setup` plus
two record writes it should have taken as arguments — still the unbuilt piece;
the third is `collect && fetch` plus the comparison whose absence is this item.

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

## What the two verbs turned out to be — **built**

Two branches of `host/cli.nix` and no new store path, per "Where they live". The
work was mostly in what they are made *of*: a composition that spells a step
itself is a second copy of it, so `collect)` and `fetch)` became `collectSlot`
and `fetchSlot` and both verbs call those, beside `provisionSlot` from the gap
above. Three constructions are new — `verifyExhibit`, `exhibitDirty`,
`archiveRefs` — and each is one question.

**The order, which is the argument.** `handoff <src>`:

1. `collectSlot <src>`, then `verifyExhibit <src>` — the guest's head against the
   objectnames the quarantine's code refs hold. Membership rather than a named
   ref, because the branch a guest commits on is the guest's business
   ([item 18](./018-git-channel-direction.md)) and this file has never held its
   name.
2. `exhibitDirty <src>`, refusing on the count of files in `.capsule/dirty.diff`
   and naming the exhibit's own `dirty:` beside it, so the message says which
   half travelled.
3. `fetchSlot <src>` — because `capsule-provision` resolves its ref in the
   human's repo, so the tip has to be there to be pushed. A source whose refs in
   that repo diverge from its quarantine stops the verb with `fetch`'s own
   remedy: **the archive `handoff` runs is the destination's**, and a divergence
   somebody left behind is somebody's.
4. `collectSlot <dst>`, `fetchSlot <dst>`, `archiveRefs <dst>` — collect and
   fetch *first*, so the destination's last exhibit is in the repo before
   anything overwrites it, and the rename after, so the live names are **freed**.
   That second half is what stops item 50 recurring one assignment later: the
   next collect of the incoming work fetches into a name nothing is sitting on.
   One `update-ref --stdin` transaction, `create` and `delete` paired, so a
   generation that has already been archived is a refusal with nothing moved.
5. the destination's own `refs/capsule/state/*`, dropped by stage — the stages
   being the ones the collect at (4) just took, which is the guest's answer of
   seconds ago rather than a second round trip. A drop that fails stops the verb
   **before** the force, because the alternative is a push refused as a
   non-fast-forward, naming a cause that is not the cause.
6. `provisionSlot <dst> <tip> --force --state <src>`, once.
7. the source's `unit` copied, the human's `--purpose` written.

`land` is (1), (2) as a *report* rather than a refusal, (3), and then the
divergence against the repo's own `HEAD` — `rev-list --left-right --count` and
`merge-tree --write-tree --name-only`, naming the branch it found without ever
having chosen one. `--branch <name>` is `update-ref <ref> <oid> ""`, whose empty
old value is the create-only assertion; there is no default name.

**One value crossed a file boundary to get here.** The destination's chain is
`refs/capsule/state/<stage>` on its volume, which `host/state-snapshot.nix`
declares as `refPrefix` and `host/brief.nix` pushes into, so the front end takes
it as `stateRefPrefix` through `host/programs.nix` rather than spelling a fourth
copy.

### The seam, and what it does not pin

Every branch above sits downstream of one round trip to a guest, and
`pkgs.openssh` is in this program's `runtimeInputs`, so nothing in a sandbox can
stub `ssh` (CLAUDE.md). `guestControl` is therefore an argument with a default,
for exactly `proxyControl`'s reason one field up: it holds `guestHead` and
`guestDropState`, two functions because each call needs a *result*. It is not a
test-only artifact — `recordProvisioned` asks `guestHead` for the `base.oid` it
records, so the seam has two real callers and the question "what is this guest's
head" has one spelling.

What it does **not** pin is the ssh argv on the far side of those two, which is
the same boundary [item 41](./041-a-delegable-verb-that-ends-in-root.md)'s
seam leaves around its sudo rule and the reason `gitChannelCases` exists one
program over. Stated because the honest version of a seam is the list of what it
gave up.

### What the rounds cost, and one that passed for the wrong reason

80 rounds, `just cases` 405 → 485. Nine mutations, each red on its own rounds:
the verify's comparison, its silent-guest guard, counting untracked dirt as
tracked, no archive, `create` weakened to `update`, no drop of the chain, no
fetch of the source, a `--branch` that clobbers, and a `--purpose` that is
guessed. A tenth — `if false` around the purpose refusal — was **rejected by
shellcheck before the suite ran** (`SC2034: purposeGiven appears unused`), which
is the failure that reads exactly like nothing went red, and which items 50 and
51 both hit.

The purpose mutation is the one worth keeping: with it applied, the round's
**exit status still passed** — the run fell through to the verify, which refused
for its own reason — and only the assertions on the *message* went red. A
refusal for the wrong reason is a different program passing, and here it is,
caught by the rule rather than by the exit code.

## The four questions, decided

### 1. `land` writes no branch unless it is handed a name — **built**

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

### 2. `handoff` refuses on a **modified tracked file**, and only that — **built**

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

### 3. The archive is generation-keyed, in the human's repo, and item 50 is a prerequisite — **built**

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

### 4. The verify is a refusal, with no override, and it needs the guest up — **built**

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
  untouched by naming them or by writing them automatically.
- Whether `capsule <slot> stop` should record the guest's head, which is what
  would let a stopped slot be handed off without starting it.
- `setup --unit <token> --purpose <text>` as record writes of its own, which is
  the last unbuilt piece of verb 1. `unitScope` made the *scope* work; the two
  fields are still two more commands.
- What any of this does on a live host. The verify, the archive, the drop and the
  force have run in a sandbox and nowhere else — the smoke test spent was the
  argv refusals, because the fleet was driving `SL-251` in two slots and the
  cheapest live exercise of `handoff` is a reassignment. The first real one is a
  free slot handed a finished exhibit, and it should be watched rather than
  assumed.
