# CHR-002: Exercise item 53's three verbs on a live slot

**The premise this was written on is stale, and by more than a little.**
`handoff` has run on this host **twice**, not in a sandbox. The evidence, all of
it read off the host rather than inferred:

- `refs/capsule/e/gen/7/heads/work` and `.../gen/7/state/implementation` in
  `~/dev/doctrine` — that is the archive step in the verb's own naming,
  `refs/capsule/<dst>/gen/<n>/`. A hand-run sequence does not produce
  generation-keyed archives.
- `d`'s record has `base.ref = refs/capsule/c/heads/work`; `e`'s has
  `refs/capsule/d/heads/work` at generation 7, purpose *SL-251 audit of d*. A
  chain of two handoffs, c→d→e.
- `capsule e fetch` answers `code: landed / state: landed`.

So **the verify, the archive, the drop and the force have taken** on a live host.
What is actually left is narrower:

1. **`land`'s report** — ahead/behind against doctrine's own `HEAD`, the
   conflicting paths a merge would produce, and `--branch <name>`'s create-only
   refusal against a name that already exists. Nothing observed says a `land` has
   run; the verb writes no ref without `--branch`, so its absence leaves no trace
   either way.
2. **The two refusals**, which are `trigger` and nothing has triggered them: a
   stale exhibit (guest head ≠ quarantine tip), and a modified tracked file read
   from the exhibit.

Both `handoff` and `land` collect first and then refuse unless the guest's head
is one of the objectnames the quarantine's code refs hold. There is **no
`--stale`**, whose corollary is that both need the source *running* — and the
fleet is stopped by default now, so any further exercise starts with a `sudo
capsule <slot> start`.

**One correction to this item's own reasoning about `c`.** It said *"`c`'s work
has already migrated to `d`, so neither destination costs a live assignment"*.
That is true of `c`'s **commits** and was checked no further. `c`'s guest also
held a modified tracked file — 81 lines of SL-251 harvest notes — which `d`'s
base commit does not carry. It turned out to be safe (byte-identical to
`refs/capsule/e/state/implementation`, and superseded by a longer version at
doctrine's `HEAD`), but it was safe by luck rather than by the check this item
described. **A slot whose commits have migrated is not a slot whose work has
migrated**; the question is answerable in one command, `capsule <slot> collect`,
and that is what a destination should cost.

Needed CHR-001 first, which is resolved.

## Observed on a live host, 2026-08-17 — all of it on slot `d`

`d` was the subject rather than `c` for the reason the correction above gives:
its commits *and* its work had migrated to `e`, its guest tree was clean at
`95c1412f9` on branch `work`, and nothing in it was driving anything. `c` stayed
untouched. `sudo capsule d start` reported the guest not answering ssh inside a
minute and injected nothing; it answered a few seconds later, and nothing here
needed the injection.

**1. `land`'s report — taken.** `capsule d land`, guest at its branch tip:

```
capsule d: code: landed / state: landed
capsule d: against edge — 3 commit(s) here that it has not, 87 there that this has not
  and a merge would conflict on:   [13 paths]
```

The branch name is read off the repo (`symbolic-ref`) and is `edge`, which is
what `~/dev/doctrine`'s main checkout has HEAD on — the verb named a branch
without ever having chosen one, which is the property the code claims. The
conflict list is `merge-tree --name-only` and is real: ten `.doctrine/` records
and the three `install/agents/claude/capsule-*.md` files.

**2. `--branch <name>` — both halves, taken.** `--branch chr-002/land-probe`
against a free name created it: `capsule d: chr-002/land-probe is at 95c1412f9
in /home/david/dev/doctrine`, then the report. The **same command again**
refused:

```
fatal: update_ref failed for ref 'refs/heads/chr-002/land-probe': cannot lock ref …
capsule: /home/david/dev/doctrine already has a branch 'chr-002/land-probe', and a land never
  moves one — that is how nothing it does can lose a commit.
```

Exit 1. The create half was run **first on purpose**: a refusal against a name
that was never going to be written is a refusal nobody can tell from a no-op.
The branch was deleted afterwards (it was at `95c1412f9`, `d`'s tip).

**An ordering worth knowing**: the create-only refusal exits before the report,
so a `land` that names a taken branch prints no ahead/behind and no conflict
list at all. The remedy it prints — `refs/capsule/d/heads/*` — is a ref and not
a report.

**3. The stale exhibit — taken, and it needed a detached HEAD.** A guest commit
does not go stale: `land` collects first and the collect's refspec is
`+refs/heads/*` (`host/git-channel.nix:536`), so any new commit on a branch is
in the quarantine by the time `verifyExhibit` looks. What is *not* is a HEAD
that is no branch tip. `git checkout --detach HEAD~1` in `d`'s guest, then
`capsule d land`:

```
capsule: 'd' is at f869433c3 and the collect that just ran did not
  take it — so the guest has moved since, or the collect did not
  reach it. What the quarantine holds:
    95c1412f9  capsule/d/heads/work  19 hours ago
```

Exit 1, and it refused **before `fetchSlot`** — doctrine's `refs/capsule/d/*`
were untouched by that run. The control is step 1 above: same command, same
slot, reattached guest, exit 0.

**4. The modified tracked file — taken, and it produced `ISS-006`.** One tracked
file dirtied in `d`'s guest (`README.md`), nothing untracked. The quarantine was
read *first* — `dirty: 1`, one `diff --git` in `.capsule/dirty.diff` — because
`handoff` refuses on `dirtyTracked > 0` and a zero there would have carried the
command past the refusal into a real provision. Then
`capsule f handoff d --purpose …` refused, before any fetch and before touching
`f` at all. Its closing parenthetical is wrong, which is `ISS-006`.

**Left as found**: `d`'s guest is clean, on `work`, at `95c1412f9`. In
`~/dev/doctrine`, `refs/capsule/d/heads/work` is unchanged and
`refs/capsule/d/state/implementation` advanced `269a98ee7 → ed275f7e0` — a newer
clean snapshot of the same slot, which is what any `capsule d fetch` writes.
`d` is left **running**; stopping it needs the human's sudo.

**Not exercised**: `handoff`'s own report path on a live host was not re-run —
it is `taken` from the two prior handoffs this item already documents, and
nothing in this session's four runs touched it. `land` against a repo with no
commit on `HEAD` (the early-exit at `host/cli.nix:1875`) is unreachable on any
real target here.

Evidence rung (`STD-001`): the archive, the drop, the force and the verify were
already **taken**. `land`'s report, `--branch`'s create and its refusal, the
stale exhibit and the tracked-file refusal are now **taken** as well.
