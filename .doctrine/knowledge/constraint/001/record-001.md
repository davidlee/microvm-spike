# CON-001: Extras are fleet-wide, so nothing pins them

The guest's tool set is `compose(floor, extras)`. The **floor** is the target's
(`target.nix`'s `toolsPackage`); the **extras** are the host operator's,
`fragments.nix`'s vocabulary selected by `extras` in `flake.nix`.

**One list for the fleet today, so one image.** That is the constraint, and three
things follow from it that read as bugs and are not:

- The assignment record's `extras` and `image` fields are **inert**.
- `"extras": []` in a live record reads as a lie. It means *this assignment
  selected none*, because nothing selects yet — the fleet composes `agents` and
  `dev-facilities` at build time.
- **Nothing selects extras, so nothing pins them.** No gcroot holds a resolved
  image, and no refusal stops a slot's composition changing under a populated
  volume. That is safe **only while the list is fleet-wide** — which is exactly
  the condition per-assignment selection removes.

And "one image" is an argument about the **declaration**, not a reading of this
host: the fleet has run as three runner store paths at once.

Relaxed by `IMP-003` (Plan D D7), which must bring the store-path identity, the
gcroot and the dirty-volume refusal *with* the selection, not after it.

Ownership rule this sits on: putting a convenience in `target.nix` says doctrine
needs it, which is the ownership smell pointed the other way (`NOTES item 31`,
`docs/contract-flavour.md`).
