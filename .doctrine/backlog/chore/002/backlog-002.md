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

Evidence rung (`STD-001`): the archive, the drop, the force and the verify are
**taken**. `land`'s report and the two refusals are **built** and, in a sandbox,
**run**.
