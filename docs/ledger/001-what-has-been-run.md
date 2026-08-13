# NOTES item 1 — what has actually been run, versus reviewed

*State: standing caveat.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**What has actually been run.** The guest boots and the agent works over ssh;
the perimeter has been exercised in both shapes — `capsule-host` in the
devshell, and the units under dedicated uids on Sleipnir
([item 11](./011-host-side-runs-as-you.md)), including the guard's teardown
against a live guest — though the unit path's git channel has since stopped
serving, and [item 18](./018-git-channel-direction.md) is why. Not exercised: a
second host, a second target repo ([item 16](./016-target-agnostic.md)), and the
VMM half of [item 11](./011-host-side-runs-as-you.md). Assume anything
documented here but not named in this paragraph is reviewed rather than run.
