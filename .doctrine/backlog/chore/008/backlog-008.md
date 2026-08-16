# CHR-008: Clear the two stale quarantine artefacts

Two pieces of stale state on this host, both out-of-band cleanups and neither a
flake change:

- `/var/lib/capsule/collect/` holds a `faux.git` from before a capsule named its
  own quarantine.
- `/var/lib/capsule/doctrine.git` is the served mirror that `NOTES item 18`
  deleted the *service* for — the git channel stopped serving and the directory
  stayed.

Two more of the same class, found 2026-08-17 and added here rather than opened as
their own item: `.vm/--help` and `.vm/--list` in this checkout, both dated
2026-08-11, are `ISS-002`'s artefacts. That issue is **resolved** — the flag is no
longer read as a VM name — but resolving it did not remove what it had already
created, and nothing else claims them.

The general question behind them is **quarantine retention**, which is open and
belongs to the confined project's corpus: doctrine's `DEC-193` is proposed there.
That is *doctrine's* id, not this repo's — the two id spaces are strictly
separate (`ADR-001` term 2).

Note `capsule-adopt` has no transport, so inside the repo it silently reads the
**devshell** quarantine. `CAPSULE_STATE=/var/lib/capsule` points it at the module
path's before you go looking.

Evidence rung (`STD-001`): housekeeping; no claim.
