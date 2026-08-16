# ISS-001: capsule-brief's gloss describes a case doctrine does not produce

`capsule-brief`'s **count is truthful and the sentence beside it is not.**

It reports `differs from its HEAD in 0 paths`, which is correct: every path
doctrine declares is gitignored, so a brief carries the runtime tier and **not**
the other agent's uncommitted tracked edits. Those live only in the exhibit's
`.capsule/dirty.diff` and are dropped at layout, by design.

So the number is right and the gloss describes a case doctrine does not produce.
The fix is the sentence, not the count.

Watch the generalisation: the gloss is wrong *for this target*. A different
target with tracked, non-gitignored declared paths would make it right. So the
replacement wording must not assume either shape — it should say what the count
measures, not what it implies.

Evidence rung (`STD-001`): **read back** — the count was correct and the
conclusion drawn beside it was not, which is item 50's rung.
