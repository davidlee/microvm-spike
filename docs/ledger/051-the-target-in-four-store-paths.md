# NOTES item 51 — the four programs still spell the target, and it is item 20 one level up

*State: **steps 1 and 2 built and green; 3-6 gated on three decisions.** The five
guest-pushed scripts take every value they are about on their command line, the
two that had no case suite have one, and each of the seven suites was watched
going red against a deliberately broken copy of what it pins. Nothing about
*where* the values come from has changed yet — they are still `target.nix`'s,
spelled by the host program that makes the call — so no store path has stopped
being a function of the target. That is step 3 onward.
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

## The decisions not taken

Three, not one — and two of them gate step 3 rather than being taken during it.
Steps 1 and 2 need none of them, which is why the order of work starts where it
does.

**1. Is the profile document per target, or one for the host?** Per target —
`profileDir/<name>.json`, with the slot's record naming which — is the eventual
shape and mirrors `policyDir` exactly. One document for the host is less work
today and is a second thing to migrate later. **Recommended: per target**, on the
grounds that the interim saves an hour and the migration costs a day, and that
`policyDir` has already paid for the shape.

**2. Where does the document live, and who validates it?** Step 3 says *checked
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

**Recommended: render to a store path first and read it through one function**,
so the plain-file switch is a change of where that function looks rather than a
change to every caller. Not decided.

**3. What does a fleet-wide status table do with a per-target predicate?**
`stateNeedsUnit` shapes the front end's printed text, and `capsule all status` is
one table for every slot. Three answers exist — the union of columns with blanks
where a target has none, a table per target, or the column always present and
empty — and they are a front-end decision that outlives this item. It is named
here because step 6 reads as *one list of verbs* and it is not: the verb list is
the easy half. Not decided, and it is the only one of the three that could
reasonably be deferred past step 3, since the predicate can stay build-time while
every *value* around it has moved.

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

Red/green, and the first step is a test that fails. **Steps 1 and 2 are done**;
what follows is what was written before they were, kept because 3-6 are still
what it says:

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
3. **Render the profile document.** `target.nix`'s run-time half → JSON, authored
   in nix and checked at build for free, read at run time by a program. §6.1's
   *validated document, not a nix file*, with `perimeter/egress-allow.txt` as the
   standing precedent for a plain file that is deliberately not a store path.
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

## Which verb the evidence covers

**Read**, twice. The first pass took `host/programs.nix`,
`host/git-channel.nix`, `host/cli.nix` and `target.nix` plus the record-writing
site, and produced the inventory. The second was a readiness pass over the plan
this file had already written — `host/record.nix`, `host/state-snapshot.nix`,
`host/refresh.nix`, `host/brief.nix`, `host/baseline.nix`, `host/observe.nix`,
`host/services.nix`, the `justfile`'s `cases` recipe and [plan D](../plan-d-fleet.md)
§6.1 — and it is what added the `stateNeedsUnit` row, `profile_snapshot`,
decisions 2 and 3, step 1's coverage gap and the `guestPath` edge. Every line
reference above was checked against the file it names.

Nothing is built and no step has been started. **Steps 1 and 2 are ready** —
mechanical, scoped, needing no decision, once step 1's two-file gap is closed
either way. **Steps 3 to 6 are not**, and what they wait on is the three
decisions above rather than more reading — 1 and 2 before step 3, 3 before step
6. The inventory is the reads' product and is the part
worth trusting; the ordering is a judgement.
