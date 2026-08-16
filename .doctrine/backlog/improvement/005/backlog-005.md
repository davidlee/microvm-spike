# IMP-005: Author the spec corpus

`ADR-001`'s step 5, the half not yet done. The invariants became `POL-001`…
`POL-004`; what remains is **SPEC**, and it is the least broken of the five
migrations, which is why it was deferred rather than dropped.

## What is waiting

Eight documents, in two shapes that want different spec kinds:

| document | shape | likely kind |
| --- | --- | --- |
| `docs/contract-target.md` | what any repo must supply and may rely on | **PRD** — the durable product intent of *being confinable* |
| `docs/contract-flavour.md` | where a guest's tool set comes from and how it composes | tech spec |
| `docs/contract-assignment.md` | what a slot is assigned, and who may say so | tech spec, with `POL-003` holding the authority half |
| `docs/contract-doctrine.md` | doctrine's two roles — client, and one instance of the contract | **neither, possibly.** It is a client's requirements register pointed at another corpus's ids |
| `docs/plan-b-other-jails.md` | the non-firecracker shapes | tech spec |
| `docs/plan-c-multi-capsule.md` | what N capsules on one host would cost | tech spec |
| `docs/plan-d-fleet.md` | what administering a fleet costs | tech spec, and the biggest |
| `docs/plan-e-room.md` | a guest that is **not** a capsule | tech spec |

**The contracts already split by authority**, which is the POL-vs-SPEC
distinction, so that half of the mapping is cheap. **The plans are scoping, not
commitments** — *"plans record what a thing would cost, not whether it has
happened"* — which is a tech spec's contract almost word for word, and their
order-of-work sections are slice material rather than spec material.

## Start with the assessment, not with the mapping

**Do not author eight specs off the table above.** `/spec-coverage-assessment`
exists for exactly this question — what is already governed, what is dark, and
where a new spec's boundary should fall by product altitude and C4 level — and
the table is a guess made before it ran. Two things it will likely move:

- **Whether `contract-doctrine.md` is a spec at all.** It is a register of
  another corpus's ids (`RFC-025`, `SPEC-030`, `REQ-448`, `DEC-191`…) mapped onto
  answers here. That may be a spec, a set of `CON` records, or a document that
  should stay a document. Whatever it becomes, **its ids stay doctrine's**
  (`ADR-001` term 2).
- **Whether four plans are four specs or one.** They overlap: Plan C's N-capsule
  costing feeds Plan D's fleet administration, and Plan B and Plan E are both
  *is the machinery separable from the product*. One spec with four sections may
  be the honest boundary.

## What this must not do

**A spec is not a place for present tense.** Two of the contracts already carry a
"part of this is built" line at the top, and those lines are now
`doctrine backlog list`'s and `doctrine knowledge list`'s job — the spec says the
shape, and what exists is a record's to say. Carrying the state across would
rebuild `NOTES item 54` in a fifth file.

**And a spec is not a second copy of a policy.** `POL-001`…`POL-004` hold the
rules; the specs hold the shape. Where a spec restates a rule it should cite it.

## Sizing

**Slice-sized, and probably the largest thing on this board** (`ADR-001` term 1 —
larger programs of work get a slice). The assessment is the first phase and may
well conclude that only part of it is worth doing.

Evidence rung (`STD-001`): unstarted. The mapping table above is **reasoned**, is
below *build*, and is the assessment's input rather than its output.
