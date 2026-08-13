# NOTES item 28 — a slot has no default, and a front end is where one is guessed

*State: built, unrun on this host — it wants the guest rebuild the rename wants.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**`capsules.default` is deleted, and what replaces it is not a value.** It was
defensible while the one capsule on this host was called `capsule`: the default
named the thing you were obviously talking about. [Plan D](../plan-d-fleet.md)
§0 makes a slot's name abstract — `a` is not doctrine's and `b` is not the
spare — and that turns the same default into a verb acting on a slot nobody
chose, with **nothing in the name to say it was the wrong one**. The failure
mode is the one this repo has priced twice already: at N=2 two capsules were
indistinguishable by prompt ([item 21](./021-declared-capsule-flake-attribute.md)),
and the durations were the evidence.

So the four host programs now take `--capsule <name>` or `CAPSULE_NAME` and
**refuse** ([item 20](./020-which-capsule-a-program-means.md)'s chain, one link
shorter). The `capsule` front end resolves an unnamed verb to *the capsule that
is up*, and refuses when none or several are.

**Why that asymmetry is the same rule as before, not an exception to it.**
Item 20 refused to let a program probe for which transport to use, because a
store path that guesses has the guess baked into it and both answers with it.
`host/cli.nix` already carries the other half of that decision — it picks
between the two copies of each program by looking at the host — and says why:
*picking is a front end's latitude, not a program's*. Resolving a name from
host state is the same kind of act, in the same place, and it leaves every
program below it deterministic. A `capsule-provision` on `$PATH` still cannot
be run without saying which capsule it means.

The resolution is deliberately narrow — a way in, or a running VMM, for exactly
one declared slot. Not "the lowest index", which is a default wearing a
disguise, and not "the last one you used", which is state nobody declared. On
the devshell path nothing matches, so an unnamed verb refuses there and
`CAPSULE_NAME` is the answer; that path runs one guest and never needed a name
for anything but the quarantine.

**The justfile is where this pays.** The word `capsule` was a literal in fifteen
recipes — invisible while the default capsule was called that, and wrong the
moment it was not. The delegating recipes now pass no name at all and let the
front end resolve; the ones that use the name for something of their own —
`up`, `refresh`, `load`, `proxy-log`, `reset-known-hosts` — **require** it,
which is the right posture anyway: creating and destroying a slot is not
something to do to whichever one happens to be running.

## The other half: `capsule` is the image, `a` and `b` are slots

Renaming the instances took the flake attribute `capsule` with it, and it had to
come back — as a different noun. A runner is `microvm@<hostName>` in the process
table, one string for every capsule because there is one image (item 21), and
every probe both *builds* `.#capsule` and *matches* on that name. The attribute
and the process name have to be the same word, so `vms` declares the guest under
its own hostname alongside the slots, which are that same value under theirs.

The consequence to know: `nixosConfigurations.capsule` exists, so
`microvm -c capsule` would create an instance with no namespace, no proxy and no
relay — a capsule that boots into the root namespace with nowhere to go. The
front end refuses the name (it is not declared), and `just up` goes through the
front end. Nothing else guards it.

It also cost the probes nothing and bought them something: a probe's namespace
is now `cap-capsule`, which is not any slot's, so `probe-freshness` making and
destroying volumes cannot land on a declared slot's socket. Its refusal to run
beside a live capsule is unchanged — `pgrep microvm@capsule` matches every VMM
on the host, which is exactly the unscoped question that refusal wants.
