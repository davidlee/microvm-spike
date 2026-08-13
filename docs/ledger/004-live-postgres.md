# NOTES item 4 — `just test` may want a live Postgres

*State: open, unhit.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**`just test` may want a live Postgres.** doctrine's flake sets
`doCheck = false; # tests need a live Postgres`, though no `DATABASE_URL`
appears anywhere in the tree. Not provisioned; `services.postgresql.enable`
in `vm/capsule.nix` if it bites.
