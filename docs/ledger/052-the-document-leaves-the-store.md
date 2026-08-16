# NOTES item 52 — the document leaves the store, and a pin becomes necessary

*State: **steps 1 and 2 built and green; step 3 owed.** Three decisions, all
taken — two of them were already taken elsewhere and this file says where rather
than re-taking them. The documents are out of the store and in a directory this
host owns, every predicate about a document is the reader's, and the render is
now a build that *runs* the reader. What is left is `profile_snapshot`: the pin,
which matters more after this commit than before it, because until now nothing
could edit a document at all.
[Item 51](./051-the-target-in-four-store-paths.md) made every host-side program
read the target's run-time half out of a document, and put that document in
`/nix/store` (its decision 2, explicitly "a store path first"). That bought one
reader and left one property unbought: **two targets are still a rebuild apart**,
which is the whole of what making a target run-time state was for
([Plan D](../plan-d-fleet.md) §6.1's controller that never runs
`nixos-rebuild`). This item moves the documents out, and it carries the two
things item 51 deliberately did not do — **step 5's `profileDir` pairing** and
**`profile_snapshot`** — because both become real in the same commit and neither
is real before it.*
One item of the [ledger](./index.md) — the number is the citation, and it never
moves.

## The coupling, in one sentence

`profileLoad` reads `<dir>/<name>.json` where `dir` defaults to a store path, so
adding a target is a `nix build` and a switch, and the document a program reads
is one no producer but nix can write.

That is a smaller coupling than item 51's and it is the last one of its shape:
item 51 took the target out of every *program*, and what is left is the target
being in the *closure*. A host that confines two projects still rebuilds to gain
the second, and a controller holding a fleet still needs nix on the box.

## What is already in place, so this is again a refactor

- **One reader, one lookup.** `profileLoad` is the only thing that opens a
  document and `profileDir` is the only thing that says where — bought at item 51
  step 3 for exactly this, so the switch is a change to one function's default
  and not to six programs.
- **`CAPSULE_PROFILE_DIR` already exists** and already wins over the baked
  default. Nothing needs a new knob; what it needs is a *legal second value*,
  which today it has not got.
- **The checks are all intra-document.** Item 51 step 3 found this and wrote it
  down as making the switch cheap: the eleven render-time checks compare a field
  against another field of the same document or against a shape, and not one of
  them needs anything nix knows. So none of them is *lost* by leaving the store —
  they move.
- **The record has the field, and the contract has already specified it.**
  `profile_snapshot` is written as an explicit `null` by `host/record.nix:128`,
  and [contract-assignment.md](../contract-assignment.md) says what it holds, why
  a digest alone will not do, and what the retention rule is. This item fills a
  field to a written spec rather than designing one.
- **`policyDir` is the standing precedent for the whole shape**: a directory of
  plain files, outside the store on purpose, so a change needs a proxy restart
  and not a rebuild (`host/services.nix`, [item 36](./036-a-policy-is-selected-not-named.md)).

## The decisions

**1. Where do the documents live, and what happens to one nix rendered?**

The fork is not "store or not" — that is settled by the item existing. It is what
a rebuild does to a document that is *already there*, and the two obvious answers
are both wrong:

- **Copy if absent** (tmpfiles `C`) makes an edit to `target.nix` invisible
  forever after the first boot. The document would then be a stale copy of a file
  the repo still presents as the source, which is
  [item 22](./022-secrets-at-start.md)'s write-if-absent payload rule applied to a
  *derived* payload — and Plan D §6.3 already names that as the thing to get right
  rather than repeat.
- **A symlink into the store** (`L+`) keeps nix authoritative and gives up the
  entire point: the target of the link is read-only and a controller cannot write
  it.

**Taken: a host-owned directory, and nix owns the names it renders.** `profileDir`
is a real directory (`/var/lib/capsule-profiles`), tmpfiles creates it, and the
module writes one document per target this host declares **at every activation**,
overwriting. A name nix does not render is nobody's but its writer's, and nix
never touches it. So:

- this host keeps authoring in nix and gets its build-time checks, which is
  §6.1's *"authoring in nix and rendering to JSON in a directory is what this host
  will do, because nix is what it has"*;
- a controller that never runs `nixos-rebuild` drops `otherproject.json` in beside
  it and every program reads it — §6.1's actual requirement;
- and the failure mode is bounded in the right direction. **This is why the
  document is not simply committed as a plain file and read back with
  `builtins.fromJSON`**, which would be one spelling instead of two and was the
  first shape considered: the guest image needs `name`, `guestPath`, `volumePath`,
  `cachePaths` and `sizes`, so a document nix reads is a document whose *syntax
  errors break the guest build*. A controller's bad write would then take out a
  rebuild of a project it has nothing to do with. Under the shape taken, a bad
  write breaks that document's readers and nothing else.

**What it costs, stated:** a document edited in place under this host's own target
name is reverted at the next activation, silently. That is the correct behaviour —
`target.nix` is the source and the file is a render — and it is also a trap, so
the render carries a first line saying so and `capsule all status` reads the
document rather than the nix value, which makes an out-of-date host visible
instead of assumed.

**2. Who validates, now that the writer may not be nix?**

Item 51 put eleven checks at render and seven at read. Once a document can arrive
from somewhere else, the eleven protect only the documents that did not need
protecting. Keeping both is two spellings of one predicate in two languages, and
this repo has already paid for that shape once
([item 38](./038-a-probe-that-became-a-borrower.md)).

**Taken: one implementation, in the reader, and the build runs the reader.** The
eleven move into `profileLoad` beside the seven, and the render becomes a
`runCommand` that emits the JSON **and executes the shipped fragment over it** —
which is `host/profile-cases.nix`'s own arrangement (splice the fragment into the
smallest `main` there is) turned from a test into a build step. Three properties
fall out and the third is the one worth having: nix's document is still checked
before it can be installed; a controller's document is checked too, which nothing
checked before; and there is one predicate, so the two cannot disagree.

The one check that does **not** move is the one nix can make and a reader cannot:
nothing compares a document to *the guest image the slot is running*. Item 51
named that as the sharp edge and left half of it open. Decision 3 is the other
half.

**3. What is `profile_snapshot`, and where do the bytes live?**

Already decided, in [contract-assignment.md](../contract-assignment.md): **the
bytes, retained, addressed by their digest**, because every one of `base.ref`,
`profile` and `extras` is *a name that re-resolves* and a digest detects the drift
it cannot undo. What this item settles is only the mechanism, and there is one
that adds no code:

**Taken: the bytes are a file in the slot's own directory, and pinning is a
`profileDir` choice.** At provision the front end copies the resolved document to
`<stateDir>/slot/<slot>/profile/<name>.json` and records its digest; every later
verb on that slot points `CAPSULE_PROFILE_DIR` at that directory. `profileLoad`
does not learn a second way to find bytes — which is the one property decision 2
of item 51 was bought to keep — because the second place it looks is *the same
place, named differently*. A re-provision re-pins. This is what makes the
edited-under-a-running-slot failure impossible rather than merely detectable, and
it is why the pin belongs in this commit and not the one before it: with the
documents in the store there was nothing that could edit one.

Consequences to accept, both of them from
[contract-assignment.md](../contract-assignment.md) rather than new:

- **A profile is pinned; a policy is live.** So editing a project's `baseline` or
  its caches does *not* change what a running capsule does until a verb re-pins
  it, while a tightened allowlist reaches it on a proxy restart. Two owners, two
  clocks — and now two directories, which is what makes the difference legible
  instead of asserted.
- **Retention is for the current assignment.** Superseded generations keep their
  bytes as provenance because bytes are small; nothing holds their images.

## Order of work

1. **Done. `profileDir` out of the store.** `host/services.nix` grows the option
   (`/var/lib/capsule-profiles`), the tmpfiles rule, an activation script that
   installs one document per declared target, and `CAPSULE_PROFILE_DIR` in `wrap`
   — which is **item 51 step 5**, owed and explicitly deferred to this commit. The
   directory has **one declaration and two consumers** (`profileDirOwner`), read
   by the tmpfiles rule that makes it at boot and the activation that fills it at
   switch, because two carefully-equal spellings are the thing that drifts.
   Read-only files in a writable directory: the *set* is a controller's to add to
   and each rendered document is nix's.

   The pairing item 51 asked for is
   [item 39](./039-a-bind-is-not-a-traversal.md)'s class, and it is **reuse rather
   than new machinery**: `hostModuleUnits` already pairs every `d` tmpfiles rule
   against each unit's `User` for bound paths, so declaring the rule is what wires
   it. The honest note stays — it is vacuous until a *unit* reads a profile, which
   none does, and an assertion with no failure mode is a round that never
   discriminates ([item 37](./037-a-teardown-that-only-unnames.md)).
2. **Done. The eleven checks moved, and the build runs the reader.**
   `host/profile.nix` splits into a **validator** (what a document is, takes a
   file) and a **locator** (where documents live, resolves a name to one). That
   seam is the whole of the switch — nothing in the validator moved — and it is
   also what makes the build-time check possible at all: a validator carrying a
   default directory would depend on the directory that running it produces.
3. **Owed. `profile_snapshot`.** The copy at provision, the digest, the pinned
   read, and a marker in `capsule all status` when the host's document has moved
   on from a slot's pin. `policyCases` is the suite — it already stubs
   `capsule-provision` and asserts what the record step *did*, which is exactly
   the seam this needs and is
   [item 51 step 6](./051-the-target-in-four-store-paths.md)'s own leftover paying
   for itself.

Steps 1 and 2 are one commit. Step 3 changes what a provision writes, so it is
its own commit and its own risk.

## What steps 1 and 2 turned out to be

**Three things came out of doing them that the scoping did not have.**

**The validator/locator split was not planned and is the best part.** It was
reached for to break a dependency cycle — `check` splices the validator, `dir` is
built by running `check`, and the locator names `dir` — and it turns out to be the
decomposition the file always wanted. *Validate a file* and *resolve a name to
one* are two responsibilities, and the plain-file switch touches only the second.

**One jq program, not a shell rule per line.** Every one of the eleven is a
predicate over JSON, so a shell implementation would read the two arrays back a
second time to ask. It is one `jq` producing the first failing reason or nothing,
wrapped in `try`/`catch` so a field of the wrong type is a refusal naming the
document rather than a stack trace. Two of the eleven stayed in shell because they
were already there and are about the *loaded* values: the ceiling pairing and the
three sizes.

**A twelfth rule appeared, and only this commit could need it.** A document is
addressed by its filename and also names itself. While every document was
rendered by `host/profile.nix` nothing could make those disagree; a producer that
is not nix can, and `foo.json` calling itself `bar` would have every program
report a target nobody named — item 51 decision 4's silent-wrong-target failure
arriving by another door. `profileLoad` refuses it, and it is the one check that
needs both halves.

## The evidence, and what it does not cover

`just check`, `just build`, `just units` green; **`just cases` 384** (was 369).
Three mutations against file copies of the fixed program:

- deleting the `guestPath`-derivation rule reddens **its two rounds and nothing
  else**;
- deleting the filename-vs-self-name check reddens **its three**;
- neutering the whole grammar (`| first // ""` → `| ""`) reddens **17**, and the
  shape of the 17 is the interesting part. Eight rules go fully red. The
  ceiling and the sizes stay green, correctly — they are the two that live in
  shell. And the newline rule goes red on its *reason only*: the document is
  still refused, by the `mapfile` count downstream, saying "holds a value with a
  newline in it, which cannot be read back". A suite asserting exit status alone
  would have called that one green. It is the clearest demonstration this repo
  has that a refusal for the wrong reason is a different program passing.

**Two things are built and not asserted, said plainly rather than covered by a
round that would not discriminate:**

- **That the render invokes the checker.** `check` is built and run by the suite,
  and `dir` is built; what nothing pins is the edge between them. Deleting the
  `${check}` line from `dir` reddens nothing. Every cheap pin considered was
  circular or fake — a marker file the same edit would remove, a build failure a
  build cannot assert. It is a five-line derivation and the deletion is visible.
- **That `wrap` exports the right directory.** Item 37's class turned up a third
  time on the way: `installed` in `flake.nix` forces the wrappers' outPaths and
  builds nothing, so `host/services.nix`'s `wrap` — five programs whose entire
  text is the environment this host's copies run with — **had never been
  shellchecked by anything**. `hostModulePrograms` now embeds their store paths,
  which builds them; that proves the wrapper parses and not that
  `CAPSULE_PROFILE_DIR` names the directory the module also creates. The same
  derivation gained the module's **activation scripts** for the same reason, and
  that one pays for itself twice: an activation script is in neither the unit
  graph nor `systemPackages`, and its text names the rendered directory, so
  including it makes the document a build input and `just build` renders it —
  which now means running the reader over it.

## What must not drift while this is being built

- **One reader, one lookup.** The whole cheapness of this item is that
  `profileLoad` is the only opener. A second way to get bytes — a flag taking a
  path, a record field parsed inline — is the thing to refuse, and decision 3 is
  written the way it is to avoid needing one.
- **No program probes for which target it means.** Pointing `CAPSULE_PROFILE_DIR`
  at a slot's pin is the **front end's** act, not a program's, exactly as
  resolving the *name* is ([item 20](./020-which-capsule-a-program-means.md), item
  51 decision 4). A program that looked for a pin would be choosing its own
  target.
- **The front end's printed shape is not a function of any target**
  ([item 51](./051-the-target-in-four-store-paths.md), decision 3). A drift marker
  is a column that is always printed, not one that appears when a host has two
  documents.
- **No control migrates into the profile.** The allowlist and
  `collectMaxPackBytes` are policies and stay policies; `stateMaxBytes` is the
  target's ([item 36](./036-a-policy-is-selected-not-named.md)). A directory a
  controller may write makes this sharper, not softer: if a control were in the
  profile, whoever may drop a document in would hold it.
- **The two shipped copies of the CLI stay one store path.** `host/cli.nix` is
  imported at three call sites and only stays one derivation while every argument
  agrees ([CLAUDE.md](../../CLAUDE.md)).

## Risk, and the smoke test

Steps 1 and 2 move the store paths of everything that reads a profile, and the
module path's copies gain an environment variable they did not have. Nothing is
live until a `~/flakes` switch, and **the failure to look for after one is a
program that cannot find a document it could find before**: the wrapper points at
`/var/lib/capsule-profiles`, which the activation fills, and if the activation has
not run the refusal reads `no profile named 'doctrine' in /var/lib/capsule-profiles`.
That is the right refusal and a confusing one, so the first thing to run after a
switch is `capsule all status` — a table with a `-` in every target-derived cell
is that failure, not an empty fleet.

The devshell path is untouched by design: its baked default is still this host's
store render, so `just`-anything keeps working with no environment and no root.

## What this closes, and what it does not

It closes item 51's stated limit: **two targets stop being a rebuild apart**, and
§6.1's controller becomes possible rather than merely designed for.

It does **not** make two targets concurrent, and the reason is unchanged and is
not in this item's reach: the guest **image** still knows the project's name.
`vm/capsule.nix`'s seed builds `guestPath` from the build-time half, so a second
target on this host is still a second image. That is Plan D §6.2's
assignment-driven seed, and it is the next thing after this one rather than part
of it.
