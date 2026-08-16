# IMP-001: Plan D D3 and D4 — volume verbs and clone semantics

`docs/plan-d-fleet.md` §9 order of work, step 6. **Ungated** since `NOTES item
49`'s read on who owns a state directory was taken.

The case for doing it next is operational rather than architectural: S4 and S5
are the two most frequent administrative actions here, and **one of them is a
hand-typed `rm -rf`**.

Large enough to warrant a slice rather than execution straight off this item
(`ADR-001` term 1) — volume verbs touch the state-directory ownership question
and clone semantics touch provisioning.

Evidence rung (`STD-001`): unbuilt.
