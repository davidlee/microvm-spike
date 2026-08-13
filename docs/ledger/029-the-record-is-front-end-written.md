# NOTES item 29 — the record is front-end written, and a pin is measured rather than resolved twice

*State: built, unrun on this host — wants `just build` and a host rebuild.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

[contract-assignment.md](../contract-assignment.md) fixed the field list and the
authority split before anything was built, which is what it was for. Four things
it left to whoever built it came up immediately, and all four are answered by
rules this repo already had rather than by anything new.

## 1. `base.oid` is read back out of the guest, not resolved a second time

The contract says `base.ref` is provenance, `base.oid` is authoritative, and
*nothing resolves against the ref twice*. The obvious implementation resolves the
ref against the source repo at record time — which is a second resolution, and
the one that can disagree with what the capsule actually got.

So the front end does not resolve it at all. `base.ref` is what argv asked for;
`base.oid` is the guest's `HEAD` after a successful provision, read over the door
by the same round trip a status already pays for
([host/observe.nix](../../host/observe.nix)). That is not a convenience: the
commit a capsule is *working on* is the only commit an assignment can honestly
claim to have pinned, and a resolution done host-side is a claim about what
should have landed. The record follows the fact.

One consequence worth stating: `observe` therefore emits the **full** oid and the
status column shortens it for display, rather than emitting a short one and the
record pinning an abbreviation. A pin is not an abbreviation.

## 2. The front end writes it; `capsule-provision` does not

The record is host state, and [item 20](./020-which-capsule-a-program-means.md)
and [item 28](./028-a-slot-has-no-default.md) both say host state is a front
end's latitude and never a program's — a program that carries state has the state
in its store path, and `capsule-provision` exists in two copies that differ only
in transport. So `capsule <slot> provision <ref>` records, and
`capsule-provision --capsule <slot> <ref>` does not.

**That gap is deliberate and it is a real gap**, not a rough edge to be closed by
teaching the program about records. Calling the program directly already bypasses
everything else a front end does — picking the reachable copy, resolving an
unnamed slot, refusing a name this host does not declare. The record is the same
kind of thing. If it ever needs closing, the answer is a front end that is harder
to bypass, not a program that knows where `/var/lib/capsule` is.

## 3. It lives on the module path only, and under `slot/`

Two decisions, one paragraph each.

**Module path only.** A slot is a `capsules.nix` declaration and the units around
it are the module's; the devshell shape runs one guest and never needed a name
for anything but a quarantine. An assignment record for a devshell capsule would
describe a slot that does not exist. So the root is `moduleState`
(`/var/lib/capsule`) and not `statePaths`' two homes — and note the asymmetry
with the quarantine, which *does* search all of them, because either shape can
write one. A reader may search; a writer may not.

**Under `slot/`.** The contract's prose says `/var/lib/capsule/<slot>/`. The state
root already holds `collect/`, and `capsules.nix` has exactly one name rule — 11
characters, for IFNAMSIZ — so a slot called `collect` is legal and would land a
record inside a quarantine's directory. `/var/lib/capsule/slot/<name>/` costs one
directory. The alternative is a list of reserved slot names that grows every time
this repo adds a state directory, and which nothing would remind anyone to
extend.

## 4. `generation` is written and not yet checked, which is the right order

The contract asks for two things from one integer: read-modify-write under
`flock` so concurrent mutations do not lose each other, and *any command that acts
on a slot states the generation it is acting for and is refused if that is not
current*.

The first is built and verified — twenty concurrent writers land on generation
twenty, with no lost update and no half-written document. The second is not, and
deliberately: there is nothing detached to refuse yet (Plan D D6), and the two
have opposite retrofit costs. Adding the **field** later means rewriting every
record that exists; adding the **check** later means adding an argument to a verb.
So the expensive half ships early and the cheap half waits, which is the same
reasoning the contract used to call these properties "cheap now and expensive to
retrofit" — applied per property rather than to all of them at once.

## What is absent, and why absent rather than omitted

`policy`, `extras`, `image` and `profile_snapshot` are written as `null`/`[]` on
every record, by `recordWrite` itself rather than by any caller. A record then
says for itself which half of the contract is built, and no caller who meant to
set one field can forget the rest.

`profile_snapshot` is the interesting one. The contract wants *bytes*, retained,
because a digest detects drift it cannot undo. Today's profile is `target.nix`, a
build-time literal, and it is pinned by being in the closure — which is a
**stronger** pin than a copied file and a useless one for a controller that never
runs nix. So the field is absent rather than filled with a store path: a store
path there would look like the contract satisfied while quietly requiring nix of
whoever reads it.
