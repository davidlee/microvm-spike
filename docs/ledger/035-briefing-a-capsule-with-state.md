# NOTES item 35 — briefing a capsule with another one's state

*State: built and **evaluated** — `just check`, `just build` and `just units`
green, so shellcheck-at-build has seen both new renders and `hostModuleUnits` has
forced the module's copy. The guest half's **logic is run and asserted at build
time** (`briefCases`, fourteen cases), and the suite was watched failing on two
deliberate mutations before it was kept. And it has now **run against two live
capsules** — 1884 files, 18.6 MB, slot `a`'s `implementation` state into slot
`b`'s checkout as step (2) of one provision, 1.14 s for the whole three-step
motion ([probes](../probes.md#what-the-sideband-arc-costs-end-to-end)).*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What was asked

[Item 32](./032-the-sideband-channel.md) built the outbound sideband and named
what it did not buy:

> **Provisioning has no state half.** `capsule-provision --state <ref>` pushing a
> state commit *in*, and the guest seed materialising it through the same
> validated extraction, is what closes the loop for a fresh audit capsule that
> must see the implementation capsule's phase sheets. The ref name and the `-p`
> parent are here to reserve it; nothing builds on the chain yet.

So the sideband had two of its three motions. `capsule-collect` takes a capsule's
out-of-band state out; `capsule-adopt` ([item 34](./034-adopting-a-guest-authored-tree.md))
lays it on this host's disk for a human. Neither of them puts it anywhere a
*second agent* can read it — and the case the whole thing was built for is one
agent auditing what another did, in its own capsule, with its own perimeter.

`capsule-brief <source>[:<stage>]` is that motion, and `capsule-provision
--state` is the same thing as step (2) of a provision.

## Where the validation runs, which was the open question

Item 34 left it explicitly undecided:

> what is not decided is whether the guest runs this text pushed on stdin … or
> whether the host validates before pushing and the guest only lays out. The
> second is the better shape — validation belongs where the policy is — and
> neither is built.

The host validates. The reason is one line long and it is not a preference: the
guest is the confined side, so a control that runs there is a control the
confined thing is in a position to not run. Nothing crosses the door that the
host has not already refused to send if it was refusable.

That decision is what turned item 34's check into a construction. It was eighty
lines inside `capsule-adopt`, which was then the only program that wrote a state
tree anywhere; it is now `host/exhibit.nix`, spliced into both. **Anything built
at two call sites needs one construction, not two careful ones**
([CLAUDE.md](../../CLAUDE.md)) — and this is the instance where the second copy
would have been the security control itself, which is the strongest form the rule
takes. Nothing about the check changed: `withinExhibit`, `readExhibit`,
`refuseExhibit`, the same three classes, the same depth counter.

## `code-oid` stops being a note

The commit message the outbound snapshot writes has always carried it, and item
32 called it the whole point of doing this in git rather than in tar. **Nothing
had ever read it.** This is the first thing that does, and it reads it as a
refusal: the guest compares `code-oid` against its own `HEAD` and refuses unless
they are the same commit.

That is not belt-and-braces, it is what makes the rest of the program defensible.
`git add -f -- <dir>` stages **worktree** content, so a state tree carries the
other agent's *uncommitted edits to tracked files* under `statePaths` — which is
exactly the material item 32 says an auditor most wants, and exactly the material
that has no meaning apart from the code it was an edit to. Laid over the same
commit it reproduces the worktree that existed. Laid over a different one it
composes a worktree that never existed anywhere, and the difference is invisible
to everything downstream.

The refusal also teaches the flow rather than merely denying it: collect the
source capsule, bring its code half into the target repo, provision the second
capsule at that commit, then brief. Three steps that were already the right ones
and that nothing had ever said out loud.

**No override**, for [item 28](./028-a-slot-has-no-default.md)'s reason and item
34's: a `--force` that the normal case needs is not a control. If a real case
ever wants old state against newer code, it wants a different verb and a stated
argument for why the result is readable.

## What a brief may overwrite, and what it may not

It overwrites tracked files, deliberately — see above, that is the content it
exists to move. It refuses a checkout with uncommitted changes to tracked files,
also deliberately, and the two are the same rule from opposite ends: **a brief
may replace the code's version of a file, and may never replace a person's.**
Immediately after a provision the second condition holds by construction, because
`receive.denyCurrentBranch = updateInstead` only lets a push land on a clean tree.
The visible cost is that a second brief onto an already-briefed capsule refuses,
which is correct and is asserted.

**`.capsule/` does not land on disk.** The state tree carries
`.capsule/dirty.diff`, and that path is *this system's* namespace inside a
target's tree rather than the target's own: it is a record **of** a worktree, not
part of one. Written into the checkout it becomes untracked content that the next
collect from this capsule picks up and carries again, as though this agent had
authored it — a small, self-sustaining contamination of exactly the exhibit the
sideband exists to keep clean. It is dropped from the index and not from the
tree, so the quarantine keeps it and `capsule <src> adopt` still hands it over.

## Three temporary indexes, one channel

The source guest builds the tree in a temporary index so its agent's index never
learns the paths ([item 32](./032-the-sideband-channel.md)); the host reads it
back through one ([item 34](./034-adopting-a-guest-authored-tree.md)); this
writes it through one. **No repository anywhere on this path has an index worth
contaminating**, and all three arrive at that the same way.

One trap on the third, and it is the one `host/state-snapshot.nix` orders itself
around at the other end: `GIT_INDEX_FILE` in the *environment* would make the
closing `git status` compare the worktree against the state tree and rewrite that
index on the way past — silently, with a plausible wrong answer. So it is named
per call (`gidx`) rather than exported, and the status that reports what the
brief made runs against the real index because nothing set otherwise.

## The order inside a provision

Push the code, materialise the state half, regenerate what neither may carry.
That is [item 33](./033-provision-is-a-sequence.md)'s reading of a provision with
its middle step filled in, and the order is load-bearing in one direction: a
refresh derives from the checkout, so a checkout missing half of what it is
supposed to hold derives from half of it — silently, and looking exactly like
state that was derived from all of it.

One interaction falls out and is worth stating rather than engineering away: a
target whose `refresh` **writes tracked files** cannot be briefed in the same
provision, because `capsule-refresh` refuses to commit onto a tree that was
already dirty and a brief is what dirtied it. The refusal is loud and names the
cause. doctrine is not that target — `doctrine boot` writes only its gitignored
runtime tier, so `$before = $after` and the branch is inert — and a target that
is wants a decision about which of the two outputs is the commit, which is not a
decision this program should make quietly.

## The seam that made the guest half testable

`host/brief.nix`'s `runner` is **a function of the checkout it runs in**, and
that is the same seam `host/guard.nix` takes its `tools` through and `perimeter/`
takes its fragments through. One text, two instantiations: the real one at
`target.guestPath`, and `briefCases`' at a throwaway checkout a build sandbox
makes.

It earns it on CLAUDE.md's own test — *the interesting branches are ones a live
host can only reach destructively*. Here they are a `code-oid` that does not
match and a worktree somebody else dirtied, and reaching those on a live host
means two capsules and a deliberate mess in one of them. Fourteen cases, in `just
build`, so a failing one is a failing build. Both halves of the rule were
honoured: each case asserts the *reason* and not only the status, and the suite
was watched failing — dropping the `.capsule` removal turns exactly one case red,
and neutering the `code-oid` comparison turns five red and leaves the rest green.

This is the second instance of the third kind of check here, and the pattern
generalises the way `guardCases` said it would: a host-authored program becomes
testable by taking as an argument the one thing that ties it to this host.

## Considered and rejected

- **The guest validating the tree it was pushed.** Item 34 listed it as the open
  alternative. It puts the control on the confined side, which is the invariant
  this repo is built on read backwards.
- **A `--force` for the `code-oid` mismatch.** See above; and item 34's own
  argument, that a flag the normal case passes is not a control.
- **Landing the tree in a sibling directory** — `/work/state/<src>-<stage>/` —
  so that nothing is ever overwritten. Safe, and useless: the target's own tools
  look for their runtime state at the paths the target declared, so an exhibit
  beside the checkout is one an agent has to be told about, by something that
  knows what a phase sheet is. That is the doctrine-shaped rule this whole arc
  keeps out of generic code.
- **Applying `.capsule/dirty.diff` as part of the brief.** It would make the
  destination worktree byte-identical to the source's, which is a real property
  and the obvious next thought. Rejected because it is a *second* kind of write
  with a different failure mode — a patch that does not apply — bundled into a
  verb that otherwise cannot half-succeed. The blob is in the exhibit and `git
  apply` is one command for a human who wants it.
- **Chaining the stages now.** An audit capsule collecting at `--stage audit`
  could take the implementation state it was briefed with as its parent, which is
  the provenance record item 32 described. The inbound commit lands at the source
  stage's ref, so a *same-stage* collect chains and a different-stage one does
  not; making it general is a `--after <stage>` on the outbound program, which is
  an outbound change inside an inbound item. Still reserved, now reachable.
- **Forcing the push into the guest's state ref.** A destination that has already
  collected at that stage has its own commit there, and overwriting one capsule's
  chain with another's is not something a flag should make easy.

## What this does not buy

~~**It has not run against two capsules.**~~ It has, and what the run found is a
sentence of this program's own that does not fit the target it was built for.
`b`'s worktree is **clean** afterwards and the program says so —
`differs from its HEAD in 0 paths` — because every path doctrine declares in
`statePaths` is gitignored, so the state tree and HEAD cannot differ unless a
project declares a path holding tracked content. The gloss beside the count
(*that difference is the other agent's uncommitted work, and it is the point*) is
therefore true of a target doctrine is not: slot `a` was dirty in exactly the way
the sentence imagines — one modified tracked file — and none of it reached `b`,
because a tracked-file edit travels only as the exhibit's `.capsule/dirty.diff`
and this drops that on purpose. Both halves are right and the pair reads as a
claim. **What an audit capsule gets from a brief is the runtime tier, not the
other agent's working copy**, and nothing in the arc says that out loud yet.

**The scope is still wrong, and this does not touch it either.** Item 32's live
invariant — *a collect brings back the out-of-band state of the work the capsule
was assigned, and none that is not* — fails by declaration, and a brief now
propagates whatever a collect over-collected into a *second* capsule. That is not
a new hole; it is the existing one acquiring a second reader, which is an argument
for narrowing at collect rather than an argument against this. The design is item
32's policy-template-plus-unit-token and nothing builds it.

~~**Nothing measures it.**~~ Measured, n=1: the whole three-step provision — push,
brief, refresh — is **1.14 s**, and a second collect of a state half the same size
is **0.48 s** because the quarantine already holds the blobs
([probes](../probes.md#what-the-sideband-arc-costs-end-to-end)). Nothing in the
arc is a bottleneck; it costs less than the ssh handshakes inside it. What stays
unmeasured is the case those figures are least like — a destination that shares
*few* objects with the source, which is what a brief across two different base
commits would be.
