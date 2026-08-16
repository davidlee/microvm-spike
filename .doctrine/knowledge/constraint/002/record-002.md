# CON-002: generation is read and never checked

`generation` is read once and still never checked. `capsule <slot> fetch` names
`refs/capsule/<slot>/gen/<n>/` off it when a half is refused, and `handoff`
renames by it — but **nothing refuses on it**.

The refusal half — a command stating the generation it acts for, so a stale
controller is **told rather than obeyed** — waits for D6 (`IMP-002`,
`NOTES item 46`).

Why this is a constraint and not a bug: **nothing today can be stale**, so
nothing today notices the rest of the field is inert. Sessions are attached and
one controller acts at a time. Detached sessions are what create the staleness
the refusal exists to catch, which is why the two arrive together or not at all.

Removed by `IMP-002`.
