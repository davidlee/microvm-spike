`ip netns pids <ns>` works by reading `/proc/<pid>/ns/net` for every process,
which `ptrace_may_access` gates on **`CAP_SYS_PTRACE`** for anything owned by
another user — **`CAP_DAC_READ_SEARCH` does not cover that check.**

With the caps trimmed it returns the readable processes and **silently omits the
rest**, so the guard concluded a correctly-bound VMM was `not in cap-a` and
refused the fleet's egress, **naming a cause that was not the cause**.

The A/B that proves it, and the shape for the next one:
`sudo systemd-run --pipe -q -p CapabilityBoundingSet="…" <cmd>` beside plain
`sudo <cmd>` — the same command under the unit's own capability set.

**The stubbed cases cannot catch this class**: `guardCases` proves logic, and
privilege is only provable on a host. So `hostModuleUnits` asserts the pairing
instead — a program that reads `/proc` and a unit that may.