# IMP-003: Plan D D7 and D2's dynamic half — per-assignment flavour

`docs/plan-d-fleet.md` §9 order of work, step 8's remainder. Items 51 and 52 took
the host-side programs; **what is left is the guest image**, which still knows
the project's name (§6.2), and per-assignment flavour selection.

That selection is what turns the record's inert `extras` and `image` into fields
something actually selects — see `CON-001`, which is the constraint this closes.
It also brings the three things that do not exist while the list is fleet-wide:
a store-path identity, a gcroot that retains it, and a refusal to recompose under
a dirty volume.

Note the one-image lever is what makes every capsule `microvm@capsule` in the
process table, so **a VMM is identified by its namespace, never by its name**.
Per-assignment images must not quietly make `pkill -f` look safe again.

Slice-sized (`ADR-001` term 1).

Evidence rung (`STD-001`): unbuilt.
