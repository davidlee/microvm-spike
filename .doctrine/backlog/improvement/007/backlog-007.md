# IMP-007: A declared default target for a slot nobody has assigned

**This host declares two targets as of `IMP-004`, so five unassigned slots now
refuse every `profileVerb` until told `--profile`.** The refusal is correct and
was designed for (item 51, decision 3); the question is whether the operator may
*declare* which target an unassigned slot means, the way they already declare
which policy it runs.

## What happens today

`profileNameFor` (`host/cli.nix`) resolves in three steps: an explicit
`--profile`, then the slot's assignment record, then — only if this host has
rendered exactly one — that one. With two documents in `profileDir` the third
step refuses, naming both. `capsule all status` shows `-` in the profile cell for
every unassigned slot, which is the same refusal rendered as a table.

## The precedent, and where it stops

The **policy** axis already has exactly this shape: `capsules.nix` declares
`policy` (the operator's choice for a slot nobody has assigned) beside `policies`
(the set an assigner may select within) — two fields because they are two
statements, and the second is what makes `capsule <slot> policy <name>` safe to
delegate (`NOTES item 36`, `item 25`). A declared default is **not** `item 28`
softening: `item 28` is about a slot's *name*, which means nothing and so cannot
be guessed on a human's behalf.

`capsules.nix` states the warrant for the policy default in one line: **absence
is not a state a perimeter may be in.** A slot whose record names no policy still
has to run something.

**That warrant does not transfer.** Absence *is* a fine state for a target: an
unassigned slot holds no project, and nothing has to be chosen until a provision
chooses it. So a profile default is a convenience, not a necessity, and it is
worth saying so before building it.

Against it, and it is `Plan D` §0's own decision: **a slot's name is abstract and
carries no meaning** — `a` is not doctrine's and `b` is not the spare. A per-slot
`profile` field says slot `f` is a panopticon slot, which is a binding at
declaration time that the pool shape deliberately avoided. Declaring is not
inferring, so this is a tension rather than a contradiction, but it is the thing
to decide first.

## Two shapes

1. **Per slot, mirroring policy.** `profile` and `profiles` in `capsules.nix`:
   the operator's default and the set an assigner may select within. Symmetric
   with the axis beside it, `POL-003`-clean (declared, one home, nothing
   implicit), and it is also the field `plan-c` recommended as cheap insurance
   and `Plan D` L1 records as **not taken** — `declared` carries `index` and
   nothing else. `IMP-006` needs that field or its replacement anyway, since a
   slot must say which image it is.
2. **Per host, one name.** A `defaultProfile` in one declaration. Cheaper, and
   the thing `POL-003` is most suspicious of: it is an implicit default wearing a
   declaration's clothes the moment a second one is wanted.

Shape 1 is the recommendation, on the strength of the policy precedent and
because `IMP-006` needs the field regardless.

## Cost

`capsules.nix` schema and `instancesOf`, the front end's resolution step, the
`profileCases`/`policyCases` fixtures, and `docs/contract-assignment.md`. Not
large, but it is an axis change and `POL-003` governs it — worth a slice if the
per-slot set (`profiles`) comes with it, since that is a delegation boundary and
not only a default.

Evidence rung (`STD-001`): the *need* is **taken** — five slots refusing on this
host, observed 2026-08-17 (`IMP-004`). The design is **reasoned** and unbuilt.
