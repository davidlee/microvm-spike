# NOTES item 3 — `pkgs.claude-code` is unfree, and guarded for channel drift

*State: resolved.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**`pkgs.claude-code`** exists on this channel (confirmed by it failing the
unfree check, not the existence guard). It is unfree, so the guest carries
an `allowUnfreePredicate` naming just that package. Still guarded by
`lib.optional (pkgs ? claude-code)` for channel drift.
