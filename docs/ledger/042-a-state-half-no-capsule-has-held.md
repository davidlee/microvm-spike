# NOTES item 42 — a state half no capsule has ever held

*State: **decided and built; unrun against a guest.** `capsule-brief --from-host`
takes the state out of `target.path` with the same text a capsule runs and pushes
it in over the door a brief already had. The two decisions this item refused to
make on its own are made and are below. Measured on doctrine's live checkout for
`SL-251` — 30 entries, 554 KiB, the same tree twice
([probes](../probes.md#a-state-half-authored-on-this-host--the-origin-that-is-not-a-capsule)).
What has not happened is the delivery: slot `c` is provisioned at `de32c856b` and
this checkout is at `f49314de8`, so a brief refuses today and the sequencing below
is owed before it can land.*

*Originally: **open, and hit.** Capsule `c` is being provisioned for doctrine's
`SL-251`. That unit's out-of-band state — a research directory, phase sheets, a
symlink between them — exists only in the human's checkout, because no capsule
has ever driven `SL-251`. Every inbound motion this repo has reads from a
quarantine, and a quarantine exists only because some capsule was collected. So
there is nothing to brief from, and the paths are declared and correct.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What was asked

[Items 32–35](./032-the-sideband-channel.md) built the sideband arc and it is
whole in the direction it was built for: `capsule-collect` takes a capsule's
out-of-band state out, `capsule-adopt` lays it on this host's disk for a human,
`capsule-brief` puts it into a second capsule's checkout. The case that shaped
all three is one agent auditing what another did.

That is not the only case, and the other one arrives first. A capsule taking on
a *fresh* unit of work needs the state that unit already has — which is on the
host, in the checkout the human has been working in, and has never been inside
anything. `capsule-brief <source>[:<stage>]` cannot name it: `briefState`
resolves `refs/capsule/<source>/state/<stage>` inside a quarantine directory
(`host/brief.nix`, `host/quarantine.nix`), and both are artefacts of a collect.

So the missing thing is not the inverse of a brief. **A brief is already the
inbound direction; what it has not got is an origin that is not a capsule.**

The allowlist is the part that is already right, which is what makes this a
missing motion rather than a missing design. `target.nix`'s `statePaths` names
`.doctrine/state/slice/{unit}` and `.doctrine/slice/{unit}`, and the comment
beside the second one says `# research/ (ignored) and uncommitted authored
edits`. Those are exactly the paths a fresh capsule wants and exactly the paths
nothing can send it.

## The capability, and the value

The guinea-pig rule ([CLAUDE.md](../../CLAUDE.md)) applies as usual and resolves
easily here, because the hard half was done at collect. The **capability** is
*author a state tree from a checkout this host already has, and brief it in*.
The **value** is doctrine's — the same `statePaths` templates, the same `{unit}`
token, filled by the same assignment. A second target with a per-unit runtime
tier gets this for free and a target with no `statePaths` gets no verb, exactly
as it gets no `collect --unit` and no `baseline`.

And the seam it needs already exists for the third kind of check's sake.
`host/state-snapshot.nix`'s `snapshotFor` is **a function of the checkout it
runs in** — that is how `snapshotCases` runs the real text against a throwaway
checkout a build sandbox makes. A host origin is a third instantiation of one
text, at `target.path` instead of `target.guestPath`, and the alternative is a
second program that builds a state tree, which is the shape
[item 35](./035-briefing-a-capsule-with-state.md) refused when it moved the
exhibit checks into `host/exhibit.nix`: *anything built at two call sites needs
one construction, not two careful ones.*

## Three sentences that stop being true when the origin is a host

This is the reason to write the item rather than a TODO line. The snapshot's
text is reusable; some of the *reasoning* around it is not, and all three
failures are silent.

**"The agent's uncommitted work, and it is the point."** Item 32 takes
untracked-but-not-ignored files unscoped, on the ground that "work the agent has
not committed" is a generic notion and one agent in one capsule working on one
thing is what makes it sound. In the human's checkout that set is not one
agent's work in progress; it is whatever is lying around — another unit's
drafts, a scratch file, an editor's leavings. The premise that made it safe to
leave unscoped is a property of a capsule, and it does not travel with the
program.

**"What an audit capsule gets from a brief is the runtime tier, not the other
agent's working copy."** Item 35 established that against doctrine, because
every path doctrine declares is gitignored *in the guest's checkout*, so the
state tree cannot differ from HEAD. From a host origin the same `git add -f`
picks up the human's uncommitted edits to tracked authored files under
`.doctrine/slice/{unit}` — a design still being written, a plan mid-edit. That is
almost certainly what you want a fresh capsule to see. It is also the opposite of
what item 35's sentence says a brief carries, and nothing downstream would
notice.

**The ingestion bound guards a door this tree does not cross.** `policies.nix`
holds a per-policy bound on what the host will accept from any capsule, and
`stateMaxBytes` is the smell detector over `statePaths` — set against the
observation, in `target.nix`, that this repo's own `.doctrine/state` on the
human's host has grown a scratch directory three orders of magnitude past it. A
host-authored tree meets neither bound by construction, because neither sits on
its path. Which of the two should apply is a decision, not an oversight to fix
by reflex: one of them is about a confined thing's output and the other is about
a path list's blast radius, and only the second has any claim here.

## `code-oid` is a reading, not a claim — keep it that way

Item 35 made `code-oid` load-bearing: the guest refuses a brief unless its own
HEAD is the commit that state was the state of, because a worktree laid over a
different commit is one that never existed anywhere. The outbound snapshot can
write that field honestly because it runs in the guest, whose HEAD *is* the
assignment.

The human's HEAD is not. It moves while they work, and the capsule was
provisioned at a ref somebody chose. The tempting shape — pass the provisioned
commit in as `code-oid` so the brief lands — turns the field from a reading of
where the tree came from into an assertion that it came from somewhere, and the
control it feeds then passes on both the true and the false case.

So the host snapshot reads HEAD like the guest one does, and **the sequencing
constraint is the price**: provision the capsule at the commit the host checkout
is on, then snapshot, then brief. That is item 35's own three-step flow with the
first step's argument now pinned by the third, and the refusal that fires when it
is violated is the one already built.

## What exists today by hand, and whether it is a seam or a hole

Read from source and **not run**: `briefState` validates its source with
`checkToken` and then asks whether a quarantine directory exists at that name. It
never asks whether the name is a declared slot. So a state commit authored on the
host, written to `refs/capsule/<name>/state/<stage>` in a quarantine-shaped
directory, appears to be briefable today with no change to any program — and it
would be validated by `host/exhibit.nix` host-side like any other, since that
check is upstream of the push and does not care what wrote the tree.

That is either the seam this motion should be built on or a hole that wants
closing, and the two readings are not compatible. It is the seam if a quarantine
is *a place state lives*; it is a hole if a quarantine is *what a capsule sent
back*, in which case a host-authored ref in one is a forgery of provenance, and
the same `%B` parse that reads `code-oid` would read a `capsule:` line naming a
slot that never ran. Nothing decides this yet, and the decision belongs in the
same commit as the verb.

## Decided: a quarantine is what a capsule sent back, and this keeps no archive

Both readings above put a host-authored tree *somewhere*, and the third one does
not. **A capsule's exhibit is kept because it is evidence of what a confined
thing did; a tree authored here is evidence of nothing that is not still on this
host's disk**, and the checkout it was read from is the original. So there is no
quarantine, no second root beside `collect/`, and nothing to give a name to: the
snapshot's ref is dropped either side of the delivery and the objects it wrote
into the human's repository are unreferenced the moment it goes.

Deleting the ref *before* as well as after is not tidiness. A leftover from an
interrupted run would become the next commit's parent, and an accidental chain is
an archive nobody decided to keep.

That answers the question by removing its subject, and it pays for itself twice.
`collect/` keeps meaning exactly one thing, so the `%B`-parsed provenance line
this item imagined is unnecessary — and provenance carried in a commit message is
worth nothing against whoever can write the directory anyway, while a directory
that only a collect ever writes is structural. And the hole becomes cheap to
close rather than a thing to live with: `briefCheckSpec` now refuses a source
that is not a declared slot, which is eight lines and one threaded argument
because the *other* reading was rejected. Under that reading this same refusal
would have been the seam a host origin was built on.

The rejected shapes, for the record, are the two above and not a third:

- **A quarantine at a reserved name** (`collect/host.git`). Cheapest — no program
  changes at all, `capsule c brief host` works today. It makes `collect/` stop
  meaning "what a capsule sent back" with no diff to notice, which is the class
  items 37–44 are seven instances of, and it leaves a name convention as the only
  thing between a host tree and slot `a`'s exhibit.
- **A second root outside `collect/`.** Honest about provenance and costs a
  second path convention plus a second lookup arm in `briefState` — for an
  archive of something that is not evidence.

## Decided: the sweep is an argument, and a host origin takes nothing undeclared

The first of the three sentences above is the one that had to be answered in
code. Untracked-but-not-ignored travels unscoped from a capsule on the ground
that one agent in one capsule is working on one thing; **that premise is a
property of a capsule and does not travel with the program.** So `snapshotFor`'s
text gains a third positional argument — `all` or `declared` — with no default,
because the value a missing one would fall back to is the whole of somebody's
desk. One text, one store path, three instantiations, and the difference is in
argv exactly as `stage` and `unit` already are.

`declared` takes **no sweep at all** rather than a narrower one, which is worth
saying because the narrower one looks right: `git add -f` over a declared
directory already stages everything inside it, ignored files included, so a
sweep restricted to those paths adds nothing and an unrestricted one adds the
rest of the desk. The same pathspec bounds the two other whole-repo reads —
`dirty.diff` is a patch of the entire worktree, which from a capsule is one
agent's work and from here is every file this host has open, and the `dirty:`
count in the message is a reading of the same thing.

**Measured rather than reasoned**
([probes](../probes.md#a-state-half-authored-on-this-host--the-origin-that-is-not-a-capsule)):
the same checkout and unit is 30 entries at `declared` and 34 at `all`, and three
of the four extras were files a *different process* had written into the checkout
seconds earlier. The sentence fails on a desk in the most literal way available.

## The item's own first suggestion is wrong, and cheaply so

"Building it directly into a quarantine — `GIT_DIR` there, `--work-tree` at the
checkout — keeps the human's repository untouched and is the first thing to try."
It breaks the snapshot's **reads**, all of which precede the temporary index and
all of which need the real repository. A quarantine's HEAD is unborn, so with
`GIT_DIR` pointed at one, `git ls-files -o --exclude-standard` calls every
tracked file untracked and the snapshot takes the whole checkout — silently, with
`stateMaxBytes` catching the large case and nothing catching the small wrong one.
That is the same trap `host/state-snapshot.nix` already orders itself around one
level down, reappearing at the outer boundary.

The mechanism instead is the plain one: run the text in the checkout with normal
discovery, and drop the *ref* rather than diverting the writes. The objects are
garbage that `git gc` reaps, and the index — the contamination item 32 actually
guarded against — is never touched, because the snapshot builds in one of its
own.

## What is built

- `host/state-snapshot.nix`: the scope argument, and the reordering it forces —
  the declared-path substitution now runs *ahead* of the two whole-repo reads,
  since under `declared` they are asked about exactly those paths. Still ahead of
  `GIT_INDEX_FILE`, which is the ordering that is load-bearing.
- `host/brief.nix`: `briefDeliver`, which is everything downstream of *which
  commit and what code was it of* — validate, push, lay out — factored out of
  `briefState` so the two origins share it. That is `host/exhibit.nix`'s own rule
  applied again: the thing being factored is a security control.
- `host/brief.nix`: `briefHostState`, and `capsule-brief --from-host [--stage
  <name>] [--unit <token>]`. The flags belong to that origin — a capsule's stage
  rides its name and its unit is whatever the exhibit was collected under, both
  readings of a quarantine rather than choices — so naming them with a source is
  refused rather than ignored.
- `host/cli.nix`: `brief` intercepted the way `collect` is, to fill `--unit` from
  the slot's record. Only for `--from-host`: a brief *from a capsule* is already
  scoped, and re-scoping it here would be a second answer to a settled question.
- `host/programs.nix`: `capsules` threaded in for the one refusal that needs it,
  for `policies`' reason — three call sites, and a value each resolves separately
  is a value one of them can resolve differently.
- `host/brief.nix`: a **host-side `code-oid` precheck**, which is not a second
  copy of the control but a fix for an ordering this origin makes reachable.
  `briefDeliver` pushes before the guest speaks, because the guest needs the
  commit in order to lay it out. From a capsule that is harmless: a refused brief
  is retried with the *same* commit, so the ref stranded in the guest is the same
  object and the second push is a no-op. **A host origin mints a new root commit
  every run** — no archive, so no parent — so a refused attempt leaves a ref the
  retry cannot fast-forward, and the retry then fails naming a cause that is not
  the cause. One round trip ahead of the snapshot, so a mismatch writes nothing
  anywhere; the guest's own refusal stays the control, and HEAD moving between
  the two readings is exactly what the confined side is there to catch. Found by
  writing the recommended sequence down, before running it.
- Cases: `snapshotCases` 29 → **43** (both origins, the scope refusal, the desk
  that does not travel, the scoped diff and dirty count, and the pair where the
  same unit takes the desk from a capsule and nothing from a host);
  `briefCases` 14 → **23** (which names may be a source, through the fragment's
  own text via `briefSpecChecker`). Both watched going red on a mutation — the
  sweep made unconditional, and the slot check made vacuous.

## What is not built, deliberately

`capsule-provision --state-from-host`, the symmetry with `--state <capsule>`.
The sequencing is expressible as two commands today and each is separately
retryable, which is what a step of a sequence wants (`host/refresh.nix`'s own
reason). The seam is there — `briefHostState` is in the fragment
`capsule-provision` already splices — so it is an argument parse when somebody
wants it, and not a shape to decide in advance.

## Considered and rejected

- **rsync or tar over the ssh channel** — `TODO.md`'s "provisioning extras:
  rsync?", which is the nearest thing to a record of this item and names the
  wrong transport. Item 32 rejected it outbound because the exhibit would be a
  directory rather than a sha; inbound the provenance argument is weaker, but the
  `code-oid` control disappears entirely, and the extraction would need a second
  writer beside `host/exhibit.nix` — the security control being the thing built
  twice, which is precisely what item 35 refused.
- **`capsule-inject`.** It is already a host-initiated push of payloads *in*, so
  it looks like the answer. Wrong grain in both directions: each entry declares a
  host-side `produce` fragment in `setup.nix` and is written write-if-absent at
  every start, which is a credential's shape and not a unit's tree, and what
  lands is opaque bytes with nothing binding them to a commit.
- **Committing the research so the code half carries it.** This is asking the
  target to change its own storage rule to suit the jail. doctrine gitignores
  that tier deliberately — authored is committed, runtime is disposable — and a
  repo whose ignore rules are decided by what a capsule can transport is the
  coupling the guinea-pig rule exists to refuse.
- **Making it an unconditional step of every provision.** [Item
  28](./028-a-slot-has-no-default.md)'s rule: a fresh capsule that silently
  inherits whatever the human's checkout holds for a unit is worse than one that
  refuses to guess, and a provision that always briefs cannot express *this
  capsule starts clean*.
- **Letting the guest ask for it.** [Item 18](./018-git-channel-direction.md)'s
  inversion, re-proposed. The host initiates both directions.

## What this does not buy, and what is undecided

**Where the objects go.** ~~Building it directly into a quarantine — `GIT_DIR`
there, `--work-tree` at the checkout — keeps the human's repository untouched and
is the first thing to try, unmeasured.~~ **Wrong, and refuted in one command** —
see above. Settled the other way: the objects land in the human's repository and
become garbage when the ref is dropped.

**Which stage a host-authored commit lands at, and what it parents.** Still
open, and narrowed by the no-archive decision rather than answered by it: with
the ref dropped either side, a host-authored commit is always a **root** commit,
so it parents nothing and there is no chain to name. `implementation` remains a
default somebody picked rather than a stage something was in, now overridable
with `--stage`. Item 35 reserved chaining across stage names; this is still the
case that would want it, and it still should not be built to want it before the
verb has run.

**A brief's closing sentence is now two sentences.** Item 35 left `differs from
its HEAD in N paths — that difference is the other agent's uncommitted work` as a
wording problem, on the grounds that doctrine's declared paths are all gitignored
in a guest so the count is always 0. From a host origin it is not: the operator's
uncommitted edits to tracked files under `.doctrine/slice/{unit}` are exactly
what a fresh capsule should see. So the clause is an argument to `briefDeliver`
rather than a fixed string — the same count meaning two different things — and
item 35's own case is unchanged and still misleading in the way it says.

~~**Nothing is built and nothing is measured.**~~ Both are, bar the delivery:
[probes](../probes.md#a-state-half-authored-on-this-host--the-origin-that-is-not-a-capsule).
The interesting number was the last one, as predicted — a checkout with an editor
and an agent pointed at it produced the **same tree twice**.

**What no run has reached.** Everything past the snapshot: the push, the guest's
layout, and `briefDeliver`'s exhibit refusals against a host-authored tree. The
`code-oid` mismatch is reachable today and is worth taking deliberately — ~~`c` is
at `de32c856b` and the checkout at `f49314de8`~~ **not on `c`, which is working;
see [item 45](./045-a-brief-is-an-origin-not-a-top-up.md)** — but it now lands on
the **host** precheck rather than in the guest, which writes nothing and is the
point of having it.

**And the case arrived before the delivery did**
([item 45](./045-a-brief-is-an-origin-not-a-top-up.md)). `c` needed exactly this
state half and was two hours into the unit by the time anyone noticed, at which
point four refusals stand between the verb and the capsule and each of them is
correct. The window in which a brief is possible is the window before the agent
starts, which is the argument for `capsule-provision --state-from-host` that the
section above declined to make in advance — a step of a sequence that is easy to
forget and impossible to take late wants to be part of the step before it. The guest's own `code-oid` refusal stays unreached from this origin,
and can only be reached by HEAD moving mid-flight; that is the honest reading of
what the precheck cost, and it is worth the retry it stops poisoning.
