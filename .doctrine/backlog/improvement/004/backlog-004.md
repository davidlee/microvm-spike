# IMP-004: Declare a second target

`docs/plan-c-multi-capsule.md` order of work, item 8. **Now a file rather than a
rebuild** — `NOTES item 52` moved the documents out of the store, so the module
writes one per declared target into `profileDir` at activation.

It is the only thing that can exercise **three refusals that are build-time-only
today**:

- `--unit` against a target with no `{unit}` hole (`NOTES item 32`).
- `capsule-adopt`'s gitlink mode class (`NOTES item 34`) — no target carries one.
- The corrected `capsule-baseline` sizing, which has never produced a record
  because doctrine shares no inodes between `target/` and `.cargo` and so
  reconciles either way (`NOTES item 23`).

It also exercises `RSK-002`'s three absent paths, which is the other reason to
prefer a genuinely *different* repo over a second copy of doctrine: a target that
sets everything doctrine sets proves nothing about the degradation paths.

This is the review challenge made concrete (`CLAUDE.md`, *doctrine is the guinea
pig*): **would a different target need this code changed, or only a different
value?**

Evidence rung (`STD-001`): the capability is **built and unused**. This buys
**trigger** on three refusals and **take** on three absent paths.
