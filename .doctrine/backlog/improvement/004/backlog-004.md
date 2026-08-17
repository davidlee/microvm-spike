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

## Open, and answered by doing it

Whether a second document should be **rendered by nix from a second
`target.nix`-shaped file** — which needs an axis for *the targets this host
declares* and therefore a `POL-003` answer — or **hand-written**, which is the
producer item 52 explicitly allowed for. Hand-written first: it tests the
validator, and it does not drag in an axis question that belongs to `IMP-006`.

Evidence rung (`STD-001`): the logic is **verified by test**; the arrangement is
**unrun**. This item buys **taken** on two documents at once, and on
`capsule-profile-check` over a document nix did not write.
