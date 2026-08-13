# NOTES item 32 — credential divergence has a mechanism, and a grant that sidesteps it

*State: measured, and resolved by avoidance — [item 2](./002-agent-credentials.md)
closes on it. A broker remains available and unbuilt.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## The question item 2 left open

[Item 2](./002-agent-credentials.md) ended on a distinction it could state but
not explain: *"Running several agents off one credential is already known to
work (the bwrap jails do it), but they share one file; that answers concurrency,
not divergence."* Field experience matched — a shared home keeps every agent
signed in, a capsule holding a **copy** of `.credentials.json` works for a while
and then loses auth, and re-pushing a known-good copy does not rescue it.

The standing explanation was server-side: Anthropic fingerprints the machine and
busts a session whose id has moved. That mattered here, because a capsule is a
different machine by construction, and if it were true no amount of careful
carrying would help.

## What it actually is

It was probed against Claude Code 2.1.223 on 2026-08-14 — a static read of the
shipped bundle plus live refreshes. Doctrine holds the record: `EVD-024`, which
carries the method, the identifiers to re-grep, and the numbers. In short:

- **Refresh rotates the refresh token, every time.** There is no read-only
  refresh, so exactly one process-group may refresh a given credential.
- **A shared home is not sharing identity — it is sharing concurrency control.**
  The client compare-and-swaps on one `.credentials.json`, commits only if the
  on-disk token is still the one it started from, and has a named branch for
  losing the race. That, and nothing else, is why the bwrap jails coexist.
- **The logout is local.** A copy that loses the race gets `invalid_grant` and
  the client **zeroes its own credential file**. It presents as a server-side
  lockout; no fingerprint is involved, and the refresh request carries nothing
  device-derived.
- Re-pushing a good copy cannot fix it: the copy is invalidated by the source's
  next refresh.

So item 2's write-if-absent instinct was right for the wrong reason. The hazard
is not that the two copies *drift*; it is that they are two claimants on one
rotating grant, and the loser destroys itself.

## Why none of that has to be solved

The problem is avoidable rather than manageable. `claude setup-token` mints a
**one-year** OAuth token, prints it, and saves it nowhere — a grant separate
from `.credentials.json` that never joins the rotating lineage. Set it as
`CLAUDE_CODE_OAUTH_TOKEN` and a capsule authenticates on its own grant: no
rotation, no compare-and-swap, no self-destruct, and none of the ~5-day absolute
re-login clock that governs a `/login` grant.

It is also *less* credential material across the boundary than the payload item 2
built. A capsule needs no `.credentials.json` and none of the four `.claude.json`
keys — the account data those carried exists to be folded back in by a refresh
that no longer happens.

The trade is exposure: one year rather than the eight hours a broker could hold
it to, in a guest confined precisely because it is not trusted. Doctrine's
`DEC-220` records that as a decision rather than a discovery — taken because the
capability was blocking work, the blast radius is acceptable at single-user,
few-capsule scale, and a shared multi-user host is a different deployment that
account-sharing terms route toward API keys before this trade is even reached.
One known-unknown rides with it: **no published doc describes revoking an
individual `setup-token`**, so containment after a compromise may mean
re-authenticating the account rather than killing one grant.

## The broker, if it is ever wanted

A host-side broker holding the sole lineage and handing out short-lived access
tokens would cap guest exposure at eight hours. It is genuinely available: the
compare-and-swap write-back was exercised live and works, and a `setup-token`
can authenticate the broker itself, so it would not inherit a re-login clock
either. Two things to know before starting:

- **`apiKeyHelper` is the wrong pipe** despite fitting perfectly — a shell
  command, live-reloaded, with a TTL. The client branches on credential *shape*:
  an object with an access token becomes `Authorization: Bearer`, otherwise
  `X-Api-Key`. The helper yields an untyped string that lands in both headers, so
  it is API-key-typed at the seam whatever is fed to it.
- **The elegant path is undocumented.** The SDK control protocol has an
  `oauth_token_refresh` request — the child asking its host to refresh, exactly
  this topology — but it is absent from the published SDK reference and gated on
  an entrypoint allowlist. It would be scraped, not supported.

`CLAUDE_CODE_OAUTH_TOKEN` and `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` are both
documented, so a broker needs no internals. Note the second hands over a
*refresh* token, so everything above applies to it in full: safe only where the
consumer owns its own grant.

## What is actually running

Neither. The orchestrator passes the token inline in its `tmux` environment, and
credential management is a convenience rather than a requirement — which is the
honest end state for a single operator, and the reason the broker is recorded
here instead of built.
