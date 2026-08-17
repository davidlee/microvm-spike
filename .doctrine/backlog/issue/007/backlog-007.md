# ISS-007: A fetch half is a glob refspec, so it can half-land

**`capsule <slot> fetch` moves each half with an unforced glob refspec and no
`--atomic`, so one ref in a half can land while its sibling is rejected — and
the line printed says the whole half refused.** Read from source; not observed.

## The mechanism

`fetchSlot` (`host/cli.nix:1144-1171`) fetches the two namespaces separately —
that separation is deliberate and `NOTES item 50`'s finding: the halves have
opposite failure modes, so a pair-atomic fetch would refuse a
state half that was fine. Within a half it runs:

```
git -C "$repo" fetch "$q" "$ns/*:$ns/*"
```

Two properties make a partial result reachable:

- **Unforced, on purpose.** The rejection is the only reason a first
  assignment's code still exists anywhere (item 50), so a non-fast-forward ref
  must be refused rather than clobbered.
- **A glob, so more than one ref per half.** The code half is whatever the guest
  pushed — `capsule-collect` fetches `+refs/heads/*`
  (`host/git-channel.nix:546`), any number of branches. The state half is
  per-stage — `refs/capsule/state/<stage>` (`host/brief.nix:343`,
  `host/state-snapshot.nix:71`).

`git fetch` without `--atomic` updates each ref independently: a rejected ref
does not roll back the ones already written. `capsule-collect` takes the flag
for exactly this invariant and says why (`host/git-channel.nix:586` — "nobody
observes a result commit without the capsule state that goes with it"). The
host-side fetch does not.

## What it says when it is wrong

A reassignment that diverges one branch and fast-forwards another lands the
second, refuses the first, and prints:

```
capsule <slot>: code: refused
```

The remedy under it — archive under `refs/capsule/<slot>/gen/<n>/`, then fetch
again — is still correct, but the repository is already holding a mix, and the
line naming the half gives no way to tell which refs moved. That is item 50's
own complaint (a repository left holding one assignment's code beside another's
state, by a verb that named neither) reproduced one level down, inside a half.

Same shape for the state half across two stages, which is the likelier one: a
handoff's source and its own stage chain need not agree.

## The fix

Add `--atomic` to the fetch in `fetchSlot`. Per-half, not per-pair — the pair
stays split, for item 50's reason. Then a half is all-or-nothing and the
`landed` / `refused` line is true of every ref in it.

`policyCases` already has the fixture: `host/policy-cases.nix:359-427` builds
two commits off one base and a state chain that fast-forwards over them, and
runs `fetch` on agreeing and disagreeing halves. A round needs one more branch
in the code half — one divergent, one fast-forwarding — asserting the
fast-forwarding ref did *not* move when its sibling was refused. Mutate by
dropping the flag and watch it go red.

Evidence rung (`STD-001`): the defect is **read** from source and from git's
documented per-ref behaviour — **not run**. No host run has put two refs in one
half in disagreement.
