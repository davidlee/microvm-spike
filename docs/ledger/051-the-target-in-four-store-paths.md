# NOTES item 51 — the four programs still spell the target, and it is item 20 one level up

*State: **steps 0-3 built and green; decisions 1 and 2 taken; 4-6 open, and only
step 6 still waits on a decision.** The run-time half of `target.nix` is a
rendered document now — `host/profile.nix`, per target, in the store, read
through one function — with a suite pinning both halves of it. **Nothing reads
it yet**, so no host program's store path has changed: that is step 4, and it is
the commit that moves the boundary. Before that: the
five guest-pushed scripts take every value they are about on their command line,
the two that had no case suite have one, and each of the seven suites was watched
going red against a deliberately broken copy of what it pins. The suites are then
out of `flake.nix` and beside what they pin, one file each, which halved that
file. All of it is
[Plan D](../plan-d-fleet.md) §6.4, which that
file names as **D7's first task rather than a detail of it** and says is worth
doing even if flavours never happen. Written up here rather than left as a
paragraph in a plan because the implementation will not fit one session, and a
plan is not a thing anyone hands over.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## The coupling, in one sentence

`host/programs.nix` builds every host-side program with `target.nix`'s values
**interpolated into their text**, so each program's store path is a function of
which project this host confines. One target makes that invisible. Two targets
make it four programs per target — which is exactly the bug that stood between
N=1 and N=2, where a socket path baked into a store path meant a program per
*capsule* ([item 20](./020-which-capsule-a-program-means.md)). The fix rhymes:
the values arrive at run time, the way `--capsule` already does, and one store
path goes on serving everything.

## What is baked, read from source

| value | source | store paths carrying it |
| --- | --- | --- |
| `guestPath` (`/work/doctrine`) | `name` + `volumePath` | `guestRepo` — so `capsule-provision` and `capsule-collect` — plus `observe`'s workdir, `capsule-baseline`'s workdir and `measure[0]`, `refresh`'s workdir, `brief`'s workdir, `snapshotFor`'s workdir |
| `path` (the host checkout) | `target.path` | `capsule-provision`'s `src` (`host/git-channel.nix:110`), `brief`'s `hostCheckout`, the front end's fetch (`host/cli.nix:797`) |
| `baseline`, `refresh` | command lines | `host/baseline.nix`, `host/refresh.nix` |
| `statePaths`, `stateMaxBytes` | `target` | `host/state-snapshot.nix` — **a script pushed into the guest**, so the text is the interface |
| `cachePaths`, `volumePath` | `caches`, `volumePath` | `capsule-baseline`'s `measure`, `observe`, `inject`'s payload destinations |
| `name`, `sizes` | `target` | the record's `profile` and `class` (`host/cli.nix:591`), the motd, `services.nix`'s `repo` default |
| `statePaths`' `{unit}` hole, as `stateNeedsUnit` | `statePaths` | the front end's **own** text — usage, the status table's `printf` format, its header and its row, and the `unit` verb's parser (`host/cli.nix:111,169,513,519,554,1069-1090`) |

The table is the inventory as read, and two of its names are gone: step 2 removed
`snapshotFor` and `refreshFor`, and the values in the guest-side column arrive on
a command line now (see *What steps 1 and 2 turned out to be*). Nothing else in
it has moved — the store paths still *carry* those values, because the host
program that spells the command line still gets them from `target.nix`.

Step 3 does not change a row of it either. Every value in the first five rows now
also exists in a document (`host/profile.nix`), but *also* is the operative word:
nothing reads that document, so the right-hand column is still the truth. Step 4
is what empties it.

`programVerbs` is the same coupling in its other form: which verbs exist at all
is decided at build time by which `target.nix` fields are non-null.

`stateNeedsUnit` is that form again and is the harder of the two, which is why it
has a row of its own rather than a mention. It is twelve `lib.optionalString`
sites in one file, and eleven of them are not a verb list — they are the shape of
the text the front end prints. **`capsule all status` prints one table for the
fleet**: one `printf` format, one header, every slot a row. A predicate that
becomes per-target makes that one header over two column sets, which is a
question about the front end rather than about the values, and it is not answered
below.

## The finding that changes the scope

**Detargeting subsumes [Plan D](../plan-d-fleet.md) D7's "the checkout goes at a
generic path" generalisation, and at none of its cost.** That bullet exists to get
a project's name out of the closure. A path that *arrives at run time* is not in
the closure either — so the relocation buys nothing the detargeting has not
already bought, while costing every existing volume its checkout, on a host where
a slot is holding live work. Do the values; leave `/work/<name>` where it is.

**The honest limit, so nobody reads this item as more than it is:** the guest
*image* still knows the project's name, because `vm/capsule.nix`'s seed creates
that directory. Getting it out of there is §6.2 — the seed becoming
assignment-driven — and is a different consequence with a different rebuild
class. This item is **the host programs only**, and finishing it does not make
two targets concurrent.

**And the sharp edge inside that limit.** `guestPath` has two producers today and
they cannot disagree, because one derives the other: `target.nix:30` builds it
and `vm/capsule.nix`'s seed creates exactly that directory from the same file.
The moment the host reads it from a document at run time, they *can* — a document
edited after a slot booted names a checkout the running image never made, and
every program that reaches for it gets a clean "no such directory" naming a path
that is plainly correct in the document it came from. Nothing proposed below
checks the agreement. Either the read is pinned to what the slot was built with
(which is what `profile_snapshot` is for, below) or something asserts it; a
document that is merely *later* is the failure this paragraph exists to name.

## What is already in place, so this is a refactor and not a design

Three things, and they are why the shape is obvious rather than inventive:

- **The record already carries the fields, including the one for the pin.**
  `host/cli.nix:591` writes `profile` (the target's name) and `class`
  (`mem`/`vcpu`) at every provision; both are written and read by nothing — inert
  fields waiting for this. The third is `profile_snapshot`, written as an
  explicit `null` by `host/record.nix:128` and already carrying the comment that
  says what it waits on: *a profile that is a document rather than a build-time
  literal*. So the pinning bullet below is not new machinery — it is filling a
  reserved field, and today's pin is the closure, which is stronger than a copied
  file and unusable by a controller that never runs nix.
- **`CAPSULE_REPO` is the precedent, already shipped.** `host/git-channel.nix:110`
  is `src="''${CAPSULE_REPO:-${target.path}}"`: a run-time override of a baked
  default, in the two places that read the host checkout. This item generalises
  that from an override to a lookup.
- **The guest-pushed scripts already take their subject as an argument**, because
  the case suites forced it: `snapshotFor <checkout>`, `refreshFor <command>`,
  `briefRunner`. That is the third kind of check
  ([CLAUDE.md](../../CLAUDE.md)) paying for itself in a direction it was not built
  for — the seam a test needed is the seam a run-time value needs.

## The decisions

Three, not one — and two of them gated step 3 rather than being taken during it.
Steps 1 and 2 needed none of them, which is why the order of work starts where it
does. **1 and 2 are taken and built; 3 is still open and now gates only step 6.**

**1. Is the profile document per target, or one for the host?** **Taken: per
target**, as recommended. `<dir>/<name>.json`, one document per project, and the
slot's record will name which — the shape `policyDir` had already paid for. The
grounds were that the interim saves an hour and the migration costs a day; what
building it added is that *the suite wanted it anyway*, since the claim the whole
item is about ("one reader, N targets") is only assertable with two documents in
one directory.

**2. Where does the document live, and who validates it?** Step 3 said *checked
at build for free*, and that is true only while nix is what renders it. The
precedent it cites cuts the other way: `policyDir` defaults into this checkout
(`host/services.nix:458`) and every allowlist under it is a plain file
deliberately outside the store, so that it can change without a rebuild — which
is exactly the property that means **nobody checks it**. Both halves cannot hold
at once and the item should not pretend otherwise:

- A **store path** keeps the build-time check and keeps two targets a rebuild
  apart. That is a smaller step than it sounds — the *programs* stop being a
  function of the target, which is this item's whole claim — but it does not
  reach §6.1's controller that never runs `nixos-rebuild`, and that limit belongs
  beside the guest-image one above rather than discovered at step 4.
- A **plain file** reaches it, and then a reader has to validate: the fields a
  program will index into, the `{unit}` hole's boundedness, and the paths' shape.
  That validator is work this item does not currently list.

**Taken: a store path first, read through one function**, so the plain-file
switch is a change of where that function looks rather than a change to every
caller. `profileLoad` is that function and `CAPSULE_PROFILE_DIR` is where it
looks — `CAPSULE_REPO`'s own shape, which is the precedent this generalises. The
limit stands and belongs here rather than at step 4: **this does not reach
§6.1's controller that never runs `nixos-rebuild`.** Two targets are still a
rebuild apart. What has stopped being a rebuild apart is the *programs*, which is
the item's claim.

**What building it settled that the decision did not, and it makes the plain-file
switch cheaper than this section assumed.** "Checked at build for free" is free
only in the sense that nix *runs* the check — somebody writes it, and there are
eleven now where there were none. But every one of them turned out to be
**intra-document**: they compare a field against another field of the same
document or against a shape, and not one of them needs anything nix knows. So a
plain file does not lose them, it re-runs them per invocation, and the switch is
transcribing eleven predicates into `profileLoad` beside the seven that are
already there. That is much less than "a validator this item does not list".

**What neither shape has is the check that matters most**, and naming it is worth
more than the eleven: nothing compares the document to *the guest image the slot
is actually running*. The render pins `guestPath` to `volumePath`/`name`, which
stops this file from disagreeing with itself; it cannot stop a document edited
after a slot booted from naming a checkout that image never made. That is the
sharp edge above, it is `profile_snapshot`'s job, and it is step 4's.

**3. What does a fleet-wide status table do with a per-target predicate?**
`stateNeedsUnit` shapes the front end's printed text, and `capsule all status` is
one table for every slot. Three answers exist — the union of columns with blanks
where a target has none, a table per target, or the column always present and
empty — and they are a front-end decision that outlives this item. It is named
here because step 6 reads as *one list of verbs* and it is not: the verb list is
the easy half. **Still not decided**, and the deferral held exactly as written:
step 3 is done and the predicate is still build-time, with every value around it
in a document. It now gates step 6 alone.

## What step 3 turned out to be

**A document nothing reads is a document nothing builds, so the suite is what
builds it.** `host/profile.nix` renders and validates; nothing consumes it until
step 4, which makes it precisely the shape of
[item 37](./037-a-teardown-that-only-unnames.md) — a thing named by no flake
output and reached by no unit. So `profileCases` loads the *shipped* document
from the *baked* directory as its first case, with no environment set, which is
what puts the render in `just build` at all. Everything after that is fixtures.

**The suite's subject is a library, and that is a first here.** The reader is a
shell fragment for [`host/record.nix`](../../host/record.nix)'s reason — the
programs that will call it are already separate store paths, and a profile
*program* would be one more thing to install that each of them would still have
to call. So the suite splices the fragment it was handed into the smallest `main`
there is (`profileLoad`, then `profileShow`) and reads that. One text, handed
down from `flake.nix`, not a second render.

**And `profileShow` is not only for the suite.** A library that sets eleven
variables inside a program that uses three of them is SC2034 a dozen times over,
and `writeShellApplication` fails a build on it. A function that prints all of
them makes every one referenced within the fragment, which is the honest fix
rather than a suppression — and it is also what a `capsule <slot> profile` verb
would print. (Cost, in passing: a comment whose first word is `shellcheck` is a
*directive* to it, and an unparseable directive is a build failure.)

**The render's own refusals are pinned at eval, because a throw is not a build.**
Eleven fixtures, each differing from a rendering target in exactly one thing,
run through `builtins.tryEval` and reported as `refused`/`RENDERED` lines the
shell asserts — `hostModuleUnits`' arrangement, one level down. With a **control**
beside them, since a render that refused everything would otherwise read as this
suite passing ([item 37](./037-a-teardown-that-only-unnames.md) again: a round
that never discriminates). The fixture target is nobody's — borrowing doctrine's
values would make it pass by standing still
([item 38](./038-a-probe-that-became-a-borrower.md)).

**One construction, so `render` is the function and the profile is it applied.**
`flake.nix` needed the file as a function of a target for the suite's fixtures
and as a value for this host, and building both would be two careful
constructions of one thing (CLAUDE.md). `hostProfile = render target`.

**Two mutations that mattered, out of five.** Gutting the required-field loop went
red on exactly four cases and nothing else; replacing the line-per-value read with
a `@tsv` row went red on the two fixtures that exist for it — the target with
`null` commands, because bash treats tab as IFS *whitespace* so an empty column
collapses and every later field shifts up by one, and the target with spaces in
its paths. That trap is the reason the reader is one value per line, and the
comment saying so is now load-bearing. The other three (the env override ignored,
the `guestPath` derivation check dropped, the newline check dropped) each went red
on their own case alone.

**Two things fixed in passing.** `just build` was missing `observeCases` and
`baselineCases` — added in step 2, added to `just cases`, never added to the
build, so two of the seven suites were not failing the build they are supposed to
fail. And `just build` now names `profileCases`, which is the eighth.

## What steps 1 and 2 turned out to be

Written after doing them, because three things were not in the plan above.

**One text, not one text per instantiation.** The seam these five scripts already
had was a *nix function* of the checkout, which is one store path per checkout —
the same shape as one program per capsule ([item 20](./020-which-capsule-a-program-means.md)),
one level down. Moving the values to argv removed the function: `snapshotFor`,
`refreshFor` and `runnerFor` are gone and `stateSnapshotScript`, `refreshScript`
and `briefRunner` are store paths. The state snapshot had **three** call sites — a
guest, this host's own checkout under `--from-host`, and the sandbox — and they
are now one path and three command lines. Each file exports the tail of that
command line (`argsFor`, `guestArgs`, `runnerArgs`) so no call site can order the
values differently, which is also the one place step 4 has to change.

**A value crossing ssh is parsed twice, and that had to be built.**
`guest-exec.nix`'s `loginRun` was `bash -l -c 'bash -s'`, which has no channel for
an argument at all; it is `bash -l -c 'bash -s "$@"' capsule-guest-script` now.
ssh joins its arguments with spaces and the guest's shell parses the result, so
every value is escaped **twice** — the same class as a `just` recipe's `{{...}}`
being text and never an argument (CLAUDE.md), and the failure is a value with a
space in it splitting silently. `capsule-baseline`'s invocation was worse: it
built a nested `bash -l -c "bash '$dir/run.sh' start $stamp"`, which is *three*
parses. It is the `"$0" "$@"` shape now, which uses its arguments instead of
re-parsing a string built out of them, and that is what keeps the count at two.

**`needsUnit` came down a level, and it is the shape decision 3 is about.**
`host/state-snapshot.nix` decided at eval whether its templates were unit-scoped
and emitted the refusal conditionally, so *whether the guest checks at all* was a
property of which flake the host had built. The script computes it from the
templates it was handed. The host still asks the same question at eval —
`capsule-collect` refuses before it opens the door — and `stateNeedsUnit` still
shapes the front end's printed text, which is the half that has not moved.

**The two files with no suite have one, and neither was covered by accident.**
`observeCases` and `baselineCases` are new; `just cases` runs seven suites now.
Both reach branches a live host reaches expensively — an unprovisioned volume, a
baseline that failed, a run already in flight, a build that can be asked to fail
— and `host/baseline.nix` had to split into `{program, runner}` for its guest half
to be reachable at all. Every suite was then run against a mutated copy
(a script ignoring its argv, a hardcoded path) and the rounds that went red were
the ones naming the value: no collateral, and nothing that passed for the wrong
reason.

## Order of work

Red/green, and the first step is a test that fails. **Steps 0, 1 and 2 are
done**; what follows for 3-6 is what was written before any of them, kept because
it is still what those steps say:

0. **Done. Split the case suites out of `flake.nix`, before step 3 and not during
   it.** Not detargeting, and it changes no behaviour — it is the precondition for
   doing the rest of this legibly. `flake.nix` was **2565 lines and 1341 of them
   (52%) case suites**; steps 1 and 2 added about 530 of that, and steps 3-6 add
   more, as does D7 after them. Three unrelated kinds of thing shared the file:
   the composition (values → programs → outputs, the only part
   that has to be there), the suites, and the probe fabric (~350 lines, which
   *does* belong there — `borrowed` has to throw where probes are constructed,
   [item 38](./038-a-probe-that-became-a-borrower.md)).

   **One file per suite, beside what it pins** — `host/state-snapshot-cases.nix`,
   `host/refresh-cases.nix`, and so on — each a function of `pkgs`, `lib` and the
   store path it runs, with a short `import` left behind. Beside rather than
   in a `checks/` directory, because a suite and the program it pins are read
   together, which is the pairing `host/` already uses. `nix_paths` globs
   directories, so `just check`'s parse and `alejandra` picked them up with no
   justfile edit.

   Two invariants the move had to preserve, both already true of the text: a suite
   runs **the store path the program ships** and never a re-render — which is
   precisely what step 2 made possible — and `guardStubs` travels with
   `guardCases` (its only caller) while `quarantine` is shared and stays.

   Doing it *after* step 3 would mean moving 1350 lines in the same commits that
   change what programs read, and neither diff would be readable.

   **What it came to:** `flake.nix` 2565 → **1263**, seven files of 1384 lines
   under `host/`, and the seven attribute names, the `packages` set and `just
   cases` unchanged. Two of the suites are handed a *fixture* rather than a
   shipped path and say so in their own headers — the guard its stubbed kernel,
   the front end a pool that is not this host's — and those two came off
   **unchanged store paths**, which is the move asserting its own claim: nothing
   about what they build moved. The other five rebuilt for one reason each, a
   markdown link in a shell comment that had to become `../docs/ledger/…` a
   directory down. Every case's log line is byte-identical before and after.

1. **Done. Extend `snapshotCases`, `refreshCases` and `briefCases`** to pin the
   argument-taking form of every value each guest-side script currently
   interpolates. Watch them fail against today's text, which is the rule about
   mutating the behaviour a suite claims to pin. Note what these three actually
   cover: `snapshotFor` takes a checkout and still bakes `statePaths` and
   `stateMaxBytes` (`host/state-snapshot.nix:90,99`), `refreshFor` already takes
   both of its values, and `briefRunner`'s guest half already takes its only one —
   what `brief` bakes is host-side (`guestRepo`, `hostCheckout`). So step 1 is
   mostly one file's worth of new pinning, not three.
2. **Done. Move the values into arguments** in `host/state-snapshot.nix`,
   `host/observe.nix`, `host/refresh.nix`, `host/brief.nix`, `host/baseline.nix`.
   Nothing about where the values *come from* changes yet; this step only ends
   interpolation.

   **Step 1 did not cover this list, and the gap was two files — closed.**
   `host/observe.nix` (`:42-44`) and `host/baseline.nix` (`:73-75`) each
   interpolate three values and **neither has a case suite at all** — so red/green
   is red for three of the five and silent for the other two. Either they get
   suites first, on the seam the other three already have (a function of its
   subject, exported beside `stateSnapshotFor` and `refreshFor`), or this item
   says out loud that two of the five move unpinned. The first is the cheaper
   answer and is the same shape three times over; the second is a choice, not an
   oversight, and must be written as one.
3. **Done. Render the profile document.** `target.nix`'s run-time half → JSON,
   authored in nix and checked at build, read at run time through one function.
   §6.1's *validated document, not a nix file*, with `perimeter/egress-allow.txt`
   as the standing precedent for the plain file it is deliberately not yet.

   **What it came to:** `host/profile.nix` — ten fields, `schema: 1`, eleven
   checks at render and seven at read, plus `profileLoad`/`profileShow` as a
   fragment. `host/profile-cases.nix` is 57 cases, the eighth suite. The document
   is `capsule-profiles` as a flake output so a human can read what a program will
   resolve. **No host program's store path moved** — `capsule-cli`,
   `capsule-provision`, `capsule-collect` and `capsule-brief` are byte-identical
   to HEAD's, checked against a throwaway worktree, which is the honest statement
   that step 3 is a render and not a switch.
4. **Host programs read it after resolving `--capsule`**, exactly where
   `transport` already resolves a socket, and with the same refusal when unnamed
   ([item 28](./028-a-slot-has-no-default.md)).
5. **Pair the read with the units' permissions in `hostModuleUnits`** — a program
   that opens `profileDir` and a unit whose user can traverse it. This is
   [item 39](./039-a-bind-is-not-a-traversal.md)'s class exactly, it is not
   catchable by the cases because a sandbox has one uid, and it is where the last
   bug of this shape came from.
6. **`programVerbs` and `stateNeedsUnit` last**, since what exists at all becomes
   a property of the document rather than of the build, and that is the step most
   likely to want a decision nobody has made yet — decision 3 above, which is
   about the *table* and not about the values. The verb list is the easy half and
   could land alone; the predicate is eleven sites of printed text and should not
   be started before that decision is taken.

## What must not drift while this is being built

Every one of these has cost something once:

- **No program probes for which target it means**, any more than one probes for a
  transport. It takes an argument or reads the record it was pointed at
  ([item 20](./020-which-capsule-a-program-means.md)).
- **Nothing target-shaped is read out of the target repo.** The document is
  host-side and keyed by name; the agent can edit the confined tree
  ([item 16](./016-target-agnostic.md)).
- **A profile is pinned at the assignment's generation; a policy is live.** Two
  owners, two clocks — editing a project's caches must not change what a running
  capsule is doing with no verb run against it, while a tightening must reach one
  without a re-assign ([contract-assignment.md](../contract-assignment.md),
  [item 25](./025-assignment-is-a-perimeter-verb.md)).
- **No control migrates into the profile.** `collectMaxPackBytes` and the
  allowlist are policies and stay policies; `stateMaxBytes` is the target's,
  because it bounds what the target's own declared paths may grow to
  ([item 36](./036-a-policy-is-selected-not-named.md)).
- **The two shipped copies stay one store path.** `host/cli.nix` is imported at
  two call sites and only stays a single derivation while every argument agrees;
  anything built at two call sites needs one construction
  ([CLAUDE.md](../../CLAUDE.md)).

## Risk, and the smoke test

`capsule-provision` and `capsule-collect` are what the live slots use, and a slot
is holding real work ([status](../status.md)). So: one commit behind `just cases`
and `just build`, and before anything else on the far side of the switch, a
`capsule all status` and one `capsule <slot> collect` against a slot whose result
is already safe. A refactor that reports success while collecting nothing is the
failure mode this repo has already had once, in `host/refresh.nix`
([item 47](./047-a-script-on-stdin-and-the-command-that-eats-it.md)).

**Step 3 did not spend any of that, and the reason is checkable rather than
argued.** It adds a document, a library and a suite and changes no program: the
four store paths above are byte-identical to HEAD's. So the smoke test is still
owed in full, and it is owed at step 4 — the first commit in which a live slot's
`capsule-provision` is a different store path from the one that provisioned it.

## Which verb the evidence covers

**Read**, twice, and then **Build** four times — steps 1, 2, 0 and 3, in that
order. The first pass took `host/programs.nix`,
`host/git-channel.nix`, `host/cli.nix` and `target.nix` plus the record-writing
site, and produced the inventory. The second was a readiness pass over the plan
this file had already written — `host/record.nix`, `host/state-snapshot.nix`,
`host/refresh.nix`, `host/brief.nix`, `host/baseline.nix`, `host/observe.nix`,
`host/services.nix`, the `justfile`'s `cases` recipe and [plan D](../plan-d-fleet.md)
§6.1 — and it is what added the `stateNeedsUnit` row, `profile_snapshot`,
decisions 2 and 3, step 1's coverage gap and the `guestPath` edge. Every line
reference above was checked against the file it names.

Both passes were taken before anything was built. **Steps 0 to 3 are now built
and green.** 0, 1 and 2 were mechanical, scoped and needed none of the decisions;
3 needed two of them and they are taken. **Steps 4 to 6 are not built**, and what
step 6 waits on is decision 3 — step 4 and step 5 wait on nothing but the work.
The inventory is the reads' product and is the part worth trusting; the ordering
is a judgement, and so far it has held.
