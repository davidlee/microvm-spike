# IMP-004: Declare a second target

**Two documents in one `profileDir`, on this host, for a repo that is not
doctrine.** The image tier — a second target *running* alongside doctrine — is
`IMP-006`.

`docs/plan-c-multi-capsule.md` order of work, item 8. **Now a file rather than a
rebuild** — `NOTES item 52` moved the documents out of the store, so the module
writes one per declared target into `profileDir` at activation and
`capsule-profile-check` validates a document nix did not write. Nothing has ever
put a second one there.

## What this item is not, any more

It was written as *the only thing that can exercise three refusals that are
build-time-only today*. That claim is **stale**: item 51's move of the target's
run-time half into a document made all three reachable from a fixture, and three
suites took them while this item sat open.

| the claim | where it is pinned now |
| --- | --- |
| `--unit` against a template with no `{unit}` hole (`NOTES item 32`) | `host/git-channel-cases.nix:184` — *"and a --unit against a document with no hole refuses"* |
| `baseline = null` (`RSK-002`) | `host/policy-cases.nix:570` — the front end skips and says *"declares no baseline"*; the fixture renders `baseline: null` at `:125`, and `host/baseline.nix:237` is the program's own refusal |
| the front end with M targets | `host/policy-cases.nix:435` — *"an unassigned slot refuses once this host declares two"*, naming both |

`capsule-adopt`'s gitlink class and the corrected `capsule-baseline` sizing were
this item's other two, and both are `IMP-006`'s: they need a second guest doing
real work, not a second document.

## What is left, and it is an exercise

Every row above is **a program's own text against a fixture** — the third kind of
check (`CLAUDE.md`). None of it has ever been a real document, on this host,
beside doctrine's. That gap is the same shape as `CHR-002`, `CHR-003` and
`CHR-011`: the logic is pinned and the *arrangement* is not.

The deliverable:

1. **Author panopticon's document.** `~/dev/panopticon` is a real second target
   and its `target.nix` is on branch `second-target` (`NOTES item 23`) — uv
   rather than cargo, `UV_CACHE_DIR`, no `statePaths`, no `refresh`, 4096 MiB and
   an 8 GiB volume. It predates three field removals (`allowlist`,
   `defaultBranch`, `collectMaxPackBytes`), so bringing it to today's shape is
   itself a check on what the contract dropped.
2. **Validate it** with `capsule-profile-check`, which has never been run over a
   document that was not this host's own render.
3. **Drive the module-path front end with both documents** —
   `CAPSULE_PROFILE_DIR` is a *default* since `ISS-004`, so a caller may point it
   at a directory holding two without root and without writing to
   `/var/lib/capsule-profiles`. Read-only verbs only; nothing near the slot
   driving `SL-251`.
4. **Record what breaks**, and correct whatever the run contradicts —
   `docs/contract-target.md` and `RSK-002`'s rung included.

## The run, 2026-08-17

Hand-written `panopticon.json` (uv and cargo caches, 4096 MiB, an 8 GiB volume,
`baseline = "just check"`, `refresh = null` as the port declared), beside a copy
of this host's `doctrine.json`, with `CAPSULE_PROFILE_DIR` pointed at the pair.
Module-path binaries by absolute path, read-only verbs only, nothing near the
slot driving `SL-251`.

**What worked, first time and unmodified:**

- `capsule-profile-check` accepted the hand-written document and printed all
  twelve values plus `needsUnit yes` — the first document nix did not write.
- `capsule all status` with two declared targets: the assigned slots kept their
  record's `doctrine`, and the five unassigned ones went from `doctrine` to `-`.
  No guess, exactly as item 51 decision 3 says, and the table needed no
  per-target shape.
- `capsule f collect` refused: *"'f' has no assignment and this host declares
  more than one target: doctrine panopticon"*, naming both and naming the verb
  that assigns.
- `capsule f refresh --profile nosuch` refused naming the directory it looked in.

**What broke — two, both fixed:**

1. **`capsule-profile-check` was reachable by nobody.** Built only as an argument
   to `profileCases`; no `packages` entry, no devshell, no `systemPackages`. The
   contract names it as *what to run before dropping a document in* and item 52's
   point is a producer that is not nix, so the one caller it exists for had
   nothing to run. Now all three.
2. **`capsule-refresh` announced a command that was not there.**
   `capsule f refresh --profile panopticon` printed `capsule-refresh:  in f` and
   *then* refused for `refresh = null` — the banner sat above `refreshInvoke`
   and the absent-path check sits inside it. `ISS-006`'s class. The line moved
   into `refreshInvoke` after the check, `capsule-provision`'s weaker
   *"regenerating derived state"* went with it, and `refreshCases` took the
   fragment as a second subject to pin the order.

**A third, doc-level:** `host/services.nix`'s `systemPackages` header still said
`capsule-baseline` and `capsule-refresh` *"go on PATH as they are"*, fifteen
lines above the entry that wraps both and says *"Wrapped since ISS-004"*.

**Not exercised.** No provision, no boot, no guest — panopticon has no image
(`IMP-006`). No document was written to `/var/lib/capsule-profiles`, so this host
still declares one target; the run was a rehearsal through the override that
`ISS-004` made possible. And the two failure orders for one slot — the front end
reached the profile check while `capsule-refresh` straight off `PATH` was refused
by its transport first — is the two-copies-two-transports family, noted and not
chased.

## Open, and answered by doing it

Whether a second document should be **rendered by nix from a second
`target.nix`-shaped file** — which needs an axis for *the targets this host
declares* and therefore a `POL-003` answer — or **hand-written**, which is the
producer item 52 explicitly allowed for. Hand-written first: it tests the
validator, and it does not drag in an axis question that belongs to `IMP-006`.

Evidence rung (`STD-001`): the logic is **verified by test**; the arrangement is
**unrun**. This item buys **taken** on two documents at once, and on
`capsule-profile-check` over a document nix did not write.
