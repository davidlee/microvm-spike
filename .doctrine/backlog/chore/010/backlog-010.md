# CHR-010: Exercise capsule start and stop's two message branches

`capsule <name> start|stop`'s epoch-scoped journal tail is verified both
directions against a **live, healthy** unit. The two branches that print a
message when the unit is *not* healthy have never been taken — they need a
stopped or failing unit.

This is `NOTES item 40`'s class exactly: a refusal nothing had triggered.

While you are there: `capsule all status`'s unit column distinguishes `running`
from `auto-restart`, and `auto-restart` is a crash loop rather than a state.

Evidence rung (`STD-001`): currently **run** on the healthy path. This buys
**take** on both branches.
