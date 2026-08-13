# Contract — what a flavour is, and where its tools come from

**Nothing here is built.** [status.md](./status.md) owns the present tense.
This is the design being fixed alongside
[contract-assignment.md](./contract-assignment.md), and it is the *build-time*
half of the same split: an assignment says what a slot is for, a flavour says
what the guest inside it can do. Today there is exactly one of these and it is
implicit — the guest image, built from `target.nix`'s `toolsPackage` plus
`extraTools` plus whatever `vm/capsule.nix` supplies. Naming it is what lets
there be two.

Cost, cardinality and the one-image lever it has to preserve are
[Plan D](./plan-d-fleet.md) §6 and D7. The client-facing floor — what a repo has
to do to get itself confined — is
[contract-target.md](./contract-target.md).

## What a flavour is

**The guest's capability set: a tool closure plus whatever the guest has to be
able to do to run those tools.** It is the only irreducible per-project content
of the closure. Everything else that looks target-shaped in the image today —
the checkout's directory name, the branch, the cache directories, the static
config, the motd — is a *value the seed reads out of the closure instead of out
of a document*, and D7's inventory is the list of those.

The second half of that sentence is not decoration. `programs.nix-ld` is a
guest capability with no package attached, and it is what made a second target's
first baseline fail at exit 127 one second in
([item 23](./ledger/023-second-target.md)). A flavour that could only carry
packages would have had nowhere to put it, and the answer would have been the
one that item rejected: a `target.nix` field that looks parameterised for
something every non-nix-native toolchain needs identically.

So a flavour is two lists — **packages** and **guest capability fragments** —
and both compose.

## Where the tools come from

**Not necessarily the repo being confined.** Today's floor says a target exports
a flake package that is its devshell's tool set, and that stays the *default*
because of what it buys: the guest and that devshell cannot drift, which is the
whole reason the tool set was threaded from the target in the first place. It is
a good default and a bad requirement.

Three sources, all legitimate, none privileged by the mechanism:

- **the target's own flake** — the default. Keeps the no-drift property. Costs
  the target an exported package, which is where
  [item 23](./ledger/023-second-target.md) argues that cost belongs.
- **a shared tool repo** — one flake carrying the tool set for a *class* of
  projects. A generic node/nextjs environment serving eight projects is one
  input, one closure, one image, and eight repos that export nothing at all.
  This is the case that makes the current floor wrong as a binding rule: most
  repos do not have a flake, and requiring one of them is requiring the wrong
  repo to change.
- **this repo's nixpkgs** — what `extraTools` is now. A supplement, and
  structurally limited to things with a bare attr name: a
  `python3.withPackages (…)` has no name to give, which is why `extraTools` was
  never the escape hatch it read as (item 23).

**What a target must supply is a floor: the fragments it cannot be built or
tested without.** Not a flavour, and not necessarily anything it authored — a
floor may be one reference to a shared base and nothing else. That is the
sentence that replaces the current one, and the difference it makes is which
repo has to change when an ordinary project arrives.

## Composition

**A flavour is not declared and selected. It is composed, and the composition
is the identity.**

    flavour = compose(profile.floor, assignment.extras)

Both are ordered lists of fragments drawn from a vocabulary the host declares.
The *floor* is the project's — what it cannot run without — and it travels with
the profile, pinned at the assignment's generation like everything else there.
The *extras* are the assigner's: task-specific tools, a debugger for this one
investigation, the human conveniences that make an ssh session bearable. Same
mechanism, two owners, and neither can quietly become the other.

That split is what the earlier draft got wrong by asking whether a *flavour*
belonged to the profile or to the assignment. Both, in different halves — and
the noun demotes accordingly: a flavour stops being a thing someone picks from a
list and becomes **the result of a composition, identified by its store path**.
Nix already identifies derivations that way, so this is a naming decision rather
than a mechanism.

**The store path, not a digest over the fragment names.** Names re-resolve: the
vocabulary's flake inputs relock and `agents` quietly means something else. So
an assignment records the resolved path and holds it with a gcroot, exactly as
it records a commit rather than the branch that named it — one rule, applied
three times ([contract-assignment.md](./contract-assignment.md)). A digest over
the inputs would detect that drift without being able to undo it.

Each fragment is a package set, a guest capability, or both, and each has
exactly one owner:

| fragment | declared in | owned by | example |
| --- | --- | --- | --- |
| base | the floor | host operator, from a shared tool repo or the target's flake | a node/nextjs environment; doctrine's `dev-tools` |
| project | the floor | the project, if it has anything the base lacks | one linter |
| capability | either | host operator | `nix-ld`; a language server; a guest service, if [item 4](./ledger/004-live-postgres.md) ever lands |
| convenience | the extras | **the host operator, declared** | the two below |

Two real cross-project extras, which are what the vocabulary is expected to look
like in practice:

- **`agents`** — `claude`, `pi`, `rg`, `tree`, fileutils, standard shell. What
  makes the capsule a place an agent can work at all.
- **`dev-facilities`** — `neovim`, `nushell`, `btop`. What makes it a place a
  human can look around in.

They are worth naming because of what they demonstrate about cost. **Neither is
project-shaped, and both are wanted by nearly every slot** — so nearly every
slot arrives at the same composition, one image serves all of them, and the
one-image lever survives contact with free-form extras. The expensive case is
the opposite one: a fragment used by a single slot is its own 3.0 GiB. Broad and
few is not a style preference here, it is the arithmetic.

`agents` also inherits two existing items rather than raising new ones:
`pkgs.claude-code` is unfree and guarded against channel drift
([item 3](./ledger/003-claude-code-unfree.md)), and how an agent's credentials
reach a guest with no shares is [item 2](./ledger/002-agent-credentials.md),
still open — a payload question, not a fragment one. The jailed `claude`/`codex`
bwrap wrappers stay out, as they already do: they bind host paths the VM does
not have, and the capsule's confinement *is* the VM.

The convenience fragment is the one to watch, and the rule on it is the same one
CLAUDE.md states about the cargo config: it is **declared**, never scraped from
a human's `$HOME`. A fragment that copies the host's dotfiles describes a
machine the capsule is not, and it is a channel for host state into a
confinement whose entire claim is that no host directory gets in. Convenience is
a legitimate thing to build a flavour out of; it is not a legitimate thing to
inherit.

Two mechanical questions the composition has to answer, and nix already answers
both, so neither should be invented here:

- **collisions** — two fragments providing the same binary. The default is a
  build failure, because a silently-shadowed toolchain is the class of bug that
  gets found in a guest at exit 127. `lib.hiPrio` / `lowPrio` in the composition
  is the deliberate override, stated by whoever composes rather than implied by
  list order.
- **ordering** — the list is ordered for legibility and for priority, not for
  semantics; nothing should depend on where in it a fragment sits.

### What the assigner may compose, and whether it may build

Two constraints follow, and both are the same declaration-not-default move §0
asks for.

**The vocabulary is host-declared; the assigner selects within it.** A fragment
is code in the guest closure, so an assigner that could name an arbitrary one
would be adding code to a confinement it does not own. Weaker than
[item 25](./ledger/025-assignment-is-a-perimeter-verb.md)'s case — a fragment is
a build input and not a control — but the same shape, and it takes the same
answer: a slot declares which fragments may appear in its extras, and `assign`
refuses outside that set. A dev host declaring "any" is the permissive mode
falling out of a declaration.

**Whether a novel composition may build on demand is also a declaration**, and
this is where the cost lands honestly. A composition that has been built before
is free — same fragments, same derivation, same image already in the store, and
assignment stays the seconds-not-minutes operation Plan D wants. A composition
nobody has built is a build, ~3.0 GiB of erofs and the time that implies. So:

- **dev host** — build on demand, and `assign` waits. The occasional two-minute
  assignment is the price of never pre-declaring anything.
- **ranch** — refuse an unbuilt composition. Assignment is then guaranteed
  cheap, and pre-building the allowed compositions is someone's job upstream
  rather than a surprise at assign time.

Neither is the mechanism. The mechanism is that a composition resolves to an
image, and the only question is what happens when that image is absent.

## What a flavour may not carry

**Any control.** No allowlist, no ingestion bound, no policy of any kind. The
asymmetry `contract-target.md` already states about the tool set holds here and
is the reason the whole split works: *the tool set comes from the confined side
because it is a build input rather than a control*. A flavour is that build
input, grown up. Put a control in it and the perimeter argument leaks in the
same motion that makes flavours look convenient.

Policy is the assignment's, from the slot's declared set
([contract-assignment.md](./contract-assignment.md),
[item 25](./ledger/025-assignment-is-a-perimeter-verb.md)). A flavour with a
compiler in it is not a perimeter question: a guest that can build can already
run what it built, and the perimeter is host-side.

### But "not a control" is not "safe to let anyone introduce"

The asymmetry above is about what the *guest* may reach, and it is sound there.
It says nothing about where a tool set is **produced**: a project's flake is
evaluated and built **on the host, as the host user**, before any capsule
exists and upstream of every control this repo builds. The confinement is the
VM; nix evaluation is not inside it
([item 26](./ledger/026-project-nix-runs-on-the-host.md)).

Academic on a dev box, where the human already runs `nix develop` in that repo.
Not academic once the assigner and the host owner are different parties. So the
host-declared vocabulary carries a second obligation beyond keeping the guest's
closure predictable:

- **every fragment source is registered by the host at a pinned revision** — in
  practice a flake input of *this* repo, named in a file the host owns and
  locked in a lock the host controls, updated only by a deliberate
  `nix flake update`;
- **an assigner composes from the vocabulary and can never extend it**, so
  introducing a new tool source is a host operator's act with a rebuild behind
  it — the same rare-and-declared shape as everything else here.

This is not a defence against a hostile project, and claiming otherwise would be
worse than saying nothing. A host that builds a repo's flake trusts that repo's
build. The narrow claim, which is the one worth making: **the set of repos whose
nix this host will evaluate is the host's to declare, and an assignment does not
widen it.**

## Cardinality, and what it costs

**One image per distinct composition, ~3.0 GiB of erofs**
([probes](./probes.md#figures)) — so the composition is the axis the one-image
lever actually rides on, and every slot arriving at the same one is the cheap
case. **This is the cost of the extras being free-form**, and it is worth
stating rather than discovering: a per-slot convenience fragment that nothing
else uses is a distinct composition and therefore its own 3.0 GiB. Broad shared
extras cost nothing; individually tailored ones cost an image each. That is not
a reason to forbid them — it is a reason for the fragment vocabulary to be small
and for `status` to be able to say how many distinct images the fleet is
holding.

Changing what a slot runs is a stop, a `nix build -o current`, and a start —
Plan D §5 read that from microvm.nix's own source: a slot's binding to a nix
artefact is one symlink in its state directory. Adding a *fragment* to the
vocabulary is a rebuild, which is the right way round: rare and declared against
frequent and cheap.

**The unavoidable literal is now per source, not per target.** One flake input
per repo whose packages a flavour composes, because an input's url cannot be
computed ([item 16](./ledger/016-target-agnostic.md)). This is strictly better
than today: eight projects on one shared base are one input, where eight targets
would have been eight. The count follows the number of *tool sources*, which is
small and slow-moving, rather than the number of projects, which is neither.

## The reuse boundary

A volume carrying one composition's caches is not merely useless under another —
it is input from a different principal. Changing a slot's composition on a
non-clean volume is refused; the rule and its dev-host waiver are
[contract-assignment.md](./contract-assignment.md)'s, because it is an
assignment-time check even though the thing changing is a build artifact. **The
comparison is on the resolved image path** — "same flavour" is not a name
someone typed, it is whether the same artifact came out.

Worth keeping separate from the profile and policy cases even though the
behaviour is the same today: those are provenance boundaries and this one is
mostly a compatibility boundary. Adding `neovim` is not an ownership transition.
The conservative refusal is right while nothing distinguishes them; the claim
that they are the same kind of event is not.

## Open

- **Guest services.** A project that needs a database to test against gets it in
  the guest closure or nowhere ([item 4](./ledger/004-live-postgres.md), open
  and unhit). Under this split it is a capability fragment, which is the first
  concrete thing the fragment list buys that a single exported package cannot.
- **What a fragment reference looks like in a profile.** The floor is a list of
  fragment names from the host's vocabulary, which is enough for every case
  named here — but a project that wants *a version* of something has no way to
  say so, and pinning by flake input is the host's, not the project's. Leave it
  until a project asks; the failure mode of guessing is a small matching
  language nobody needed.
- **The floor's honest scope today.** Composition and shared bases are what make
  a non-nix project confinable; until one exists, the supported set is
  nix-integrated projects, and `contract-target.md` says so plainly rather than
  hedging.
