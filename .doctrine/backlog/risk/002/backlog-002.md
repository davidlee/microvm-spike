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

Evidence rung (`STD-001`), and it is no longer one rung for all three.
`baseline = null` is **verified by test** — `host/policy-cases.nix:570` asserts
the front end skips it and says so, off a fixture document rendering
`baseline: null` (`:125`), and `host/baseline.nix:237` is the program's own
refusal. That happened after this record was written and this line said
otherwise: *"below build — no artifact even names these paths as tested"*, which
was true of all three and is now true of two.

`caches = {}` and `guestConfig = {}` stay **reasoned**. Both are build-time, so
no document and no `*Cases` fixture can reach them — only a guest image built
without them, which is `IMP-006`.
