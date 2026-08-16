A tree that comes out of a capsule is **attacker-shaped input**. Three classes,
and where each is already handled is not where you would guess (`NOTES item 34`):

- A `..` or `.git` **path component** is refused **twice already** —
  `transfer.fsckObjects=true` at `capsule-collect` errors `hasDotdot`/`hasDotgit`,
  and `git read-tree` refuses `invalid path`.
- A **symlink target** and a **gitlink** sail through both.

`git archive | tar -x` then plants `-> /etc/passwd` in your worktree and turns the
gitlink into an empty directory, **exit 0, silent**; nothing escapes until the
next thing that greps or copies the exhibit.

And **refusing every `..` target refuses doctrine's own tree**, whose
`.doctrine/slice/N/phases -> ../../state/slice/N/phases` is inside the root and
load-bearing.

The rule: **lexical resolution within the extraction root**, against the tree and
never with `realpath` — plus **git's own writer** (`read-tree` into a temporary
index, `checkout-index` out of it) rather than a second one made of shell.