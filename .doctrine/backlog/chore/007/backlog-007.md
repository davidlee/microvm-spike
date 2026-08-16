# CHR-007: Point the probe fabric at this host's DoT stub

The probes lost the host's DoT hop. `~/flakes` stubs `DNSStubListenerExtra` on
`10.101.0.1`; the probe fabric is `10.111.0.1`. So **every probe falls back to
`1.1.1.1` and says so** (`NOTES item 38`).

A two-line `~/flakes` edit. **No assertion depends on it** — which is why it has
survived: the probes are green either way, and the thing being lost is a hop
nobody asserts on.

Out-of-band, in `~/flakes`, not a change here. Do not compensate for it in this
repo — that would be leniency in the flake for a transient local-state problem.

Evidence rung (`STD-001`): none, currently. The fix makes an existing **run**
cover the hop it claims to.
