# IMP-004: Declare a second target

**The host-side tier: a second target as a document beside this one, with no
second image and no rebuild of any program.** The image tier — a second target
running *alongside* doctrine — is `IMP-006`, and it is where the remaining half
of this item's original claims went.

`docs/plan-c-multi-capsule.md` order of work, item 8. **Now a file rather than a
rebuild** — `NOTES item 52` moved the documents out of the store, so the module
writes one per declared target into `profileDir` at activation and
`capsule-profile-check` validates a hand-written one. Nothing has ever used that.

**Sequential is done and is not this.** panopticon is a second target on branch
`second-target` (`NOTES item 23`) — a switch, one target at a time. What has
never been done is a second target *declared here*, resolvable on this host,
without switching away from doctrine.

## What this tier can exercise

- **`--unit` against a target with no `{unit}` hole** (`NOTES item 32`).
  `statePaths` is in the document, so the refusal is document-side.
- **`baseline = null`** — one of `RSK-002`'s three absent paths, and the only one
  that is run-time. `capsule-baseline` refuses at run time for a document that
  declares nothing, naming the profile (item 51 step 6), and nothing has made it.
- **The front end with M targets on the module path.** `capsule all status` is
  one table over N slots and M targets (item 51, decision 3); the unnamed-slot
  refusal when two are declared; `--profile` winning over the record; the record
  winning over the single-render fallback. All of it is written and only the
  one-target path has ever run.

## What it cannot, and where that went

`caches = {}` and `guestConfig = {}` are the **build-time half** — inputs to the
guest image, deliberately absent from the document (`docs/contract-target.md`).
Same for `capsule-adopt`'s gitlink class and the corrected `capsule-baseline`
sizing, both of which need a real second guest doing real work. Those four are
`IMP-006`.

So **`RSK-002` is not discharged by this item** — one of its three absent paths
is, and the risk's `needs` now points at `IMP-006`.

## The shape

A genuinely different repo, and genuinely omitting fields: a second copy of
doctrine proves nothing, which is `RSK-002`'s own mitigation clause. This is the
review challenge made concrete (`CLAUDE.md`, *doctrine is the guinea pig*):
**would a different target need this code changed, or only a different value?**

Open question for the design: whether the second document is rendered by nix from
a second `target.nix`-shaped file — which needs an axis for "the targets this
host declares" and therefore a `POL-003` answer — or dropped in by hand as the
file item 52 says a non-nix producer may write. The second is cheaper and tests
the validator; the first is what a host with two real targets would want.

Evidence rung (`STD-001`): the capability is **built and unused**. This buys
**trigger** on one refusal, **take** on one absent path, and a first run of the
M-target front end.
