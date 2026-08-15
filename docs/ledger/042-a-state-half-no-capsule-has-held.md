# NOTES item 42 — a state half no capsule has ever held

*State: **open, and hit.** Capsule `c` is being provisioned for doctrine's
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

**Where the objects go.** The snapshot builds a tree in a temporary index and
commits it; from a host origin the natural object store is the human's own
repository, and writing `refs/capsule/state/*` into the repo an agent is working
in is the contamination item 32 built the temporary index to avoid, one level
up. Building it directly into a quarantine — `GIT_DIR` there, `--work-tree` at
the checkout — keeps the human's repository untouched and is the first thing to
try, unmeasured.

**Which stage a host-authored commit lands at, and what it parents.** A chain
that starts on the host has no source capsule, so `implementation` is a default
somebody picked rather than a stage something was in. Item 35 reserved chaining
across stage names; this is the case that would want it, and it should not be
built to want it before the verb exists.

**Nothing is built and nothing is measured.** The figures for the collect side
are [probes.md](../probes.md)'s; a host-origin snapshot of the same unit has no
counterpart there and should get one, because the interesting number is not the
size — the paths are the same paths — but whether a checkout somebody is
actively working in produces a tree twice.
