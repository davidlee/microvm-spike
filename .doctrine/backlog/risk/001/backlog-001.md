# RSK-001: The sideband arc has only ever run forwards

Every refusal the sideband arc has met is one of the **two that happened to
fire** — a non-fast-forward push, and the ambiguity of an over-collected tree.

Never reached by a real capsule:

- the `code-oid` mismatch,
- a dirty destination worktree,
- an over-budget state half.

And the guest's own `code-oid` refusal is now reachable **only** by HEAD moving
mid-flight, which narrowed the window rather than closing the gap.

This is `NOTES item 40` and `NOTES item 41`'s class — refusals built, evaluated,
shellchecked and shipped, with the conditions selecting them never once true.
`NOTES item 1`'s *what has actually been run* section names it as one of four
outstanding gaps.

**Mitigation** is not a code change: it is triggering each refusal once, on
purpose, and reading which line fired rather than the exit status. Two rules from
the case suites apply — assert the *reason* as well as the status, since a
refusal for the wrong reason is a different program passing; and check the path
can fail by mutating what it pins.

Evidence rung (`STD-001`): **taken** for two refusals, nothing for the other
three.
