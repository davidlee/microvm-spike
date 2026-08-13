# Contract — what a slot is assigned, and who may say so

**Nothing here is built.** [status.md](./status.md) owns the present tense and
says so; this file is the shape being fixed *before* [Plan D](./plan-d-fleet.md)
D1 writes a persistent record, because a record is the most likely place for
today's one-target assumptions to survive a transition that was meant to remove
them. Plan D §9 has the sequencing; this is the artifact that step produces.

**No version numbers.** The shape is in negotiation between this repo and
doctrine, and a version is a compatibility promise neither can make yet. What is
frozen instead is the *split by authority* below — the field list will move and
the owners should not.

This is a governing artifact for both repos. This repo executes an assignment;
doctrine drives one ([contract-doctrine.md](./contract-doctrine.md)). A repo
being confined does not read any of it — that is
[contract-target.md](./contract-target.md), and its floor is the client-facing
half of the same design. The guest's capability set is
[contract-flavour.md](./contract-flavour.md).

## The nouns, and who owns each

Plan D §6 named five; the sixth is the one it left inside "target", and
[item 25](./ledger/025-assignment-is-a-perimeter-verb.md) is why that mattered.
**The split is by authority, not by where the value happens to live today.** Two
values in the same file with different owners is the shape of every coupling
this repo has already had to undo once.

| noun | what it decides | owner | when it changes | who may change it |
| --- | --- | --- | --- | --- |
| **slot** | identity, namespace, uplink /30, socket, units | host declaration (`capsules.nix`) | host rebuild | host operator |
| **flavour** | the guest's capability and tool closure | **not declared — composed** from the profile's floor and the assignment's extras ([contract-flavour.md](./contract-flavour.md)) | stop, build, start — a symlink re-point, not a rebuild of the fleet | both owners, within a fragment vocabulary the host declares |
| **class** | machine config: `mem`, `vcpu` | the runner's JSON | stop / start | host operator declares; an assigner selects within the slot's set |
| **policy** | egress allowlist, ingestion bounds, whether this slot may collect | host declaration, *selected* by the assignment | live — see the refresh rule | host operator declares the set; an assigner selects within it, or is refused |
| **profile** | project semantics: baseline, caches, static guest config, work branch, tool floor, display identity | host-held, keyed by name | pinned per assignment generation | an assigner names it |
| **assignment** | binds a slot to profile + policy + class + extras + base commit + purpose | `/var/lib/capsule/<slot>/` | run time, free unless the composition is unbuilt | an assigner |
| **volume** | everything mutable: checkout, `$HOME`, caches, build tree, host keys | the volume | verbs (Plan D D3); size fixed at creation | host operator |

Four consequences worth stating rather than deriving:

- **`flavour` is the one noun with no single owner, by design.** A project
  declares a *floor* — what it cannot be built or tested without — and an
  assigner adds *extras* on top; the image is what those compose to. So there is
  nothing to name and nothing to select, and the question the earlier draft
  asked — profile or assignment? — dissolves into both, in different halves.
  What that costs is that a novel composition is a build; whether `assign` may
  wait for one, or must refuse, is a per-host declaration
  ([contract-flavour.md](./contract-flavour.md)).
- **`class` is `mem` and `vcpu` only.** Volume size is a `truncate` applied at
  first boot and never again (Plan D §5), so a class that included it would let
  an assignment claim a size its disk was not created with. Storage is a
  property of the volume; a class is a runner argument.
- **`policy` is not a property of a project.** An allowlist is a control, and a
  control chosen by whoever names the project is a control the naming authority
  holds ([item 25](./ledger/025-assignment-is-a-perimeter-verb.md)). The
  permissive answer — one slot, every policy — is a *declaration* a dev host may
  make, never the mechanism's default.
- **`profile` is data at run time.** Whether a profile is authored in nix and
  rendered to JSON in a directory, or written there directly, is a question
  about *who may author one* and not about a file format. This repo authors
  them in nix because that is what it has; the interface the programs read is a
  validated document in a directory, so a controller that never runs
  `nixos-rebuild` remains possible. `perimeter/egress-allow.txt` is the
  precedent already in the tree: a plain file rather than a store path, exactly
  so that changing it is not a build.

## The assignment

What a slot is currently supposed to be. Desired state, host-authored,
never read by the guest.

| field | what | why it is a field |
| --- | --- | --- |
| `generation` | monotonic integer, per slot, bumped by every mutation | what makes a late answer refusable. Without it a worker that returns after a re-assign operates on a slot that is no longer the one it was given |
| `profile` | name of a project profile | the semantics half of what used to be "target" |
| `profile_digest` | digest of the profile document as pinned at this generation | what "pinned" means concretely, and what a drift check compares |
| `policy` | name of a policy, from the slot's declared set | the control half. Separate field because separate owner (item 25) |
| `extras` | fragments composed on top of the profile's floor, from the slot's declared vocabulary | the assigner's half of what the guest can do. The profile declares a *floor* and never a flavour; the image is `compose(floor, extras)` ([contract-flavour.md](./contract-flavour.md)) |
| `composition_digest` | identity of the resulting image | what "same flavour" means when nobody named one. A change here is a volume question and not just a restart — see the reuse rule below |
| `class` | `mem`, `vcpu` | runner config |
| `base.ref` | what the human or the client asked for | provenance and display only. Nothing resolves against it twice |
| `base.oid` | the commit that ref resolved to at assignment time | **the authoritative one.** A ref moves; an assignment must not silently move with it, and every later comparison — dirty, ahead, is-this-a-valid-clone-source — is arithmetic on a commit |
| `purpose` | free text | **opaque here, always.** Whatever a client puts in it is the client's; this repo displays it and never parses it. The same rule as `baseline` being a command line and not a build system |

`base.ref` and `base.oid` are the shape `capsule-provision` already implies —
`<ref>` is any commit-ish and deliberately undefaulted
([contract-target.md](./contract-target.md)) — made durable. What is new is that
the resolution is recorded rather than discarded.

## The observed status

What is actually true, as distinct from what was asked for. Everything below is
a *measurement*, taken host-side, and none of it is authoritative about intent.

| field | how it is read |
| --- | --- |
| `applied_generation` | which assignment the volume's contents actually reflect. Not equal to `generation` means a pending or failed apply, which is a state and not an error |
| `head_oid`, `dirty`, `ahead` | one ssh round trip into the checkout |
| `baseline` | verdict and age, **read from the record on the volume, never from an exit status** — `capsule-baseline` writes the record before the shell that runs it can lose the status (Plan D D5, [item 24](./ledger/024-set-u-not-login-shell.md)) |
| `session` | whether anything is attached or detached in there (Plan D D6) |
| `disk` | `df` on the volume — the fleet's binding constraint (Plan D L8, [probes](./probes.md#figures)) |
| `memory` | current and peak. Peak because nothing hands memory back until a stop, so `stop` is a resource verb and a human needs to know which idle slot to reap |

Keeping these two objects apart is most of the value of writing this file
down. A record that mixes them cannot answer *is this slot doing what it was
told* — which is the one question an administered fleet is for.

## The refresh rule

**A profile is pinned; a policy is live.** Different owners, different clocks:

- Reapplying a slot's payloads reapplies **the profile generation the assignment
  pinned**, not whatever the latest profile document says. Build semantics
  belong to the assignment, and an edit to a project's caches or its baseline
  changing what a running capsule is doing — with no verb run against that
  capsule — is the reproducibility failure this repo already avoids elsewhere by
  making `guestConfig` a symlink into the store rather than a copy.
- A **policy** takes effect on its own terms, because a tightening must reach a
  running capsule without anyone re-assigning it. A widening is a host
  operator's act by construction, since only the operator may edit the declared
  set.

Plan D §6.3 had one rule — refresh-always — for both, which is right for the
property it was protecting (no stale copy outliving the sizes it was rendered
from) and wrong about which document it re-reads. The generic capability is *a
payload declaration says whether it is pinned or live*, which is one field on
the declaration rather than two mechanisms
([item 22](./ledger/022-secrets-at-start.md) already needed a field of the same
kind for write-if-absent versus derived).

## States, and what makes a slot reusable

`unassigned → provisioned(oid) → baselined(oid) → dirty`, and the transition
into `dirty` is mechanical: worktree dirty, `head_oid != base.oid`, `$HOME`
touched since the baseline, or an interactive session opened.

**Reuse across an ownership change is a trust question, not a
cache-compatibility one.** A volume carries the previous assignment's caches,
build tree, `$HOME`, injected credentials and ssh host keys. Under a new
project, composition or policy,
those are not stale garbage — they are *input supplied by a different
principal*, and a build that reads them is a build the new owner did not
specify. So:

- changing `profile` or `policy`, or arriving at a different
  `composition_digest`, on a non-clean volume is **refused**, with `--reset` as
  the answer. The check is on the digest and not on a name, so adding one extra
  fragment counts and nobody has to remember that it should;
- a dev host may waive that by declaration, which is Plan D §0's two-modes rule
  again;
- a clone's identity is scrubbed by default and kept only under an explicit flag
  (Plan D D4), and a slot is a valid clone *source* while it is `baselined` and
  not yet `dirty` — which is also the cheapest source, since a volume's
  allocation is its high-water mark and never its current usage (Plan D L8).

The mechanism belongs here. The *policy* about what may be reused is the
client's.

## Concurrency

One host, ten slots, and a generation integer: the discipline is a `flock` on
the slot's directory for any mutation, and a read-modify-write that checks the
generation it read is the generation it is replacing. Nothing more elaborate is
warranted at this size, and anything more elaborate would be inventing a
control plane this repo has repeatedly declined to build
([plan-c-multi-capsule.md](./plan-c-multi-capsule.md), "No daemon").

What the generation buys is worth naming precisely, because it is not
concurrency in the usual sense: **any command that acts on a slot states the
generation it is acting for, and is refused if that is not current.** Without
detached work that is bookkeeping. With it (Plan D D6, and anything
`capsule-run`-shaped) it is the difference between a stale worker reporting into
the slot it was given and reporting into whatever that slot has since become.

## Who may assign

Trivial on a dev machine, where every repo and every slot is the same human's.
It stops being trivial the moment a program assigns, and the answer this file
commits to is narrow on purpose:

**an assigner is unconstrained in `profile`, `base` and `purpose`, and
constrained to a declared set in `policy`, `class` and `extras`.** The first
three are semantics and are what delegation is *for*; the last three are
controls, resources and guest code, and a set is what makes "this slot may be
handed to anyone" a thing a host operator states rather than a thing that is
true because nobody thought about it.

The profile's *floor* is not in either list, and that is deliberate: it belongs
to the project, arrives pinned with the profile, and an assigner names a profile
rather than editing one. What an assigner adds is extras, from the vocabulary.

## What is deliberately not here

**Execution.** There is no request/result shape in this file, and the omission
is current rather than permanent. Two reasons, and the second is the one that
matters: doctrine does not want to care about it yet, and when it does the angle
is likely to be different in kind — an outbox that a capsule fills and a host
notices, rather than a synchronous verb that returns a verdict.

That difference is not cosmetic, and it is why writing the contract early would
be worse than leaving it open. A notification model is *guest-initiated*, which
is exactly where [item 18](./ledger/018-git-channel-direction.md)'s invariant
would be quietly given up: the host initiates both directions, and the guest
has no channel out. An outbox the host *polls* over the door it already has
keeps that; a doorbell the guest *rings* does not, whatever it is implemented
with. Anyone drafting this later starts there.

What the assignment does owe any such shape, and already carries, is
`generation` — a run states which assignment it was for, and a result that
arrives late is refusable rather than misattributed. When the shape settles it
belongs in a generic execution contract, not inside doctrine's file: doctrine
being the first consumer is not a reason for the mechanism to be its
(contract-doctrine.md, Role 3).
