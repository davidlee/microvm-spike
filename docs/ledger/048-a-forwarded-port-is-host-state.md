# NOTES item 48 — a forwarded port is host state, and nothing allocates one

*State: **open, and nothing is built.** Moved here from
[Plan D](../plan-d-fleet.md) L10 / S9, which is the one limitation in that file
with no direction covering it — so it had a description and no home. Nothing here
is a decision; what it records is the shape the already-decided rules give it, so
that whoever builds it does not have to re-derive them.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

## What works, and it is more than it looks

The door is ssh with a `ProxyCommand` over the relay socket, so a host port
already reaches a guest port:

```
ssh -L 3000:<guest>:3000 …   # through the same door capsule <n> ssh uses
```

Nothing new is needed for *reach*. That matters, because "port forwarding" sounds
like a channel this repo does not have and it is a channel this repo already has.
What is missing is everything around it.

## What is actually missing is allocation, and it is host-side

Three things, none of which the ssh invocation supplies:

- **Nothing allocates.** Two capsules serving on guest 3000 both want host 3000,
  and the second one silently loses to `bind: Address already in use` — or, worse,
  to the first capsule's server, if the human forgets which terminal is which.
  At N=1 that is invisible. Plan D is the file about N not being 1.
- **Nothing records.** No column says which capsule owns which host port, so the
  question *what is on 3000* is answered by `ss -lntp` and a memory.
- **It cannot be said through the CLI.** `capsule <n> ssh` passes trailing
  arguments as the **remote command**, correctly — it takes argv rather than
  interpolating text ([CLAUDE.md](../../CLAUDE.md)) — so a `-L` has nowhere to go
  and the whole `ProxyCommand` is reconstructed by hand each time.

## Three rules this repo has already decided settle most of its shape

Worth writing down now, because each of them was expensive once and none of them
is obvious from inside this problem:

- **The guest never chooses.** A capsule naming its own host port is the same
  class as a project naming its own allowlist — the exposure is *authority*
  rather than reach, and the answer is the same one
  ([item 25](./025-assignment-is-a-perimeter-verb.md),
  [item 36](./036-a-policy-is-selected-not-named.md)): the host declares what may
  be selected and an assigner selects within it. A guest asking for a forward is
  also [item 18](./018-git-channel-direction.md)'s inversion re-proposed, which
  has now been declined three times in other clothes.
- **The allocation belongs in the record, not in a program.** A program may not
  read host state ([item 20](./020-which-capsule-a-program-means.md)) and the
  record is front-end written
  ([item 29](./029-the-record-is-front-end-written.md)), so the shape is a field
  on the assignment plus a front end that resolves it — the same two steps
  `--unit` and `--policy` already take.
- **A slot has no default and neither has a port.** Whatever is built refuses
  without one rather than picking 3000
  ([item 28](./028-a-slot-has-no-default.md)).

## It is not a perimeter verb, and the bind address is the reason

Worth stating because the name suggests otherwise. A forward is the *human's*
existing door used in the other direction: the guest gains no egress, no route
and no listener it did not have, and the perimeter — a host-side proxy the guest
cannot reach ([CLAUDE.md](../../CLAUDE.md)) — is untouched. `ssh -L` binds
loopback by default.

What *would* be a perimeter change is `-g` or a `0.0.0.0` bind, which publishes a
confined guest's service to the host's network. So the control is the **bind
address**, it is one word, and it is the one thing a verb here must not take from
an assigner without a declaration behind it.

## What to be careful of, when somebody builds it

- **A fixed port per slot** — `3000 + index` — is the cheap answer and it fuses
  two axes: it collides across targets that both want a conventional port, and it
  spends the pool on slots that serve nothing. The pool is ten
  ([item 30](./030-a-pool-audits-what-exists.md)); conventional ports are fewer.
- **A long-lived host-side listener is not the same object as an ssh session.**
  The forward dies with the session that holds it, which is
  [Plan D](../plan-d-fleet.md) L9 — the same missing thing as a detached agent
  (D6), and a reason to build the two in one breath rather than to build a
  daemon here.
- **Nothing should probe for a free port.** A program that picks by trying is a
  program whose answer depends on host state it did not record, which is the
  class item 20 is about; allocate from the record and refuse on collision.
