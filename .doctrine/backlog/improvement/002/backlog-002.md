# IMP-002: Plan D D6 — detached sessions

`docs/plan-d-fleet.md` §9 order of work, step 7. Wanted when N > 2 stops being a
probe and starts being a Tuesday.

Carries two things nothing else will:

- **L9, the *is an agent running* column.**
- **`generation`'s refusal half** (`NOTES item 46`). `generation` is read once
  and never checked today — see `CON-002`. Nothing can be stale until sessions
  detach, which is why the field is inert rather than broken.

Slice-sized (`ADR-001` term 1).

Evidence rung (`STD-001`): unbuilt.
