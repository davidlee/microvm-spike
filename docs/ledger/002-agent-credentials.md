# NOTES item 2 — agent credentials into a guest with no shares

*State: open.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Agent credentials — solved by `capsule-inject`.** No shares, so nothing can
be injected from the host *filesystem*; the channel that does it is the ssh
one that already exists, host-initiated, as the human. `setup.nix` declares
what leaves this host and `host/inject.nix` is the mechanism, which never
learns what a credential is — each entry brings its own filter.

Two payloads, and the split is the finding: the OAuth **token** is
`~/.claude/.credentials.json`, a file that is nothing but the credential, so
there is no subsection to take; `~/.claude.json` holds **no token at all** —
it is identity plus ninety keys of local state, of which four travel and
`projects`, `githubRepoPaths`, `mcpServers` and every cache do not. A
whole-directory copy would have taken `history.jsonl` (3 MB of prompts) and
`file-history/` into a jail that exists to not have them.

The token rotates on refresh, and a capsule holds a *copy* rather than
sharing the file — so the two diverge and neither is authoritative. Hence
write-if-absent with an explicit `--force`, rather than a merge or a
clobber. Running several agents off one credential is already known to work
(the bwrap jails do it), but they share one file; that answers concurrency,
not divergence.

The older path still works and needs none of this: `export
ANTHROPIC_API_KEY=...` in `/work/.env`, sourced at login. OAuth's device flow
wants a browser, which is why the token is carried rather than obtained.
**That path has a carrier now too** — the same one, as a declared payload, and
`capsule <name> start` runs it ([item 22](./022-secrets-at-start.md)).
