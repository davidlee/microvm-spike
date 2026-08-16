# EVD-004: A conditional probe's total is part of its verdict

Three probes whose green is only meaningful beside a count:

| probe | total | what a lower total means |
| --- | --- | --- |
| `netns-egress.sh` | **33/33, run 3** | 27/27 is the perimeter alone; the six extra are stage 2b — the first time a *selected* policy reached a wire. **A run that skips to 27 still reads green.** |
| `two-capsules.sh` | **42/42, run 4** | 28/28 twice before stage 2b existed, then 40/42 on run 3 whose two reds were the probe's own stale assertion. **A vacuous run agrees with its own history.** |
| `netns-restart.sh` | **33/33** shipped, **30/3** against a deliberately pre-fix program | the mutation is what proves the instrument discriminates |

The third row is the control the other two lack: build the probe against a
deliberately broken copy of what it tests and check *which* rounds go red.

`netns-restart` also demonstrates the addressing rule — it drives the real
`capsule-netns` on addressing that is **nobody's capsule**: no VM, no tap, no
guest, seconds.

Source: `docs/probes.md`, the probe table and *What netns-restart.sh
established*.

Supports `STD-001` — this is the fourth lying instrument, and `CHR-006` exists
because one of these totals was never captured.
