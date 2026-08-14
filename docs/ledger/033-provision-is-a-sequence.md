# NOTES item 33 — a provision is not finished when the push lands

*State: built; **evaluated** since [item 34](./034-adopting-a-guest-authored-tree.md)'s
round built the devshell green, which is shellcheck-at-build on this program too.
Still unrun against a capsule. Step (3) of
[item 32](./032-the-sideband-channel.md)'s inbound half. Written in a jail with
no `nix`, so it has had neither a `nix build` nor a run against a capsule — the
guest script and both host programs were rendered and shellchecked by hand, and
that is [item 1](./001-what-has-been-run.md)'s distinction, not a substitute for
it.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What was asked

[Item 32](./032-the-sideband-channel.md) dropped `.doctrine/state/boot.md` from
`statePaths` on a rule worth more than the file: **state a consumer regenerates
per checkout does not travel.** A derived file delivered into a foreign tree is
stale authority, because the next tool to run there reads it as that tree's own.

That rule has a positive half, and it is what makes the drop cost nothing:
**such state comes back by being regenerated where it is needed, and that
belongs to provisioning, not to a collect.** Nothing implements it. A tree that
wants the snapshot regenerates it by hand — which leaves the control in a pair
of hands, the same shape item 32 already refuses one field over for the
allowlist's scope.

So the question is where that regeneration runs. It is not obvious, because a
program that already does exactly this exists.

## `capsule-baseline` is the capability, minus the apparatus

`host/baseline.nix` runs **a host-declared command line, in the guest's
checkout, under the guest's login shell**, and has no opinion about what is in
the command. That is the whole of what a refresh needs. It also carries three
separately-learned corrections, each of which cost something:

- **the login shell**, because `ssh host cmd` is neither login nor interactive
  and so has none of `environment.variables` — no proxy, no `CARGO_HOME`, no
  `TMPDIR` ([item 6](./006-proxy-env-login-shell-scope.md));
- **the runner as a *child* of that login shell**, because a `set -u` script
  that *is* the login shell dies in `/etc/bash_logout` and has its exit status
  replaced by 1 ([item 24](./024-set-u-not-login-shell.md));
- **pushed at each call, never baked into the guest's closure**, for item 32's
  three reasons — host-side policy about what a capsule does, a copy left by an
  older build being drift nothing reports, and a capsule with a real workload in
  it being unrebuildable without a restart.

Which class a refresh falls in is decided by the first of those. `observe` and
`state-snapshot` are deliberately *not* login shells — "nothing here reads the
guest's `environment.variables`, so item 24's trap cannot arise". A `doctrine
boot` does read them. So a refresh is baseline's class rather than observe's,
and baseline's class is where the corrections are.

**Reuse the seam.** A second hand-written `ssh … bash -l -c` gets one of the
three wrong, and item 24 is the evidence that the wrong one is silent for three
green runs.

## But it is not a `baseline` invocation

Three counts, and the third is the one that decides it.

- **Lifecycle.** `baseline` is once per capsule warmup. A refresh is once per
  *provision*: the snapshot derives from `.doctrine/` authored content, which
  every provision replaces. Firing a cold `just web-build test` to obtain a
  seconds-long regeneration is the wrong end of a three-order-of-magnitude
  ratio.
- **The record.** `history.tsv` exists to hold one figure — the cold build, the
  largest term in time-to-interactive and the one `probe/freshness.sh` cannot
  take ([item 19](./019-baseline-build-and-figures.md)). A second command inside
  that run contaminates the only measurement the apparatus is for.
- **Failure semantics are opposite.** `capsule-baseline` is deliberately not
  `set -e` — "a failing build is a result to record, not an error to abort on",
  because that is the question it asks. A refresh that fails must be loud: a
  checkout whose derived state did not regenerate is precisely the
  stale-authority trap that dropping `boot.md` was meant to close, and it fails
  by *absence*, which reads as fine right up until something answers from it.

## The shape

Extract baseline's guest-exec seam; keep two host programs over it.

- `target.nix` grows one field beside `baseline` — a command line, `null`-able
  the same way, which drops the program rather than shipping one that cannot
  work.
- `capsule-provision` runs it after a successful push, once
  `receive.denyCurrentBranch = updateInstead` has done the checkout.
- It is separately invocable, because a human who did a hand `git checkout` in
  the guest wants it too — that is the case the hand regeneration answers today.

The guinea-pig split (CLAUDE.md) is clean, and this is the shape item 32
predicted: the **capability** is *a target may declare a command that runs in a
fresh checkout once it exists*; the **value** is doctrine's `doctrine boot`. No
generic code learns what a boot snapshot is, and a target that regenerates
nothing omits the field.

## Why provisioning owns it

The reason is not tidiness. **The inbound direction is an ordered sequence of
three steps, and two of them do not exist:**

1. push the code — built;
2. materialise the state half — `capsule-provision --state <ref>`, item 32's
   reserved piece, through the same validated extraction `capsule-adopt` will
   own;
3. regenerate what neither of the first two may carry.

The case that needs all three is the one item 32 named: a fresh audit capsule
that must read the implementation capsule's phase sheets. It gets them by (2),
and it must *not* get a copy of that capsule's `boot.md` — it needs its own, by
(3), derived from the code (1) put there. Sequencing that is provision's job.
`capsule-baseline` sits after the whole sequence, not inside it.

## The thing to check first, checked wrong, and what it turned into

The worry was: a refresh must write only paths the checkout ignores, because a
tracked modification is a **dirty worktree**, and a dirty worktree is what
`updateInstead` refuses the *next* provision on — so a hook running at every
provision would break every provision after the first, one provision away from
its cause. Same class as `recordDir` having to live outside `workdir`
([item 19](./019-baseline-build-and-figures.md)).

It was measured in doctrine's own checkout and it passed: `.doctrine/state/` is
gitignored at `.gitignore:41`, `boot.md` is untracked, and `git status
--porcelain --untracked-files=no` counted the same before and after a
`doctrine boot`. **The measurement was one invocation in one tree, and the
general claim is false** — `doctrine boot` regenerates more than the snapshot,
and some of it is tracked. A clean sample is not a property, and this is the
second time in this ledger that a measurement has been read as more than it was.

So the constraint inverts into a mechanism. A refresh **may** write tracked
files; what it may not do is leave them uncommitted, because that costs twice —
the next provision refuses, and every collect from then on carries a
`.capsule/dirty.diff` full of regenerated boilerplate, degrading the one blob
[item 32](./032-the-sideband-channel.md) built because it is what an auditor most
wants to read.

**The precondition is what makes committing safe rather than a trap.** `git add
.` in a checkout an agent is working in is precisely item 32's booby trap, one
layer over: it goes off as somebody else's commit. But a provision can only land
on a **clean** tree — that is what `updateInstead` enforces — so immediately
after one, `git commit -a` can contain the refresh's output and nothing else.
No pathspec to get right, and no in-flight work to sweep up because there was
none. `capsule-refresh` therefore checks that the tree was clean *before* it ran,
and refuses to commit at all if it was not: there is then no way to tell the two
apart, and guessing means committing someone else's work under this program's
name.

Three deliberate narrowings, each of which is a judgement the mechanism declines
to make for a target: it does not commit a **half-result** (a refresh that exited
non-zero and dirtied the tree is reported, not committed); it does not add
**untracked** files, because whether a newly created file belongs in the
repository is not a thing this program has standing to decide; and it is
**inert** for a refresh whose whole output is ignored, which is what doctrine's
was believed to be.

One property came free and is worth naming, because it is what keeps such a
commit legible in a collected history: the guest's git identity is already
`capsule <capsule@localhost>` (`vm/capsule.nix`), so a refresh commit is visibly
neither the agent's nor the human's to anyone reading `refs/capsule/<name>/heads/*`
afterwards. It says what it is without being told to.

The cost, stated once: a capsule whose refresh commits has a `work` branch ahead
of what the host pushed, so re-provisioning it wants `--force`. That is the same
override that re-provisioning over an agent's own commits already wants, and
`capsule-provision`'s existing refusal already names it — a more likely path
through a message that was already there, rather than a new failure.

## Considered and rejected

- **A `guestConfig` entry.** That field renders *static content* into the
  closure and symlinks it onto the volume. Derived state is not static content:
  its value is a function of the checkout, which is the thing that arrives
  later.
- **The guest seed.** Wrong time and wrong side. At first boot there is no
  checkout to derive anything from — that absence is what makes the base commit
  an argument rather than a closure value — and a command baked into the guest
  is the drift item 32 refuses, on a volume that outlives the build that wrote
  it.
- **A guest-side hook: `post-merge`, or a path unit watching the checkout.**
  Guest-initiated, which is the direction [item
  18](./018-git-channel-direction.md) deleted. It would also be a program the
  confined agent can edit, and a control the confined thing can edit is not a
  control (`target.nix`'s opening argument, one layer in).
- **Folding it into `baseline`.** Above.
- **Leaving it to the agent's own startup.** A rule enforced by whoever
  remembers it, over a failure mode that is an absence rather than an error.

## What the extraction actually turned out to be

Smaller than "extract the seam" sounds, and the reason is worth keeping. The
invocation form **cannot** be factored into a function, because one of its two
callers composes its command line at *run* time — `capsule-baseline` splices a
staged path and a stamp that do not exist at eval. So `host/guest-exec.nix` holds
two things and not three: the build-time shellcheck both guest runners get, and
`loginRun` as a named constant for the callers that push a script on stdin.
`capsule-baseline` still spells its own `bash -l -c "bash …"` and cites the same
item.

That leaves `loginRun` with one caller today, which is the honest cost of stating
a rule in one place rather than deriving it twice. The file earns its keep on the
*other* axis: it is where the two classes of guest script are written down —
does this read `environment.variables` or not — which is the question that sorts
`observe` and `state-snapshot` (no) from `baseline` and `refresh` (yes), and the
question whose wrong answer is item 24.

## What this does not buy

Step (2) stays blocked on `capsule-adopt`: pushing a state commit *in* and
materialising it guest-side wants the same mode-and-prefix validation the
outbound extraction wants, and that program is deliberately unwritten until one
hand adoption has said what it must check
([item 32](./032-the-sideband-channel.md)).

This item is step (3) and lands alone. It is useful from the moment it exists,
on every ordinary provision, whether or not a state half ever arrives.
