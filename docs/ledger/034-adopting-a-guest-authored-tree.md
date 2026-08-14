# NOTES item 34 — adopting a guest-authored tree: what actually needed checking

*State: built and **evaluated** — the devshell built green on the host, so
`writeShellApplication`'s shellcheck ran on the real render rather than on a
hand-made copy of it. The **logic** is run and asserted against hand-built git
objects. Written in a jail with no `nix` and no `alejandra`, like
[item 33](./033-provision-is-a-sequence.md), so the eval was the human's; `just
build` (`hostModuleUnits`, `guardCases`, the module's copies), `alejandra` and a
run against a real capsule's exhibit are still owed.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What was asked

[Item 32](./032-the-sideband-channel.md) shipped the sideband channel and stopped
one step short, deliberately: extraction stayed a human running

    git -C "$q" ls-tree -r --long <ref>

and reading it before archiving with explicit pathspecs. The reason for stopping
was stated at the time — *one hand adoption first, so the program is written
against what the job actually turned out to be* — and it named what the program
would check: **modes and prefixes**, then `git archive` with pathspecs.

That adoption has happened. So this is the program, and the interesting half is
that it is not the program item 32 described.

## What the checks turned out to be

Three classes can hurt an extraction, and the first surprise is how differently
they are already covered.

**Paths — absolute, `..`, `.git` — are already refused, twice, and neither of
them is here.** `capsule-collect` fetches with `transfer.fsckObjects=true`, which
item 32 added for object integrity: *"index-pack parses guest-authored bytes
host-side whatever the transport."* It buys more than that. Both directions
measured against trees built with `git mktree`, which will happily make them:

    error: object cf40d15…: hasDotdot: contains '..'
    error: object 91965ff…: hasDotgit: contains '.git'
    fatal: fsck error in packed object → index-pack failed → exit 128

So a **collected** quarantine cannot contain the class at all. And `git
read-tree`, at the far end, refuses it again — `error: invalid path
'.git/hooks/post-checkout'`. The extractor's own path check is therefore a third
line, kept only because a quarantine is a directory and a human may have fetched
into one without that config. It says so where it stands.

**Modes half-matter, and the half that does is silent.** fsck passes a gitlink.
`checkout-index` then writes it as an **empty directory**, exit 0, no output —
evidence replaced by a plausible absence, which is the worst way for an exhibit
to lose something. Refused here and nowhere else.

**Symlink targets are the whole of it, and nothing anywhere checks them.**
`verify_path` bounds an entry's own path and says nothing about what a `120000`
blob *contains*; fsck passes `-> /etc/passwd` without a murmur; a checkout writes
the link without following it. Run against the hostile tree, item 32's own
predicted shape does this:

    $ git archive <ref> | tar -x -C naive     # exit 0, no output
    lrwxrwxrwx  absolute -> /etc/passwd
    lrwxrwxrwx  escape   -> ../../../../etc/passwd
    drwxr-xr-x  vendor/thing/                 # the gitlink

Nothing has escaped *yet*. The escape is the next thing that greps, copies,
opens or `cp -L`s the exhibit — which is exactly what an auditor does to it.

**So item 32 named one check that was already held and one that half-mattered,
and the check it *discovered*, by extracting a real tree by hand, is the one
nothing anywhere held.** That is the argument for the hand adoption, restated as
a result rather than as a policy.

## `..` is still not the test

The finding item 32 recorded stands, and it is what makes this hard rather than
obvious. 253 of the first real tree's 1886 entries are symlinks — doctrine mints
a title-slug symlink beside every entity — and one of them is

    .doctrine/slice/254/phases -> ../../state/slice/254/phases

which is *inside* the extraction root and load-bearing: it is how a slice's phase
sheets are reachable from the slice. A rule refusing any target containing `..`
refuses the very tree this was built for.

The test is **lexical resolution within the root**: combine the link's own
directory with its target, walk the components, and refuse only if the walk ever
goes above where it started. Against the tree, never against the filesystem —
the target does not exist yet, and `realpath` would answer a question about this
host instead.

Implemented as a **depth counter rather than a resolved path**, which is smaller
and is the whole answer: the question is whether the walk ever goes negative.

One property that is worth stating rather than leaving to be re-derived, because
it is what makes per-link checking sufficient: **a chain of contained links is
contained.** Each link resolves against its own position, so following a
contained link lands somewhere contained, and composing two of them cannot arrive
anywhere a single one could not. There is no need to iterate to a fixed point.

## Not archive-and-untar

The extraction is `read-tree` into a temporary index, then `checkout-index` out
of it — git's own hardened writer rather than a second one made of shell and
tar. It also gives the path check for free, as above.

The symmetry with the other end is worth seeing: the guest builds this tree in a
temporary index so the agent's real index never learns the paths
([item 32](./032-the-sideband-channel.md)), and the host reads it back through a
temporary index so no repository of ours learns them either. **Neither end has an
index worth contaminating**, and both get there the same way.

## The first program here with no transport

`capsule-adopt` needs to know *which* capsule it is for and has no business
reaching one: it reads a bare repository this host owns and writes a directory
this host names. That is not tidiness. Every transport fragment **refuses** when
there is no way in to the guest (`host/guest-ssh.nix`), and the capsule whose
exhibit is most worth adopting is a finished, stopped one — so a full transport
would make the program refuse in precisely its main case.

`host/guest-ssh.nix` says the two questions have one answer:

> It also owns *which* capsule a program is talking to, because that question and
> this one have the same answer.

They do not, and this is the counterexample. The fragment was already built in
two layers — `selectCapsule`, then `direct`/`viaSocket` over it — so the seam
existed and only had to be exported. Note what does *not* change: which capsule a
program means has never depended on how a host is shaped, only how it gets there
has, so `selectCapsule` is identical on both paths where `transport` is not.

**The first shape of this was wrong, and the eval said so within the hour.**
Passing `selectCapsule` as a second argument beside `transport` meant every call
site had a second thing to remember, and

    error: function 'anonymous lambda' called without required argument
    'selectCapsule' … host/programs.nix:23:1

arrived from a `direnv reload` — because there are **three** call sites, not two.
`probe-freshness` builds its own `nsPrograms` to exercise the real programs on
the real seam, and it is easy to forget precisely because it is not one of "the
two paths" every comment in this repo talks about.

So the fix is not a third careful call site. `direct` and `viaSocket` return the
**pair** — `{selectCapsule, transport}` — and `host/programs.nix` takes it as one
`access` argument, which cannot be half-passed. This is the third time this exact
class has been paid for here: `observe` added to one of `host/cli.nix`'s two call
sites cost a host rebuild, `hostModuleUnits` was extended to force the module's
programs because of it, and CLAUDE.md already carries the rule — *anything built
at two call sites needs one construction, not two careful ones*. The rule was
written for two. It is N.

The consolation is which check caught it: a missing argument is exactly what
forcing the eval finds, and it found it before a build, let alone a host.

## Two programs over one convention, so the convention is a construction

`capsule-collect` writes the quarantine and `capsule-adopt` reads it. Until the
second existed, where it lives was a `let` binding inside the git channel with a
comment saying not to spell it twice. That is the shape CLAUDE.md already names
from the `observe` rebuild: **anything built at two call sites needs one
construction, not two careful ones** — and a path convention is built at a call
site the same way a program is.

`host/quarantine.nix` is that construction: the `CAPSULE_ROOT`/`CAPSULE_STATE`
fragment, the repository path, the two ref prefixes, and the stage-name check.
It collapses two of the three copies. The third stays and has a reason —
`perimeter/default.nix` defines the same two variables and may not import
anything host-shaped, which is what keeps a seatbelt or VM shape able to reuse it
([plan-b](../plan-b-other-jails.md)).

The stage check came out of it and is worth a line: a stage name goes on the end
of a ref, so it is bounded to `[A-Za-z0-9._-]+` — deliberately the same bound
item 32 puts on an assignment's unit token, for the same reason. An opaque
identifier may name an instance and may never widen a perimeter.

## Empty or absent, and no `--force`

The obvious destination is the audit worktree the code half is checked out in,
and the state tree really does overlap one: doctrine declares `.doctrine/slice`,
which holds authored content as well as ignored research. So an over-the-top
adoption is an overwrite of tracked files with guest-authored ones, and deciding
which copy the auditor wanted is a judgement this program has no standing to
make.

It lays out an exhibit into an empty or absent directory and stops. Combining
that with anything is for the hand that has the context — the same narrowing item
32 made one layer up when it refused to let a project name its own allowlist, and
the same reason `capsule-refresh` will not commit a tree it did not find clean
([item 33](./033-provision-is-a-sequence.md)).

`--list` is the same program without the write, and it is what replaces the hand
`ls-tree`: the commit's own message (`stage`, `code-oid`, `dirty`), a count by
mode, the total bytes and the top-level names, printed **before** anything is
written whether or not `--list` was passed. The check is unskippable; looking at
it first is still free.

## What was run

Against hand-built git objects in a throwaway repository, not against a capsule.
Every assertion below is a real invocation.

- **A doctrine-shaped tree adopts, and the load-bearing symlink resolves after
  extraction** — a state commit built exactly as `host/state-snapshot.nix` builds
  one (temporary index, `.capsule/dirty.diff` blob, the same commit message
  fields), fetched into a bare quarantine, laid out; `cat
  <dest>/.doctrine/slice/254/phases/03.md` reads through the link.
- **A hostile tree refuses all five, and names each one** — `.git/hooks/…`,
  `absolute -> /etc/passwd`, `escape -> ../../../../etc/passwd`, a gitlink, and
  a `..` entry, with the one contained link (`-> ../state/slice`) passing.
  Nothing written.
- **The class fsck lets through refuses on its own** — a tree of just the two
  symlinks and the gitlink fetches cleanly *with* `transfer.fsckObjects=true` and
  is then refused 3 of 3. This is the case the program exists for.
- **The path class refuses at both other layers** — fsck at fetch
  (`hasDotdot`/`hasDotgit`), `read-tree` at extraction (`invalid path`).
- **`git archive | tar -x` plants all three**, exit 0, silent (above).
- Plus the ordinary refusals: a non-empty destination, an unknown stage (which
  lists the stages that do exist), and `--stage ../../heads/work`.
- **shellcheck clean** on the rendered program.

## What this does not buy

**It has not run on the host.** The devshell evaluates and builds, which is
shellcheck-at-build on the real render and is what caught the argument above —
but `just build` is more than that: `hostModuleUnits` forcing the *module's*
copies, and `guardCases`. `alejandra` has not run either, since this was written
where it does not exist.

**It has not been run against the real exhibit.** Slot `a`'s 1886 entries and
18.6 MB are the tree this was written from and it has never been fed to the
program — the figures above are item 32's, taken by hand. That run is the first
thing to do on the host, and `--list` is how to do it without writing anything.

**The scope is still wrong, and this does not touch it.** Item 32's live
invariant — *a collect brings back the out-of-band state of the work the capsule
was assigned, and none that is not* — fails by declaration: `statePaths` names
`.doctrine/state/slice` and `.doctrine/dispatch`, every unit of work the checkout
has ever held. Narrowing belongs at **collect**, via the policy-template and
assignment-carried unit token item 32 designed, and this item deliberately
inherits whatever that produces rather than growing a doctrine-shaped rule in the
extractor. What *is* now true is the other half of item 32's sentence: the
mode-and-prefix check is no longer the thing an operator has to remember, so
scope is the only thing left in a pair of hands.

**Step (2) is still blocked, but less.** `capsule-provision --state <ref>` —
pushing a state commit *in* and materialising it guest-side — wants this same
validated extraction, guest-side. The program now exists and its checks are
written down and exercised; what is not decided is whether the guest runs this
text pushed on stdin (`host/guest-exec.nix`'s non-login class, like `observe` and
`state-snapshot`) or whether the host validates before pushing and the guest only
lays out. The second is the better shape — validation belongs where the policy
is — and neither is built.

**A gitlink is refused rather than reported.** If a target ever legitimately
carries a submodule in its out-of-band state, this refuses its whole exhibit. No
target does; the refusal is the right default until one does, and the fix then is
a report, not a flag.

## Considered and rejected

- **Refusing any symlink target containing `..`.** The naive rule, and the one
  that would have been written blind. It refuses doctrine's own tree. See above —
  this is the finding the hand adoption bought.
- **`realpath`/`readlink -f` on the target.** Resolves against *this host's*
  filesystem, where the exhibit does not exist yet and where `/etc` does. Wrong
  question, and it answers it convincingly.
- **Iterating symlink resolution to a fixed point**, to catch chains. Unnecessary:
  per-link containment composes (above). Provable rather than tested is the right
  form for that one, since a test can only sample chains.
- **`git archive | tar -x` with pathspecs**, item 32's prediction. It writes what
  the tree says (measured, above), and the pathspecs would have had to encode the
  scope — which is the doctrine-shaped rule the extractor must not carry.
- **Extracting over the audit worktree, with `--force` for the overwrite.**
  Above: the overlap is real, so the flag would be the normal case rather than
  the exception, and a `--force` that everyone passes is not a control.
- **Validating with `git fsck` alone.** It is the fetch's check and it is
  genuinely load-bearing here — but it passes both classes that matter, so
  leaning on it is leaning on the half that was never the problem.
- **A `capsule adopt` that also checks out the code half** into the same
  directory, making one command produce the whole audit worktree. Attractive, and
  it fuses two halves with different lifecycles and different trust — the code
  half is a branch git already knows how to give you (`capsule <n> fetch`), and
  the state half is the thing that needs a program. One of them is not made safer
  by being bundled with the other.
