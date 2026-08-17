`host/programs.nix` builds each guest-facing program once per transport, and the
front end picks the copy that can reach the slot. The copies do not fail in the
same order.

Observed 2026-08-17 on slot `f` (declared, never created, no relay socket):

- `capsule f refresh --profile panopticon` reached the program's **profile**
  logic and refused for `refresh = null`.
- `capsule-refresh --capsule f --profile panopticon` straight off `PATH` never
  got there: its transport refused first with *"no way in to capsule 'f':
  /run/capsule/f/ssh.sock is not a socket."*

**Why it matters beyond the message.** A branch you can reach through one copy
may be unreachable through the other, so "I ran the program and it did X" is an
answer about *a* copy. It also decides where a case suite can pin a branch: the
absent-path ordering in `refreshInvoke` (`IMP-004`) had to be pinned against the
**fragment**, because the shipped program's transport refuses before either line
runs.

Sibling of [[mem.fact.oubliette.devshell-programs-shadow-the-modules]] and
[[mem.fact.oubliette.two-paths-cannot-probe-each-other]]: same family — which
copy answered — one axis over.
