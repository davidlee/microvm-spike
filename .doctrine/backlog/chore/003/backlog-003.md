# CHR-003: Exercise the profile pin on a live slot

`NOTES item 52` step 3 — a provision copies the target's document into the slot's
own directory and records that copy's `sha256:`, and every later verb on that
slot is pointed at *that* directory.

1. ~~Provision a free slot.~~ **Done, on `c`, 2026-08-17.** The first pin ever
   written on this host: `profile_snapshot = sha256:9e1e49e0…` and
   `/var/lib/capsule/slot/c/profile/doctrine.json`, 488 bytes, mode `-r--r--r--`.
   `capsule all status` then printed `doctrine` with no marker, which is the
   control reading — pin equals host document.
2. ~~Edit `target.nix`, switch, and read `capsule all status` for the `*`.~~
   **Done, and it found `ISS-004`.** Two halves, and the second is why this step
   was worth spending rather than assuming.

   The **switch itself** was observed first: `/var/lib/capsule-profiles/doctrine.json`'s
   mtime moved while its bytes did not, so activation re-renders the document
   even when `target.nix` has not changed — item 52's activation half, which
   nothing had shown on a host before.

   The **drift** was then made discriminating rather than cosmetic: the host
   document's `stateMaxBytes` was moved to 65536 while `c`'s pin held 67108864,
   and `c`'s last exhibit was 732373 bytes. So the two documents disagree about
   whether that exhibit fits, and a verb's behaviour says which one it read.
   `capsule all status` printed `doctrine*` on `c` and no other slot — correct.
   Then `capsule c collect` reported *"732373 bytes of declared state, over the
   65536 ceiling"* and skipped the state half. **The drifted host value governed
   a verb on a pinned slot**, because `host/services.nix`'s `wrap` re-exports
   `CAPSULE_PROFILE_DIR` unconditionally on the line before it execs, overwriting
   what `slotProfileName` had just resolved. `ISS-004` has the mechanism, the
   asymmetry that makes two verbs on one slot disagree, and the fix.

   A cosmetic drift — one appended byte, as in step 3 — would have printed the
   same `*` and found nothing.
3. ~~Corrupt the pinned copy and read the `!`.~~ **Done.** Appending one byte to
   the pin moved its digest to `294977c8…` and the profile column printed
   `doctrine!`; restoring the bytes cleared it. Marker only — see below.

**The wording this item had was wrong, and it is worth correcting rather than
deleting.** There is no "digest refusal". `profile_snapshot` is read in exactly
one place — `profileCell` in `host/cli.nix` — and `capsule c collect` ran straight
through against tampered pin bytes and took a fresh exhibit. That is deliberate:
*"a digest detects a drift it cannot undo, so the pin is what a slot runs and the
digest is what says nobody has been at it"* (`host/cli.nix`, and
`contract-assignment.md`). A refusal would strand the slot on bytes it cannot
replace. Item 52's own mutation list calls it *the tamper marker*, never a gate.

**What step 1 turned up, and it is not this item's.** Every slot provisioned
before item 52's code has `profile_snapshot: null` and no pin file — `a`, `b`,
`d` and `e` are all in that state. `profileCell` keys the marker on the pin
file's *existence*, so those four print a bare `doctrine`, indistinguishable from
pinned-and-matching. The code reasons that through for a slot **nothing has
assigned** — *"there is nothing to pin it against and nothing to say"* — but
these four are assigned and merely predate the pin. They read the host document
live, so an edit to `target.nix` moves what they run with no `*` and no `!`.
Self-clearing at each slot's next provision, and it recurs whenever a record
outlives the code that writes it, which a switch makes routine.

Needed CHR-001 first, which is resolved.

**The lesson, which is this item's real yield.** A live exercise is worth its cost
only where the two states it compares would make the program behave differently.
Steps 1 and 3 confirmed what the sandbox already said. Step 2 found a shipped
defect, and only because the drift was chosen so that one document admits the
exhibit and the other refuses it — the same rule the probes are written under
(`NOTES item 37`: a round that cannot discriminate passes for the wrong reason),
applied to an operator's exercise rather than to a test.

Left behind for whoever runs the next one: the host document is drifted on purpose
while this is open, and `just system-switch` restores it from `target.nix` — the
revert costs nothing because activation is the renderer.

Evidence rung (`STD-001`): all three steps **taken** on a live host — the copy,
the digest, the pinned read, the tamper marker, the drift marker, and the
activation re-render. The pinned read is taken and **found broken**, which is a
result rather than a pass.
