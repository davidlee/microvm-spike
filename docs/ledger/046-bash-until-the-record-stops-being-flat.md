# NOTES item 46 — bash, and the three things that would end it

*State: **decided, and the decision is to change nothing.** The host programs
stay `writeShellApplication` shell. What this item is for is the *trigger*: the
conditions under which that stops being right, written down now while nothing is
under pressure, so the answer is not re-derived from taste each time somebody
notices `cli.nix` is long.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What was asked

Whether bash is still the appropriate implementation language for the host-side
CLI for the foreseeable future. Asked at the point where `host/cli.nix` had
become the largest file in the repo and the front end had grown a fifteen-verb
dispatch, a fourteen-column status table and a JSON record with a schema version.

## The failures bash is blamed for, and what they actually were

The ledger has six failures that look like a language problem. Read together
they are one class, and it is not the language:

- [Item 24](./024-set-u-not-login-shell.md) — a `set -u` script *being* a login
  shell, so `/etc/bash_logout` reads an unset guard on the way out and the shell
  reports 1 whatever the script returned. Cost a session and hid two green
  baselines.
- [Item 44](./044-a-rule-matches-a-path-not-a-name.md) — `writeShellApplication`
  prepends `runtimeInputs` to `PATH`, so the front end's `systemctl` is a store
  path and the sudoers rule names a different command.
- `wait -n` with no pids, so a child that exited before the call had already been
  reaped and forgotten, and `capsule-host` blocked while its services were dead.
- `just`'s `{{...}}` being text substitution, so `just ssh b 'echo $(hostname)'`
  answered with the *host's* name — a diagnostic that reads as the capsule's.
- A newline in a `serviceConfig` value silently deleting the rest of a drop-in.
- `host/services.nix`'s wrapper `export`ing `CAPSULE_REPO` unconditionally, so a
  caller cannot point a module-path program at another repo.

Not one of those is an expressiveness failure. Every one is **structure passed
through text or environment** — a string standing in for an argument list, a
variable standing in for a parameter — and the boundary that broke was systemd,
sudo, `just`, or a login shell rather than bash. A typed language does not fix
any of them directly, because it is not present at the boundary where each one
failed. What fixed them was the same move every time: *pass argv, take an
argument*. `capsule <name> ssh` never had the quoting bug, because a program
takes argv; `just ssh` did, because a recipe interpolates text.

So "rewrite it in a real language" is the wrong reading of this repo's own
history, and worth recording as such before somebody reaches for it during an
outage.

## What bash is buying, and it is not convenience

Three things, and the first two are structural rather than aesthetic.

**A program pushed over stdin has no version relationship with the guest.**
`host/brief.nix` and `host/guest-exec.nix` push the guest-side half at each call
rather than baking it into the guest's closure. That means host and guest cannot
skew — there is no such thing as an old capsule running an old copy of a host
program, ever. A compiled tool in the guest image buys types and immediately
re-introduces exactly the coupling that construction exists to avoid.

**The fragment seam is a text seam.** `transport`, `tools`, `snapshotFor`,
`runner`, `moduleState`, `proxyControl`, `selectCapsule` — one text, N
instantiations, the host-tying thing as an argument
([CLAUDE.md](../../CLAUDE.md)). That is what makes `guardCases`, `briefCases`,
`snapshotCases` and `policyCases` possible, and those four suites are how every
branch a live host can only reach destructively gets checked.

**Most of these programs orchestrate other programs.** git, ip, ssh, systemctl,
tar, nft. That is shell's actual domain, and it is most of the host-side lines.
Very little of this repo computes.

Worth naming, because it cuts the other way: the fragment seam is dependency
injection performed with string splicing, and a typed language would do it
*better* — a substitute becomes a value with a type instead of a spliced string.
A successor would sharpen the design rather than lose it. What it would lose is
the two structural properties above, plus `writeShellApplication` +
shellcheck-at-build, which is a type checker already paid for.

## The strain point, named

It is `host/record.nix` and `host/cli.nix`, and the tell is `jq` — around a dozen
invocations across the host side (read 2026-08-16), most of them in
`record.nix`. The assignment record is JSON with a schema version, a generation
counter, nested `base` and `class` objects, and read/write under `flock`. That is
structured data, and shell is handling it by shelling out to another language
each time it needs to look.

Today that is fine: the record is flat, every read is one `jq`, and the file can
be read in one sitting. It is fine *for a reason that can expire*, which is what
makes it a trigger rather than a smell.

## The three triggers

Any one of these firing means the question is live again. None has fired.

1. **The record stops being flat.** A slot referring to another slot, a history,
   anything where a write is read-modify-write across fields rather than a
   whole-file replacement. The nearest one is real and scheduled:
   `generation` is written and never checked, and the refusal half is
   [Plan D](../plan-d-fleet.md) D6 — which makes it a read-compare-write, which
   is the first thing here that would want a type.
2. **A case suite cannot reach a branch**, because the only interface to the
   logic is the program's whole text. The argument seam has held four times
   (`tools`, `runner`, `snapshotFor`, `moduleState`); the trigger is the first
   time it does not.
3. **A verb has to be fast.** [Item 40](./040-no-doors-is-not-the-other-shape.md)
   looks like this trigger and is not: ten seconds a row was transport inference,
   and fixing the inference fixed the timing. The trigger is a verb that is slow
   because of what it computes.

## What a successor would have to keep

Written here because the constraints are the design and the language is not:

- **The guest half stays pushed at each call**, whatever the host half is. So a
  move is host-side only, which means two languages — and *that* is the cost to
  weigh, not the rewrite. It argues for moving the whole host side at once or
  not at all, and for the front end going first, since it is the only piece that
  computes rather than orchestrates.
- **One construction, N instantiations, with the host-tying thing as an
  argument.** Not negotiable; it is what the third kind of check rests on.
- **A program takes argv and refuses without it**
  ([item 28](./028-a-slot-has-no-default.md)), and does not read host state
  ([item 20](./020-which-capsule-a-program-means.md)). Both are language-neutral
  and both are load-bearing.
- **Something that fails the build on a lint**, since `writeShellApplication`
  currently does and `hostModulePrograms` is what makes it reach every program a
  unit names ([item 37](./037-a-teardown-that-only-unnames.md)).

## Considered and rejected

- **Rewrite the front end now.** No trigger has fired, and it splits the host
  side into two languages to improve the one file that is longest rather than the
  one that is hardest. Length is not the measure; `cli.nix` is a dispatcher, and
  a dispatcher is long in every language.
- **Put a compiled guest-side tool in the image.** Reintroduces the host/guest
  version relationship that pushing-at-each-call removes by construction. The
  types are not worth a skew.
- **Parse JSON in shell rather than shelling out to `jq`.** Worse than either
  option: it is the strain point's cost without the strain point's escape.
- **A structured shell (`nushell`).** It is already in the guest's
  `dev-facilities` fragment, so it is not exotic here. It is still a shell, so it
  answers the trigger that has not fired (structured data) while giving up the
  one thing that has paid repeatedly — `writeShellApplication`, shellcheck at
  build, and a store path that *is* the program.
- **Deciding this later, without writing it down.** Two of
  [item 38](./038-a-probe-that-became-a-borrower.md)'s three findings were
  comments that were true when they were written. A decision with no recorded
  trigger is re-decided from taste by whoever next notices the file is long.
