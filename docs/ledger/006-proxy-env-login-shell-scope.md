# NOTES item 6 — proxy env is login-shell scope, so units don't inherit it

*State: accepted.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Proxy env is login-shell scope** (`environment.variables` →
`/etc/set-environment`). Anything run from a systemd unit in the guest won't
inherit it.
