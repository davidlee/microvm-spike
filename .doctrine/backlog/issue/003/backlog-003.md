# ISS-003: A dirty-worktree push refusal offers `--force`, which cannot fix it

`capsule-provision`'s refusal (`host/git-channel.nix:288-290`) names two causes
and one remedy:

```
capsule-provision: push refused. Either the guest's worktree is
  dirty (finish or collect first), or this would discard commits
  the guest has made — 'capsule-provision <ref> --force' to insist.
```

`--force` addresses only the second cause. The first is the guest's own
pre-receive hook refusing a push into a checked-out branch with modified tracked
files, and a force-push does not make a hook accept anything — the flag sets `+`
on the refspec, which permits a non-fast-forward and nothing else.

**Observed, 2026-08-17.** `just provision c edge --force` on a slot with one
modified tracked file. The remote said `! [remote rejected] … (Working directory
has unstaged changes)`; the refusal below it advised the flag that had just been
passed. Two readers in a row — the operator and an agent — concluded the flag had
been dropped by the `just` recipe or the front end, and went looking through
`justfile`, `host/cli.nix`'s `work()` and `provisionSlot`, and
`capsule-provision`'s parse loop before reading the remote's own line. The message
sent both of them the wrong way.

The information needed to say which cause applies is already on the operator's
screen, one line up, in git's words. Options, cheapest first:

1. Say which remedy goes with which cause, and mark the dirty case as one
   `--force` does not reach.
2. Read the push's stderr and print only the branch that matches — `Working
   directory has unstaged changes` is the hook's own wording, so matching on it
   couples this program to a message the guest's hook emits, which is a real cost
   and is why this is not obviously the right answer.
3. Ask the guest before pushing. It already answers `dirty` for the status column
   (`host/observe.nix`), so a pre-flight read would let the refusal be specific —
   at the price of a round trip on the happy path, and of a check that can go
   stale between the ask and the push.

Note what is *not* wrong: `--force` may go either side of the ref
(`host/git-channel.nix:139-141`, deliberately a loop rather than positional
tests), the `just` recipe forwards `*flags` correctly, and `work()` and
`provisionSlot` pass the original argv through. Every layer behaved; only the
sentence was wrong.

Related: `CHR-011`, which is the provision path's live exercise, and observed the
same run's other surprise — a provision leaves the guest reading `dirty yes` from
its own refresh's untracked output, while the hook cares only about modified
tracked files. Two notions of dirty with one name is part of why this message can
be read the wrong way.

Evidence rung (`STD-001`): **taken** — the misleading branch printed on a live
host and misdirected two readers.
