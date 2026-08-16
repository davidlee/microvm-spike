`verifyExhibit` (`host/cli.nix:1191`) asks one question: **is the guest's HEAD
oid one of the objectnames the quarantine's code refs hold?** Not how old the
collect is — membership, because the branch a guest commits on is the guest's
business and this file has never held its name.

Both callers, `land` and `handoff`, run `collectSlot` immediately before it, and
the guest-side collect's refspec is `+refs/heads/*` (`host/git-channel.nix:536`).
So:

- **A guest commit does not go stale.** Commit anything on any branch and the
  collect one line above has already taken it; the check passes.
- **A HEAD that is no branch tip does.** `git checkout --detach HEAD~1` in the
  guest, and the refusal fires with the guest's oid and a listing of what the
  quarantine holds.

That is the only deliberate trigger, and it is what to reach for when exercising
or debugging the check. Observed on slot `d`, 2026-08-17 (`CHR-002`): guest at
`f869433c3` detached, quarantine at `95c1412f9`, exit 1 — and it refused
**before `fetchSlot`**, so the human's repo was untouched.

There is deliberately **no `--stale`** override; the remedy is a collect, which
both callers already run.

Two consequences worth carrying:

- A slot **stopped** since its last collect cannot be verified at all — there is
  nowhere but the guest to get its HEAD. In practice the collect fails first and
  the run never reaches this check.
- `handoff` refuses on modified *tracked* files **after** its collect and
  **before** any fetch or provision. When exercising that refusal, read the
  quarantine's `.capsule/dirty.diff` count first: a zero there carries the
  command straight past the refusal into a real provision of the destination.
