# CHR-003: Exercise the profile pin on a live slot

`NOTES item 52` step 3 — a provision copies the target's document into the slot's
own directory and records that copy's `sha256:`, and every later verb on that
slot is pointed at *that* directory.

1. ~~Provision a free slot.~~ **Done, on `c`, 2026-08-17.** The first pin ever
   written on this host: `profile_snapshot = sha256:9e1e49e0…` and
   `/var/lib/capsule/slot/c/profile/doctrine.json`, 488 bytes, mode `-r--r--r--`.
   `capsule all status` then printed `doctrine` with no marker, which is the
   control reading — pin equals host document.
2. Edit `target.nix`, switch, and read `capsule all status` for the `*` — the
   marker for a slot whose host document has moved on. **Still owed**, and it is
   the only step that cannot be spent without a `~/flakes` switch. `c` is now the
   slot to read it on, because it is the only one with a pin to have drifted
   from.
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

Evidence rung (`STD-001`): steps 1 and 3 are now **taken** on a live host — the
copy, the digest, the pinned read and the tamper marker. Step 2's drift branch is
still **built and evaluated** only.
