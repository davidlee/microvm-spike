# NOTES item 10 — vendored crates and pre-seeded `node_modules`, dropped

*State: decision.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Dropped since the first cut:** vendored crates
(`rustPlatform.importCargoLock`) and the pre-seeded `node_modules` from
doctrine's `web-modules` FOD. Both existed to make an offline capsule
build; the proxy supersedes them, and dropping them removed this flake's
dependency on doctrine's flake (and its `pub` / `llm-agents` transitives).
Worth restoring if you want cold-start builds without network.
