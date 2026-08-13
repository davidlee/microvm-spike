# NOTES item 3 — `pkgs.claude-code` is unfree, and guarded for channel drift

*State: resolved, then superseded — the guest's agents come from `llm-agents`
now, so neither the predicate nor the existence guard exists any more
([item 31](./031-the-fragment-vocabulary.md)). Kept because the reason the
predicate was narrow still holds for anything else unfree that is built in
*this* repo's eval.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**`pkgs.claude-code`** exists on this channel (confirmed by it failing the
unfree check, not the existence guard). It is unfree, so the guest carries
an `allowUnfreePredicate` naming just that package. Still guarded by
`lib.optional (pkgs ? claude-code)` for channel drift.
