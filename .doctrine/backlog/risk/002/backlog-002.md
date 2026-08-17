# RSK-002: Three target-contract absent paths are only reasoned

`docs/contract-target.md` promises three fields degrade rather than break. All
three are **reasoned and never run**:

- `baseline = null` — **run-time**, carried by the profile document
- `caches = {}` — **build-time**, an input to the guest image
- `guestConfig = {}` — **build-time**, likewise

doctrine sets all three, so this host has never taken any of the absent branches.
That is `NOTES item 41`'s rung exactly: a branch nothing has taken.

The risk is specific rather than vague — the contract's second limb is *anything
beyond the contract is declared and optional, with a working absent path*. If an
absent path is broken, the contract is a claim rather than a capability, and the
first second target discovers it (`IMP-004`).

**Mitigation, and it takes two items rather than one.** The split above is why:
a profile document carries the run-time half of `target.nix` and nothing of the
build-time half (`docs/contract-target.md`), so declaring a second target
host-side reaches exactly one of these three.

- `baseline = null` — `IMP-004`, the document tier. No image, no rebuild.
- `caches = {}`, `guestConfig = {}` — `IMP-006`, the image tier, because both
  are inputs to the guest the seed builds.

Either way the condition holds: the second target must **genuinely omit** the
fields. A second copy of doctrine proves nothing here.

Evidence rung (`STD-001`): reasoned. Below **build** — no artifact even names
these paths as tested.
