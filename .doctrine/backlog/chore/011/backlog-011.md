# CHR-011: Run a provision through the front end on a live slot

`capsule <slot> provision <ref>` and `capsule <slot> setup <ref>` have **never
run on a live host since `NOTES item 51` step 4**, and that step's own smoke test
was a `capsule all status` and a collect — neither of which goes near this path.
The switch (`CHR-001`) has since landed, so the fixes below are installed and
still unexercised.

Three bugs sat on it, all found by a stub in `policyCases` and all fixed in the
same commit (`NOTES item 51`, *three bugs, none of them step 6's*):

- `recordProvisioned` grew a `<profile>` parameter and the call site never grew
  the argument, so the **ref** landed in the profile's place and the provision
  died *after the code had been pushed into the capsule*.
- `setup)` passed `$provisionProfile`, which only the other `case` branch sets —
  an unbound variable under `set -u`, also after the push.
- Older than both: `oid=$(observed "$n" | cut -f1)` is a bare assignment, and
  `observed` returns 1 for a guest that does not answer, so `pipefail` plus
  `set -e` killed the function silently. The "guest did not answer for its HEAD"
  branch had **never been reachable**, and its message had never printed.

All three sit past a `work` call, which is why only a stub could reach them.
That is the point of this item: a stub proves the branch **runs**, and a stub
that agrees with the program it stubs proves nothing about the program the front
end actually hands to — `program()` returns the module path only when the slot
has a relay socket, and the bare name otherwise.

What to run, against a slot whose result is already safe (never `d`):

1. ~~`capsule <slot> provision <ref>` and read the record — `base.ref`,
   `base.oid`, `profile`, and a `gen` bump.~~ **Done, `capsule c provision edge`,
   2026-08-17.** Bug 1's branch is **taken**: the record carries
   `profile: doctrine`, `base.ref: edge`, `base.oid: 1c3f112d2`, generation 5, and
   the pin `profile_snapshot: sha256:9e1e49e0…`. Nothing died after the push.

   Two things the run showed that the item did not predict. **`base.ref` and
   `base.oid` disagree by design**: `edge` is `2076df5fb`, but
   `recordProvisioned` reads the guest's HEAD *after* the refresh, and doctrine's
   refresh commits — so the oid is the refresh's commit (item 47's shape, read off
   a record for the first time). And **the guest is left dirty by its own
   refresh**: one untracked directory, zero modified tracked files. The status
   column's `dirty` counts both classes; the guest's pre-receive hook refuses only
   on modified tracked ones. A provision leaves a slot that reads `dirty yes` and
   is nonetheless pushable.
2. `capsule <slot> setup <ref>` on a fresh slot, which is the branch that
   resolves its own profile rather than reading the other branch's variable, and
   ends in a baseline or in the message that says the profile declares none.
3. Bug 3's branch on purpose: provision against a slot whose guest is **not
   answering**, and check the message prints rather than a silent exit 1.

Step 3 is the one no live run will produce by accident, and the only one that
buys **take** rather than **trigger**.

Related: `CHR-003` provisions a free slot as step 1, but its subject is the
profile pin and its assertions are the `*`/`!` markers — a chore whose steps
happen to cross a path is not evidence for that path.

Evidence rung (`STD-001`): bug 1's branch is **taken** on a host. Bugs 2 and 3 —
`setup)`'s own profile resolution, and the guest-did-not-answer message — are
**built**, and a stub has **run** them. Step 3 is still the only one that cannot
happen by accident.
