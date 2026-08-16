# CHR-003: Exercise the profile pin on a live slot

`NOTES item 52` step 3 — a provision copies the target's document into the slot's
own directory and records that copy's `sha256:`, and every later verb on that
slot is pointed at *that* directory. **Never exercised live**: no capsule was
touched.

Costs nothing:

1. Provision a free slot.
2. Edit `target.nix`, switch, and read `capsule all status` for the `*` — the
   marker for a slot whose host document has moved on.
3. Corrupt the pinned copy and read the `!`.

Needs CHR-001 first.

Evidence rung (`STD-001`): the pin is built and evaluated. Step 2 buys **take**
of the drift branch; step 3 buys **trigger** of the digest refusal.
