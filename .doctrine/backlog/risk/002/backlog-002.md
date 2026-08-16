# RSK-002: Three target-contract absent paths are only reasoned

`docs/contract-target.md` promises three fields degrade rather than break. All
three are **reasoned and never run**:

- `baseline = null`
- `caches = {}`
- `guestConfig = {}`

doctrine sets all three, so this host has never taken any of the absent branches.
That is `NOTES item 41`'s rung exactly: a branch nothing has taken.

The risk is specific rather than vague — the contract's second limb is *anything
beyond the contract is declared and optional, with a working absent path*. If an
absent path is broken, the contract is a claim rather than a capability, and the
first second target discovers it (`IMP-004`).

**Mitigation**: `IMP-004` covers it, but only if the second target genuinely
omits fields. A second copy of doctrine proves nothing here.

Evidence rung (`STD-001`): reasoned. Below **build** — no artifact even names
these paths as tested.
