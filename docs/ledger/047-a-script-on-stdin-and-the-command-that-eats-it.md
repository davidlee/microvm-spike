# NOTES item 47 — a script on stdin, and the command that eats it

*State: **found on the path to [item 42](./042-a-state-half-no-capsule-has-held.md)'s
delivery, fixed twice over, cased, switched — and the delivery it was blocking has
run.**
`host/refresh.nix`'s runner arrives on the guest's stdin and doctrine's `refresh`
command reads stdin, so **everything after `( ${command} )` in that script had
never executed** — not the status check, not the `after` snapshot, not the commit,
not one of its five messages. A refresh that failed reported success. And the
tracked change it left behind refuses the next provision and every
`capsule-brief`, which is how it was found. The fix is `</dev/null`; the suite
written to pin it found a **second** defect underneath, and the ordering problem
neither of them causes is resolved by `capsule-provision --state-from-host`.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## How it was found

[HANDOVER](../../HANDOVER.md)'s sequence, on slot `e`, at step 4. `capsule e
provision de32c856b` landed, `capsule e brief --from-host` took the host-side
`code-oid` precheck for the first time ever — correctly, naming both commits and
writing nothing — and then the fast-forward to the host's HEAD was **refused by
the guest**:

```
! [remote rejected]  582300f14 -> work (Working directory has unstaged changes)
```

On a capsule provisioned ten minutes earlier, that nobody had ssh'd into. One
tracked file modified: `skills-lock.json`, rewritten by
`doctrine install --agent claude --agent pi -y`, which is `target.nix`'s
`refresh`.

## The mechanism

`host/guest-exec.nix`'s `loginRun` is `bash -l -c 'bash -s'` and the script is
redirected into it. **The script is the guest bash's stdin.** So a command inside
the script that reads stdin does not read the operator's terminal — there isn't
one — it reads *the rest of the script*, and bash then has nothing left to
execute and exits 0.

Confirmed over the live channel, same transport, same invocation:

| script | `MARK-A` before the command | `MARK-B` after it |
|---|---|---|
| `cat >/dev/null` between them | printed | **absent** |
| `doctrine install …` between them | printed | **absent** |

The control is there because the second line alone does not distinguish a
truncated script from a command that exited. It is the same result, and the
target's command is a TUI: it opens stdin, drains it, and is indistinguishable
from `cat` at this boundary.

## What has therefore never run

Everything below `( ${command} )` in `host/refresh.nix`, which is most of the
file and all of its reasoning:

- **The failure branch.** `if [ "$status" -ne 0 ]` and its two messages. A
  refresh whose command fails is silent and returns 0. The header's third bullet
  — *"a refresh that fails must be **loud**, because a checkout whose derived
  state did not regenerate is exactly the stale-authority trap — and it fails by
  absence, which reads as fine right up until something answers from it"* — is
  the exact description of what the program does, written by the program's own
  author as the thing to avoid.
- **The commit.** `git commit -a -m "capsule: refresh"`, the one write this
  system makes to the agent's branch, together with the precondition paragraph
  that makes it safe and the `before`-non-empty refusal that guards it.
- **`capsule-provision`'s `the code landed and the refresh did not`.** Unreachable
  for this target: `ssh` returns the truncated script's 0.

And one thing that *had* run and was misread — see the second defect below, which
is that misreading turning out to be a real bug one layer down.

## Why no check saw it

- `guestExec.checked` runs shellcheck over the runner at build time. This is a
  run-time truncation of a lint-clean script; there is nothing to object to.
- The refresh had no case suite, and the seam that would carry one was half
  there — `command` was an argument to the *file* but not to the runner, so the
  text could not be instantiated twice. It is `refreshFor cmdline work` now, the
  same shape as `snapshotFor`, and `refreshCases` is the fifth instance of the
  third kind of check.
- Every observation of a provision was of its **output**, and the output is the
  target command's. It ends in `Done!`, prints a great deal, and stops precisely
  where the script does.

**The suite's invocation is the load-bearing part of it.** These cases run the
runner as a guest does — `bash -s` with the script on stdin — because the defect
is a command *inside* the script reading that stdin. A suite that ran
`bash <script>` would pass against the broken text: the same vacuous-pass shape
as a probe asserting a convention it spelled itself
([item 38](./038-a-probe-that-became-a-borrower.md)). There is a control case for
the same reason, a command that writes the same file without touching stdin, so a
suite that failed everywhere could not be read as this finding. Watched red on
both halves of the fix reverted, one at a time.

## The second defect, which the suite found and the host had hidden

The first diagnostic ran `capsule-refresh` against the already-dirty checkout,
got a silent 0, and read it as `[ "$before" = "$after" ] && exit 0` — porcelain
naming a file rather than its content, so a rewritten hash looks like no change.
That reading was withdrawn, correctly: the same silent 0 came back from a
**clean** tree, where the branch cannot be taken. A silent success has more than
one cause and the cheap one was not it.

**It was true anyway, and only the truncation was hiding it.** With the redirect
in place, the already-dirty case still exited 0 where it should have refused:
`before` and `after` were both ` M skills-lock.json`, identical *lines* about
different *bytes*. So the one refusal that exists to say `there is no way to tell
your edit from mine` was unreachable in precisely the case it is about — a
refresh rewriting a file that was already modified, which is doctrine's situation
exactly. The snapshots are `git diff HEAD` now: content, staged changes included,
untracked still excluded, which is the distinction the surrounding paragraph was
always making and the status form could not express.

Worth naming as a class rather than a fix: **`--porcelain` answers *which files*,
and a program comparing two of its readings is asking *what changed*.** Those are
the same question only while no file is written twice.

## What it blocks, and this is the part that is not one line

The fix to the truncation is `</dev/null` on the target's command. That does not
unblock [item 42](./042-a-state-half-no-capsule-has-held.md); it moves the
refusal. For a target whose refresh writes tracked files — which `target.nix`
declares doctrine's does, in a paragraph written for this — the two outcomes are:

- **The refresh commits** (post-fix, as designed). The guest's HEAD is now a
  commit the host has not got, so `capsule-brief --from-host`'s `code-oid`
  precheck refuses.
- **The refresh does not commit** (today). The worktree is dirty, so the brief's
  own dirty-checkout rule refuses — and so does the next provision's push.

So **`capsule-brief --from-host` is structurally unreachable on any target whose
refresh writes tracked files**, and `target.nix:193` says doctrine's is one. Item
42's sequencing price — *provision at the commit the checkout is on, then brief*
— cannot be paid, because step 3 of a provision moves or dirties the thing step 1
established. `target.nix` already names half of this cost (*"a capsule whose
refresh commits has a `work` branch ahead of what the host pushed, so
re-provisioning it wants `--force`"*) and stops one step short of the half that
matters: a branch ahead of what the host pushed is also a HEAD that `code-oid`
refuses.

This is [item 45](./045-a-brief-is-an-origin-not-a-top-up.md) one layer down. That
item found the window closes when the *agent* starts working. This finds it can
close before the agent exists, shut by the provision's own third step.

## Decided: the brief moves inside the provision, ahead of the refresh

Not the `</dev/null`, which was never arguable. The question was **what a brief
compares against when the provision itself commits**, and the answer is that it
does not have to: there is a moment when both preconditions hold, and it is
between the push and the refresh.

`capsule-provision --state-from-host [--stage <name>] [--unit <token>]` is step
(2) of the sequence [item 33](./033-provision-is-a-sequence.md) already
described, from the origin item 42 built. The ordering comment it lands under was
already in `host/git-channel.nix` for the capsule origin — *"The state has to be
in before the refresh, because a refresh derives from the checkout"* — and this
adds a second reason to the same line: after the refresh there may be **no later
moment at all**, so a failure message that says *run it again* would be wrong.

That makes the composite the thing [item 45](./045-a-brief-is-an-origin-not-a-top-up.md)
asked for and item 42 declined to build in advance, and the two items wanted it
for different reasons that meet here. 45: a step that is easy to forget and
impossible to take late belongs to the step before it. 47: on this target there is
no *after* to take it in.

Three smaller things fell out, each a rule already in the repo pointed at a new
pair:

- **The flags refuse rather than being ignored.** `--stage`/`--unit` without
  `--state-from-host` is an argument error, on `capsule-brief`'s own rule for the
  same pair: a scoping silently dropped is a scoping the caller believes they
  asked for. Naming both origins is refused too.
- **The front end fills `--unit` here as well**, from the slot's record, because
  the scope followed the verb — a flag whose value one call site fills and the
  other does not is a scope that silently never applies
  ([items 20](./020-which-capsule-a-program-means.md), 29).
- **And `recordProvisioned` reads the original argv, not the augmented one.** It
  takes `$2` as the ref that was asked for, so anything the front end prepends
  for the program's benefit would have been recorded as the commit the slot is
  pinned to. Two readers of one argv and only one wanted the addition.

The rejected readings, for the record:

- **The refresh's commit is part of the provision, so compare against it.** The
  host would have to learn the guest's post-refresh HEAD, which is a reading of
  the guest and not of the checkout the state came from — and `code-oid` is a
  *reading of where the tree came from*, which [item
  42](./042-a-state-half-no-capsule-has-held.md) refused to turn into a claim for
  exactly this shape of convenience.
- **`code-oid` against the pushed commit rather than HEAD.** The one to be most
  careful about: it is the tempting shape item 42 named, and it passes on the
  true case and the false one alike.

Both of those weaken `code-oid`. The one that was taken weakens nothing, because
it moves *when* the question is asked rather than what it compares.

## What is built

- `host/refresh.nix`: `</dev/null` on the target's command; `before`/`after` as
  `git diff HEAD` rather than `--porcelain`; and `refreshFor cmdline work`, so
  the text has a seam and this host's instantiation is one of two rather than the
  only one.
- `host/guest-exec.nix`: the rule beside `loginRun`, where it belongs — the
  script is the guest shell's stdin, so nothing in it that this repo did not
  write may inherit that. `host/baseline.nix` satisfies it already and by a
  different mechanism, which is worth knowing rather than relying on.
- `host/git-channel.nix`: `capsule-provision --state-from-host [--stage] [--unit]`
  at step (2), with both argument refusals ahead of the push.
- `host/cli.nix`: the `--unit` fill for the new origin, and the array that keeps
  `recordProvisioned` reading the argv a human typed.
- `flake.nix`, `justfile`: `refreshCases`, 14 of them, in `just build` and
  `just cases`. Watched red on each half of the fix reverted, one at a time — the
  redirect (six red, controls still green) and the patch comparison (two red).

## Switched, run, and item 42 is delivered

All of it on slot `e`, in one command
([probes](../probes.md#the-delivery-and-what-a-provision-that-carries-its-own-state-costs)):
`capsule e provision 582300f14 --state-from-host`, **5.204 s**, of which the
refresh is 4.553 s — so the push and the whole state half are ≈0.65 s, under a
fifth of the step they make way for. `research/`, `design.toml`,
`design-journal.toml` and `phases/` are in the guest, the worktree is clean, and
HEAD is the refresh's commit on top of the provisioned one.

Three things ran for the first time ever in that one line and only one of them is
the delivery:

- **`host/refresh.nix`'s commit branch.** `capsule-refresh: committed 0ab546b6c
  — 'doctrine install …' writes tracked files`. Everything below the target's
  command had been eaten off stdin on every provision this repo has ever done.
- **The host-side `code-oid` precheck**, earlier the same session and on purpose:
  `e` at `de32c856b` against the checkout's `582300f14`, one round trip, `Nothing
  was taken and nothing was pushed`.
- **Everything past the snapshot** — the push of a host-authored state ref, the
  guest's layout, `briefDeliver`'s checks against a tree no capsule wrote. That
  is item 42's owed delivery, and item 45's *hit* is now a *deliver*.

**And the ordering claim is observed rather than argued.** `capsule e brief
--from-host`, taken immediately afterwards, refuses: the refresh's own commit
moved the guest's HEAD off the commit the checkout is on. The remedy the message
names — re-provision at `582300f14` — would end in another refresh commit. That
loop is the whole reason the brief is step (2) of a provision.

Which verb does this evidence cover, in items 37–45's terms? **Deliver**, at
last, and *exercise* for two refusals that had never fired. What it does not
cover: the guest's own `code-oid` refusal, still reachable only by HEAD moving
mid-flight, and every refusal in `briefDeliver` that a well-formed tree does not
reach.

## Considered and rejected

- **Have the refresh not commit.** Restores today's behaviour deliberately and
  hands the dirty tree to the next provision and every collect's `dirty.diff`.
  `host/refresh.nix`'s own paragraph settles this and is right.
- **Ask the target to make its refresh idempotent-and-clean.** doctrine's lock
  file records a computed hash; a repo whose storage rules are decided by what a
  jail can transport is the coupling the guinea-pig rule exists to refuse
  ([CLAUDE.md](../../CLAUDE.md)).
- **`ssh -n`, or closing stdin at the call site.** Same effect for this one
  caller and the wrong altitude: the script is *supposed* to arrive on stdin, and
  what must not inherit it is the one command in it this repo did not write. The
  redirect belongs on that command.
- **Detect it.** `host/baseline.nix` avoids this by accident of shape — it stages
  the script to a file and detaches the run with `</dev/null` (line 132) — so
  there is one caller to fix and a rule to write down beside `loginRun`, not a
  detector to build.
