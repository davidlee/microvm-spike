# NOTES item 51 — the four programs still spell the target, and it is item 20 one level up

*State: **closed. Steps 0-4 and 6 built and green, all four decisions taken, and
step 5 belongs to a commit this item does not contain** — see "what this does not
close" below, which is the honest half. Nothing about a host-side program is a
function of which project this host confines any more: not the values it carries,
not whether it exists, and not what the front end prints. The run-time half of
`target.nix` is
a rendered document — `host/profile.nix`, per target, in the store, read through
one function — and **every host-side program reads it**. `capsule-provision`,
`capsule-collect`, `capsule-baseline`, `capsule-refresh`, `capsule-brief` and the
`capsule` front end take `--profile <name>` where they already take `--capsule`,
refuse without one, and index into the document instead of into their own text.
And **which programs exist at all**, and which columns and verbs the front end
offers, stopped being a function of the target too (step 6, decision 3). Before
that: the
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

The table is the inventory as read. **Step 4 emptied its first six rows and step
6 emptied the seventh**: every value in them is looked up at run time now, and no
store path in the right-hand column carries one. What is left of the whole
inventory is one row's worth of `volumePath` in `capsule-inject`'s payload
destinations, which is deliberately out of scope and says why below.

The two names that went at step 2 (`snapshotFor`, `refreshFor`) were the first
half of the same move; step 4 is the second, and there is nothing between a
document and a program left to instantiate.

`programVerbs` was the same coupling in its other form: which verbs existed at
all was decided at build time by which `target.nix` fields are non-null.

`stateNeedsUnit` was that form again and looked the harder of the two, which is
why it had a row of its own rather than a mention. Twelve `lib.optionalString`
sites in one file, and eleven of them not a verb list but the shape of the text
the front end prints. **`capsule all status` prints one table for the fleet**:
one `printf` format, one header, every slot a row — so a predicate that becomes
per-target makes that one header over two column sets, which is a question about
the front end rather than about the values. That is decision 3, and it is
answered below; both of these are step 6 and both are done. What the reading got
wrong is that they are *two* couplings: they are one, and "the verb list could
land alone" was false.

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

**4. Which name does a program load?** Not in the item when step 4 started, and
the first thing it needed. Three candidates: the slot's assignment record
`profile` field (written at every provision since
[item 29](./029-the-record-is-front-end-written.md), read by nothing, and the
field this was reserved for); an explicit argument, [item 28](./028-a-slot-has-no-default.md)'s
shape; or the baked `target.name` as a default.

**Taken: the argument, with no default anywhere in a program, and the front end
resolving which name.** In full:

- **A program takes `--profile <name>`, else `CAPSULE_PROFILE`, else refuses** —
  `selectCapsule`'s shape one axis over, spliced beside it, stripping itself out
  of `"$@"` before the program's own flag loop runs. Item 28's rule applies
  unchanged and is sharper here than for a slot: the value a missing one would
  fall back to is a *different project's* `guestPath` and `statePaths`, so a
  collect would report success having taken nothing. That is
  [item 47](./047-a-script-on-stdin-and-the-command-that-eats-it.md)'s shape with
  a bigger blast radius, and it is why (c) is out — the coupling it reintroduces
  is not in the store path, it is in the silence.
- **The front end resolves the name**, in the order authority runs: an explicit
  `--profile` wins, then the slot's record, then — for a slot nothing has
  assigned — **the one profile this host has rendered, refusing when there are
  none or several**. That last is not a default. It is the same latitude
  `capsule <verb>` already takes with an unnamed slot (*the one that is up,
  refusing when none or several are*), one axis over, and it degrades in the
  right direction: the moment this host renders a second document, an unassigned
  slot has to say which. Reading host state is a front end's job and a program's
  disqualification ([item 20](./020-which-capsule-a-program-means.md)), so the
  whole of this lives in `host/cli.nix`'s `profileNameFor` and nowhere else.

**What an unassigned slot gets, stated plainly**, since the question was asked
that way: on this host, the profile it would have got anyway, because this host
declares one. On a host that declares two, a refusal naming both. There is no
arrangement in which it gets a build-time literal.

**And `profile_snapshot` stays owed.** Step 4 does not fill it, and the reason is
decision 2's: a record holding the document's *bytes* is a second place
`profileLoad` looks, which is exactly the property "one function, one directory"
was bought for. What step 4 does pin is the **name** — inert since item 29 and
load-bearing now — which closes the half of the sharp edge that a *rename or a
removal* opens: an assigned slot whose document has gone gets a refusal naming
the profile, where before it would have read whatever the build had baked. The
half it does not close is a document *edited in place* after a slot booted; that
still needs bytes, and bytes belong with the plain-file switch.

**3. What does a fleet-wide status table do with a per-target predicate?**
`stateNeedsUnit` shapes the front end's printed text, and `capsule all status` is
one table for every slot. Three answers existed — the union of columns with
blanks where a target has none, a table per target, or the column always present
and empty. It was named at step 3 because step 6 reads as *one list of verbs* and
is not: the verb list is the easy half.

**Taken at step 6: the column is always present — and the rule it is an instance
of is the part worth keeping.** *The front end's printed shape is not a function
of any target.* Every verb is offered, every column is printed, and what a target
does not declare is a `-` in a cell or a run-time refusal that names the profile.
Four grounds, in the order that decided it:

- **A table whose shape is a function of a document is this item's own coupling,
  one layer out.** Under the union the header changes when a document is edited
  or a second one is rendered — between two runs of one program on one host,
  silently, with no rebuild to notice it. Item 51's whole claim is that a program
  stops being a function of which project this host confines; a *printed shape*
  that is still a function of it has not stopped, it has only moved.
- **Rows are slots and the predicate is a target's.** Both other answers make a
  per-target fact govern a fleet-wide artifact. A table per target fragments the
  only view of the fleet there is, and neither it nor the union has an answer for
  the row an operator most often wants — the **unassigned** slot, which has no
  target at all.
- **The blank is already this table's vocabulary.** Every column here has an
  absent value, and `unit` already prints `-` for an assigned slot nobody has
  given one. A target that declares no hole is one more reason for the same `-`,
  not a new kind of cell.
- **The cost is six characters of width**, against eleven conditional sites, a
  header that changes shape, and a `printf` format that has to agree with both.

**And the rule has a boundary, which is what makes it a rule rather than a
preference.** A *program* holds exactly one profile and knows which target it is
about, so `capsule-brief`'s usage line and `capsule-collect`'s `--unit` refusals
**do** branch on the predicate at run time — that is a program being honest about
its own subject, and it is where the diagnostic can name the profile. The front
end holds N slots over M targets and has no single answer, which is why it gives
none. One profile: branch. N profiles: print the column.

## What step 6 turned out to be

**Not two halves after all — one, and the easy half was a consequence of the
hard one.** The step reads as *a verb list plus a predicate*, and step 3 said
the verb list "could land alone". It could not usefully: `programVerbs` is gated
on `stateSnapshot != null`, `stateSnapshot` was built only to answer
`needsUnit`, and the moment that predicate is a question about a document
`host/state-snapshot.nix` takes **no target value at all** — so the hook is never
null, the four `lib.optional`s have nothing left to test, and `programVerbs` and
`profileVerbs` fall out as literals. One change, in this order: the predicate
moves, and the list collapses behind it.

**The predicate has exactly one host-side home, and it is not where it was.**
`profileNeedsUnit` is a function of `host/profile.nix`'s fragment, beside
`profile_state_paths`, which is the field it reads. That is *not* a third
spelling: the guest half already asked the same question of its own argv
(`perUnit`, host/state-snapshot.nix), and one end reading a document while the
other reads the arguments it was handed is the pair that has to agree — the
refusal in the script exists to report exactly that disagreement. What went is
the eval-time copy that was threaded into two files.

**The eleven sites came apart into four kinds, and only one of them is new
behaviour.** Five simply **vanished** — the verb list, the usage line, the
`printf` format, the header and the row are now unconditional, which is decision
3. Four became `slotNeedsUnit`, the front end's resolution in front of the
predicate — provision's `--state-from-host` fill, the collect's fill, and the
brief's. One is **new**: `capsule <slot> unit <token>` now *refuses* when the
slot's document has no place for the token, because a recorded scope no collect
will ever substitute is the same lie as a `--unit` that scopes nothing, one layer
up. Reading the field is never refused, because the column prints for every slot.

**And `slotNeedsUnit` has three answers, which is the part that took thinking.**
Yes, no, and *there is no target to ask* — a slot nothing has assigned on a host
with two documents. Collapsing the third into "no" is wrong in both directions:
it would make the front end stop filling a flag it should fill, and it would make
`capsule <slot> unit <token>` refuse on a slot that has nothing yet for a token
to be wrong *against*. The case for it is the one that goes red against the
two-answer version.

**One eval-time reader survives on purpose, and it is not a relapse.**
`profile.needsUnit` exists for `probe/two-capsules.sh`'s command line and for
nothing else. A probe is evidence about the real capsule on this host and is
allowed to know this host's real target —
`probe/netns-boot.sh` is the standing exception for the same reason — and it
comes off `host/profile.nix` rather than being spelled in `flake.nix` so that
`{unit}` keeps one spelling ([item 38](./038-a-probe-that-became-a-borrower.md)
is what a separately-maintained copy of a live value costs). No **program** asks
it at build, which is the whole of the step.

**Three bugs, none of them step 6's, all in the front end's provision path, and
none of them ever installed.** This is the part worth reading. `capsule <slot>
provision <ref>` and `capsule <slot> setup <ref>` were both broken in the working
tree from step 4 until now, and the live host never saw either because it has not
been rebuilt since — verified rather than assumed: the installed
`capsule-collect` rejects `--profile`, so it predates step 4 outright.

1. **`recordProvisioned` grew a `<profile>` parameter at step 4 and `provision)`
   never grew the argument.** The call stayed `recordProvisioned "$name"
   $original_argv`, so the *ref* landed where the profile goes and every
   provision died on `no profile named '<ref>'` — **after the code had been
   pushed into the capsule**, which is the half that matters.
2. **`setup)` passed `$provisionProfile`, which only `provision)` sets.** A
   different branch of the same `case`, so under `set -u` it was an unbound
   variable, also after the push. Shellcheck could not see it: the variable *is*
   assigned somewhere in the file.
3. **Older, and the worst of the three: the "guest did not answer for its HEAD"
   branch had never been reachable.** `oid=$(observed "$n" | cut -f1)` is a bare
   assignment; `observed` returns 1 for a guest that does not answer, `set -o
   pipefail` carries that out of the pipeline and `set -e` killed the function —
   *silently*, because `observed` sends the transport's stderr to `/dev/null`. So
   a provision whose code landed against a guest that had since gone quiet exited
   1 saying nothing at all, and the message written for exactly that case had
   never once printed.

**Why nothing caught them, and what does now.** All three are past a `work` call,
so reaching them needs a program on `PATH` — and no suite had ever run the front
end's provision path at all, because until this step nothing stubbed
`capsule-provision`. Step 4's smoke test was a `capsule all status` and a
collect, neither of which goes near it. `policyCases` stubs four programs now
(`collect`, `provision`, `inject`, `baseline`) and asserts what the record step
did rather than what the front end said; (3) was found by the first case ever to
run that path, which failed against the *fixed* code and was therefore not a
mistake in the case.

**Nine mutations, each red on its own rounds and nothing else**, over three files
kept as copies (never `git checkout`, CLAUDE.md). The predicate forced to `yes`
went red on every no-hole round in all three suites and on no holed one; forced
to `no`, the exact mirror. Dropping the `unit` column went red on two rounds,
which is decision 3's pin proving it can fail rather than being a column that is
merely there. And **one mutation was rejected by shellcheck before the suite
ran** — deleting the profile argument from `recordProvisioned` makes
`provisionProfile` unused (SC2034) — which reports as "nothing went red" and is
the same trap step 4 hit; re-shaped to mutate the variable's *value* instead, it
went red on the three rounds that name it.

**Two suites grew, and a third helper had to be written twice.** `profileCases`
pins the predicate over three documents — a holed one, one with no state paths,
and the shape neither of the others reaches, *declared state with no hole in it*
— so "declares state" and "needs a unit" come apart. `gitChannelCases` gained a
third fixture and pins both directions of the fork on the shipped
`capsule-collect`: both runs exit 1 either way, so the **reason** is the whole
assertion, which is step 4's lesson reused. `policyCases` needed a negative
assertion and the first spelling of it was `grep -qv`, which asks whether *some
line* lacks the text and is therefore true of almost any output — a round that
never discriminates ([item 37](./037-a-teardown-that-only-unnames.md)), caught
before it landed.

**The smoke test, spent.** `capsule all status` off the new front end against the
live fleet: ten rows, two running capsules, every observed field present, and the
`unit` column printing `251`/`254` beside slots whose documents declare a hole —
which is decision 3 on a real table. Then one `capsule-collect` against slot `e`,
through the module path's own construction built out of the working tree, which
brought back **30 files and 566,960 bytes** under unit 251 plus the code refs —
the same figures step 4 measured, which is what says the run-time fork resolves
to what the build-time one did.

`just` and `just units` green; `just cases` is **369** (was 322).

**What this closes, and what it does not.** It closes the item: no host-side
program carries a target's values, none is built or withheld according to a
target's fields, and the front end's printed shape is a function of no target.
It does **not** make two targets concurrent, and two things say why. The
documents are a store path, so **two targets are still a rebuild apart** —
decision 2's stated limit, and the commit that lifts it is the one that owes step
5 and `profile_snapshot`. And the guest **image** still knows the project's name,
because `vm/capsule.nix`'s seed creates that directory; that is §6.2, a different
consequence with a different rebuild class.

## What step 4 turned out to be

**One seam, and step 2 had already put it in the right place.** Each of the five
guest-pushed scripts exported the *tail* of its command line so no call site
could order the values differently; step 4 is that export changing from a nix
string to a **shell fragment** that prints the same values off a loaded profile.
`argsFor`/`guestArgs` became `argsFragment`, `refresh`'s `invoke` became a
function, `baselineRecord` became `baselineRecordDir`, and `guestRepo` became
`guestRepoUrl`. Nothing else about any of those five moved, and none of their
*scripts* changed at all — which is the clearest statement there is that step 2
was the right shape.

**The escaping went down by one, and that is a fact worth stating rather than a
detail.** A value spliced into a program's text crossed **two** shells and was
escaped twice (this host's, then the guest's). A value that is an *array element*
at run time is not parsed by this host's shell at all, so exactly one `%q`
survives the hop — `profileQuote` — and two would arrive backslashed. The same
arithmetic, one lower, and the reason the count is checkable at all is that the
render forbids a newline in any value, so the filter can be line-based.

**The ninth suite, and it is over the two programs that carry the risk.** The
other eight pin *guest* halves; none of them can see the host half that builds a
guest's command line, which is precisely the half this step rewrote.
`host/git-channel-cases.nix` runs the shipped `capsule-provision` and
`capsule-collect` against fixture documents and asserts everything upstream of
the door: the refusal with no profile, the refusal with an unrendered one, the
*order* (a profile is refused before a policy, so a quarantine cannot be opened
for a target nobody named), and — the ones that pin the values — two runs
differing in one argument that name two different host checkouts and two
different guest URLs. It cannot reach past the door and says so: both programs
have `pkgs.openssh` in `runtimeInputs`, so nothing in a sandbox can stub `ssh`.

**Two suites gained the case that closes the loop, and one of those failures is
silent.** `snapshotArgs` and `observeArgs` are each one order of values, read
from a document at one end and by a script at the other, and until now every
suite composed that line *by hand* — so a suite and a program could disagree
about the order and both pass. `snapshotCases` and `observeCases` now build the
tail from the shipped fragment and run the shipped script with it. The snapshot's
disagreement is loud (a ceiling that is a path) and degrades a collect to
code-only, which is item 47's shape; the status's is **silent** — a plausible
answer about three directories nobody named — and it also pins
`<volumePath>/baseline`, a convention neither end declares and both derive.

**Eight mutations, each red on its own rounds and nothing else.** The two worth
keeping: giving `select` a fallback to this host's target went red only on the
cases that assert the *reason* for a refusal and not on any that assert its exit
status, because with a fixture directory the fallback fails too — a refusal for
the wrong reason is a different program passing, and asserting the reason is what
caught it. And two mutations were *rejected by shellcheck before the suite ran*
(an unreachable branch, an overriding case pattern), which the mutation harness
first reported as "nothing went red": a build that fails for another reason and a
suite that finds nothing look identical from outside, so a mutation has to be one
the build accepts.

**What is deliberately out, and it is a row of the inventory above.**
`capsule-inject`'s payload destinations still carry `volumePath` at build time,
and that is the honest line rather than an omission: `setup.nix` is a **host**
declaration of what this machine will hand a capsule, and a payload's destination
is on the *volume* — whose mount point `vm/capsule.nix` bakes into the image.
Making a credential declaration a function of a run-time document would be a
different decision about a different owner. Same for `capsule-adopt`, which reads
a quarantine on this host and no target value at all.

**And what step 4 did not spend: the smoke test, which is spent now.** `capsule
all status` off the new front end against the live fleet — two running capsules,
every observed field present — and one `capsule-collect` against slot `e`, which
resolved `doctrine` from that slot's record, built `ssh://agent@10.99.0.2/work/doctrine`
from the document, and brought back **30 files, 566,960 bytes** of state under
unit 251 plus the code refs. The failure this was owed against is a collect that
reports success and brings back nothing; it brought back an exhibit.

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
4. **Done. Host programs read it after resolving `--capsule`**, exactly where
   `transport` already resolves a socket, and with the same refusal when unnamed
   ([item 28](./028-a-slot-has-no-default.md)). See below.
5. **Owed, and *not* at step 4 — it moved to the plain-file switch, which is a
   change of fact rather than a deferral.** The pairing to assert is a program
   that opens `profileDir` against a unit whose user can traverse it
   ([item 39](./039-a-bind-is-not-a-traversal.md)'s class, uncatchable by the
   cases because a sandbox has one uid). Two things have to be true for that
   class to arise: the directory is host-owned rather than in the store, and a
   *unit* opens it. Neither is true today — decision 2 put the documents in
   `/nix/store`, which every uid can traverse, and the six readers are all
   programs a human runs, none of them an `ExecStart`. So there is no
   `profileDir` option and no `CAPSULE_PROFILE_DIR` in `host/services.nix`'s
   `wrap`: a knob whose only legal value is the store render is a knob with no
   user, and an assertion with no failure mode is a round that never
   discriminates ([item 37](./037-a-teardown-that-only-unnames.md)). It becomes
   real in the same commit the documents leave the store, and it is written here
   so that commit cannot forget it.
6. **Done. `programVerbs` and `stateNeedsUnit` last**, since what exists at all
   becomes a property of the document rather than of the build, and it was the
   step most likely to want a decision nobody had made — decision 3 above, taken
   at the start of it and written down before any of the eleven sites were
   touched. The prediction that "the verb list is the easy half and could land
   alone" was half right: it *is* the easy half, and it could not land alone,
   because both gates are the same gate. See above.

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

**Step 3 did not spend any of that, and the reason was checkable rather than
argued.** It added a document, a library and a suite and changed no program.

**Step 4 spent it, both halves.** `capsule all status` off the new front end
against the live fleet: ten rows, two of them running capsules, every observed
field present and unchanged in shape — which exercises the record read, the
document read, the argument order and the escaping over two real relay sockets.
Then one `capsule-collect` against slot `e`, whose exhibit was already collected
twice and whose result was therefore already safe: it resolved `doctrine` out of
that slot's record, built the guest URL out of the document, and fetched **30
files and 566,960 bytes** of state under unit 251 beside the code refs. A
refactor that reports success while collecting nothing is what item 47 cost, and
that is the number that says this one did not.

One honest limit on that evidence: the module path's programs are what a live
slot runs, and this host has not been rebuilt, so both halves were run from store
paths built out of the working tree — the front end directly, and the collect
through the same `host/programs.nix` construction `host/services.nix` makes, with
the relay-socket transport. Same file, same arguments, same store path a rebuild
will install.

## Which verb the evidence covers

**Read**, twice, and then **Build** six times — steps 1, 2, 0, 3, 4 and 6, in
that order — with a **Verify** on a live host at the end of the fifth and of the
sixth. The first pass took `host/programs.nix`,
`host/git-channel.nix`, `host/cli.nix` and `target.nix` plus the record-writing
site, and produced the inventory. The second was a readiness pass over the plan
this file had already written — `host/record.nix`, `host/state-snapshot.nix`,
`host/refresh.nix`, `host/brief.nix`, `host/baseline.nix`, `host/observe.nix`,
`host/services.nix`, the `justfile`'s `cases` recipe and [plan D](../plan-d-fleet.md)
§6.1 — and it is what added the `stateNeedsUnit` row, `profile_snapshot`,
decisions 2 and 3, step 1's coverage gap and the `guestPath` edge. Every line
reference above was checked against the file it names.

Both passes were taken before anything was built. **Steps 0 to 4 and 6 are built
and green.** 0, 1 and 2 were mechanical, scoped and needed none of the decisions;
3 needed two of them; 4 needed a decision the item did not have, which is
decision 4 above and is the one that took the longest; 6 needed decision 3, which
had been open since step 3 and was taken before a line of the eleven sites moved.
**Step 5 is not built and is not this item's**: it waits on the documents leaving
the store, which is a change of fact rather than a decision and is why it moved
out from under step 4 in the first place.

The inventory is the reads' product and is the part worth trusting; it named
every site, and step 6 found no eighth row. The ordering is a judgement and it
held through all six steps, with two corrections — step 5 belonged later than
step 6 rather than before it, and step 6's two halves turned out to be one. What
neither read caught is the three bugs above: they are not in the inventory
because they are not couplings, they are a parameter added in one place and not
another, and the only thing that finds that class is a case that runs the path.
