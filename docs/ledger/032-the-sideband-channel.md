# NOTES item 32 — the sideband channel: state that is not a commit

*State: built, and run once against a live capsule; extraction is deliberately
still by hand.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What was asked

A capsule finished nine phases of doctrine's `SL-254` and `capsule-collect`
brought back exactly what it was built to bring back: `refs/heads/*`, one branch,
one sha. That is the *code*. It is not the result.

The rest of the result never gets committed, by construction rather than by
accident. doctrine's runtime tier — phase sheets, dispatch state, the boot
snapshot, research artefacts — is gitignored on purpose (its own storage rule:
authored is committed, runtime is disposable). Add to that whatever the agent
left uncommitted in the worktree, which for a capsule that reports `dirty yes` is
the material an auditor most wants to see, because it is the material nothing
else will ever record.

So the question is not "how do we copy some files out". It is: **a capsule's
result has two halves with different lifecycles, and only one of them is a
commit.** The other half needs a transport with the same integrity properties —
or the audit is reading bytes whose provenance is a `scp` invocation.

## The shape

A second, deliberately non-branch history in the same object store.

Git does not require a commit to be on a branch. A commit is a tree plus
metadata and it is durable as long as a ref keeps it reachable. So the sideband
gets its own ref namespace, guest-side:

    refs/capsule/state/<stage>

pointing at a commit whose tree contains only the declared sideband paths — no
source, no history, nothing the code refs already carry. It is built with a
**temporary index**:

    export GIT_INDEX_FILE=$(mktemp -u)
    git read-tree --empty
    git add -f -- <declared paths>
    tree=$(git write-tree)
    commit=$(git commit-tree "$tree" ${parent:+-p "$parent"} -m "…")
    git update-ref refs/capsule/state/<stage> "$commit"

The temporary index is the load-bearing part, not a nicety: the agent's real
index must never learn these paths. It is working in that checkout, and a
`git add -f` into its index is a booby trap that goes off as somebody else's
commit.

The commit message pins what the tree cannot say:

    capsule: a
    stage: implementation
    code-oid: <sha of the guest's HEAD>
    dirty: <count of porcelain lines>

`code-oid` is the whole point of doing this in git rather than in tar. The
sideband commit says *which code this state was the state of*. Chain the commits
(`-p` the previous stage) and a capsule's life leaves an immutable little
provenance record: what code an agent saw, what process state it saw, what it
produced.

Host-side, `capsule-collect` grows a second refspec, and both land in **one**
fetch:

    git fetch --no-tags --atomic "$guestRepo" \
      "+refs/heads/*:refs/capsule/$capsule/heads/*" \
      "+refs/capsule/state/*:refs/capsule/$capsule/state/*"

`--atomic` is not decoration: it buys the invariant that **nobody observes a
result commit without the capsule state that goes with it**. All refs move or
none do.

The refspec being host-authored is what keeps the whole thing sound, and it is
the same argument [item 18](./018-git-channel-direction.md) already made for
`--no-tags`: the guest chooses what is *in* its refs and never where they land.
Nothing about the guest's authority changes here. It could already write any
object it liked into its own repository.

## Why the guest-side program is pushed, not baked

It is a `writeText` pushed on stdin — `ssh … 'bash -s' < ${snapshot}` — exactly
as `host/observe.nix` is, and for its reasons plus one sharper one:

- it is **host-side policy about what leaves a capsule**, not part of what a
  capsule *is*;
- a copy left on a volume by an older build is drift nothing reports;
- and a capsule with a real workload in it **cannot be rebuilt without a
  restart**. The first capsule that needed this was thirteen hours into a
  nine-phase slice. A mechanism for getting state out that requires stopping the
  thing whose state you want is not a mechanism.

That last one generalises: anything the host wants to learn from or do inside a
*running* capsule has to arrive over the door, or it does not exist for the
capsule that needs it most.

## The allowlist, and why it is not "the ignored files"

`target.nix` gains `statePaths`, and it is a **small, explicit, host-declared
list**. Never "everything `.gitignore` covers": that set routinely holds
credentials, machine-local config, agent state and build caches. `git add -f`
over a `.gitignore` is a loaded gun pointed at whichever direction the list
happens to face.

Two things follow, and they are the guinea-pig rule
([CLAUDE.md](../../CLAUDE.md)) in its usual shape. The **capability** is *collect
declared out-of-band working-tree state alongside the code refs*; the **value**
is doctrine's list of paths. A second target supplies different paths, or omits
the field and gets a plain collect. No generic code learns what a phase sheet is.

Beside the declared paths the snapshot also takes **untracked-but-not-ignored**
files (`git ls-files -o --exclude-standard`) and a `.capsule/dirty.diff` blob of
`git diff HEAD`. Both are generic — "work the agent has not committed" is not a
doctrine concept — and both are exactly the class that a `refs/heads/*` collect
silently drops.

## The invariant the allowlist has to meet, and does not yet

The state half exists so an audit can read *the run*. That makes it an exhibit,
and an exhibit has a scope:

> **A collect brings back the out-of-band state of the work the capsule was
> assigned, and none that is not.**

Both failure directions are live today, and the second is the one that will bite.

**Too broad, by declaration.** `statePaths` names `.doctrine/state/slice` and
`.doctrine/dispatch` — every unit of work the checkout has ever held, not the one
being driven. The first run says so in its own figures: 1886 files and 18.6 MB
for a capsule driving one unit, with "dispatch bookkeeping for six slices" in the
tree. Surplus state in an exhibit is not merely noise; it is a second, older
answer to a question the exhibit is supposed to settle, and nothing marks which
answer belongs to this run.

`.doctrine/state/boot.md` was a sharper case of the same thing, and is the one
part of this already fixed: it is **dropped from `statePaths`**, because the
general rule is worth more than the file. **State a consumer regenerates per
checkout does not travel.** Delivering a foreign copy into a live tree is
delivering stale authority — the next tool to run there reads it as that tree's
own — and a path whose value is derived from the checkout it sits in is evidence
only in the capsule that made it.

The positive half is the reason dropping it costs nothing: **such state comes
back by being regenerated where it is needed, and that belongs to provisioning,
not to a collect.** The hook does not exist. There is a guest seed that creates
cache directories and links `guestConfig` files, and there is `baseline`, a
command run on demand — but nothing a target may declare as *the command that
runs in a fresh checkout once it exists*. That is the generic capability the rule
needs (value: `doctrine boot`), and until it lands, a tree that wants the
snapshot regenerates it by hand. Note the shape it shares with the state half of
provisioning, below: both are the inbound direction of this item, and neither is
built.

**Scoped in the wrong place.** The narrowing that made the first adoption correct
happened at *hand extraction* — an operator chose pathspecs — not at collect. So
the invariant currently holds in a pair of hands, which is the same observation
this item already makes about validation, one layer earlier: if `capsule-adopt`
is where the mode-and-prefix check becomes unskippable, the scope must not be
the one thing left for the operator to get right.

### Why the project cannot simply be asked

The obvious fix — let the project hand over a path list when it is assigned — is
exactly the fusion [item 25](./025-assignment-is-a-perimeter-verb.md) refuses,
applied to the sharpest control there is.
[contract-target.md](../contract-target.md) already predicts it: `statePaths`
"stops being harmless the moment assigning a project is a run-time verb, because
the project would then be naming its own perimeter". An allowlist of files read
out of a worktree with `.gitignore` deliberately bypassed is not a field a
project may write.

The shape that scopes the exhibit without moving that authority is item 25's own
split, one level down inside the field:

- the **policy** declares the allowlist as a *template* — paths that may contain
  one hole;
- the **assignment** fills the hole with an opaque **unit token**, validated
  host-side against `[A-Za-z0-9._-]+`: never a path, never a glob, no separator
  and no `..`, so it can name an instance and cannot widen a perimeter;
- a template with a hole and an assignment with no unit **refuses**
  ([item 28](./028-a-slot-has-no-default.md)'s rule), rather than degrading to
  the unscoped list — the broad collect is the failure being fixed, so it is the
  worst possible default.

The capability is *a policy path allowlist may be parameterised by one opaque
identifier the assignment carries*. The value is doctrine's
`.doctrine/state/slice/{unit}`. The guest program substitutes a token its own
host policy declared a place for, and never learns what a slice is — the review
challenge is a different template and a different token, not different code.

The residual this dissolves: narrowing at collect means `capsule-adopt` inherits
the scope for free, because the sideband tree does not contain what must not
land. One choke point, and no doctrine-shaped rule in the extractor.

## Namespace: siblings, not nesting

The quarantine's code refs move from `refs/capsule/<name>/*` to
`refs/capsule/<name>/heads/*`, so state can be its sibling at
`refs/capsule/<name>/state/*`.

Nesting state under the old layout would put `refs/capsule/a/state` beside
`refs/capsule/a/<branch>`, and a guest branch literally named `state` is then a
directory/file ref-lock collision — a loud failure rather than an escape, but a
failure the guest picks the timing of. One line now, while exactly one
quarantine exists on this host, versus a rename after N of them.

The cost is real and small: refs collected before this land at the old paths and
are simply stale. Delete them or leave them; nothing reads them by pattern.

## Considered and rejected

- **git notes.** Attractive because they are explicitly auxiliary metadata
  attached to a commit. Wrong shape: the payload is a filesystem tree of many
  evolving documents, and turning that into notes is fighting the tool. Notes
  also merge, which is the last thing wanted from an exhibit.
- **A stash.** It happens to be implemented as commits under a special ref, and
  that is all it has going for it — the tree structure and semantics are wrong,
  and depending on them is depending on an implementation detail.
- **A bundle.** A perfectly good envelope for a case where there is no object
  store at the far end. There is one at both ends here, so it is an extra
  envelope, an extra file on a disk, and an extra thing to name and reap.
- **tar / scp / rsync over the ssh channel.** The bytes would arrive. Nothing
  would say which commit they belong to, nothing would deduplicate across
  collects, nothing would fsck, and the exhibit would be a directory rather than
  a sha. `capsule-inject` is a push of opaque payloads *in* and is right to be
  one; this is a pull of an evolving tree *out*, and the asymmetry is that the
  outbound thing has provenance worth keeping.
- **`git add -f` into the guest's real index.** Contaminates a checkout an agent
  is working in. See above.
- **The guest pushing its own state.** That is the daemon
  [item 18](./018-git-channel-direction.md) deleted, re-proposed with a smaller
  payload. The host initiates both directions; a collect is one host action.

## What this does not buy yet

**Extraction is by hand, and that is where the security control belongs.** The
sideband tree is *guest-authored data*. `git archive … | tar -x` into an audit
worktree writes whatever the tree says — including paths outside the allowlist,
`..`, symlinks (mode `120000`) pointing anywhere the extracting user can write,
and gitlinks. Today the check is a human running

    git -C "$q" ls-tree -r --long <ref>

and reading it before extracting with explicit pathspecs. The program that makes
that check unskippable — `capsule-adopt <capsule> <worktree>`, validating modes
and prefixes and then archiving with pathspecs — is the obvious next piece and is
deliberately not in this commit: one hand adoption first, so the program is
written against what the job actually turned out to be.

**Provisioning has no state half.** `capsule-provision --state <ref>` pushing a
state commit *in*, and the guest seed materialising it through the same
validated extraction, is what closes the loop for a fresh audit capsule that must
see the implementation capsule's phase sheets. The ref name and the `-p` parent
are here to reserve it; nothing builds on the chain yet.

**A collect now writes to the guest.** It ssh's a script that creates one ref
under `refs/capsule/state/` and a temp file under the guest's `TMPDIR`. It never
touches the agent's index, worktree, branches or HEAD. `capsule-baseline` already
runs the target's whole build in there, so this is not a new kind of reach — but
it does mean a collect is no longer strictly read-only with respect to the
capsule, and a future reading of "collect" as an observation should not assume
otherwise.

**No figures.** What the tree costs, and what a second collect costs once the
objects are shared, are [probes.md](../probes.md)'s to hold and nothing has been
measured.

## The first run, and the two things it taught

Against capsule `a`, thirteen hours into doctrine's `SL-254`, with the guest
still running: the snapshot returned
`44f4d3005a952d4db2a3855a7336ae6075121352	18646642	1886` — 18.6 MB, 1886 files
— and said `no .doctrine/state/dispatch in this checkout — skipped`, which is a
declared path a *dispatch* run would have and this run did not. The fetch took
both refs in one atomic transaction, the code half at
`refs/capsule/a/heads/work` and the state at
`refs/capsule/a/state/implementation`. The phase sheets, the dispatch
bookkeeping for six slices, and a 921-byte `dirty.diff` all landed in the audit
worktree, and the guest was never stopped.

**A `..` in a symlink target is not the escape test.** 253 of the 1886 entries
are mode `120000` — doctrine mints a title-slug symlink beside every entity, so
they are ordinary tracked content — and one of them is
`.doctrine/slice/254/phases -> ../../state/slice/254/phases`, which is *inside*
the extraction root and load-bearing: it is how the slice's phase sheets are
reachable from the slice. A `capsule-adopt` that rejects any target containing
`..` would refuse the very tree this was built for. The real check is
**resolution within the extraction root**, plus a refusal of absolute targets
and gitlinks. Worth the hand adoption to find out: the naive rule was the one I
would have written.

**The module path does not pick up a rebuilt program.** `just collect a` on this
host ran `/run/current-system/sw/bin/capsule-collect` — the copy the NixOS module
installed, built from the flake as the host last evaluated it — so the first
`just collect` after this change collected the code half and nothing else,
silently correct and a version behind. The devshell's copy refuses on a module
host by design ([item 20](./020-which-capsule-a-program-means.md)), which leaves
a hand invocation of the built store path as the way to exercise a change before
the host is rebuilt. That is the same class as *`nix run`/devshell binaries are
store paths* in [CLAUDE.md](../../CLAUDE.md)'s gotchas, one layer further out,
and it is worth stating plainly: **on the module path, a change to a host
program is not live until the host is rebuilt.**
