# CON-005: Only the guard can read the inside of a capsule's namespace

**Nothing outside a capsule's namespace can independently confirm its
`ip_forward=0`.** This is what remains of `just status`'s blindness after
`capsule all status`: the guard is the sole reader of the inside of a namespace,
so **if the guard is wrong it is wrong alone.**

Why that is acceptable rather than merely unavoidable: the guard **holds egress
bound to itself**. A guard that fails takes the perimeter down with it rather
than leaving a hole open — unverifiable-and-forwarding is a refusal to start, and
forwarding coming up mid-session kills egress. The blindness is paid for by the
coupling.

Do not soften that to a warning. A warning is what it had while the drop was in
fact missing from the host config.

The corroborating hazard, and why single-reader is worth naming: a **hardened
unit that may not read `/proc` gets a short answer, not an error.**
`ip netns pids` gates on `CAP_SYS_PTRACE` for processes owned by another user;
with the caps trimmed it returns the readable ones and silently omits the rest,
so the guard concluded a correctly-bound VMM was `not in cap-a` and refused the
fleet's egress **naming a cause that was not the cause**. The stubbed cases
cannot catch that class — a sandbox has one uid — so `hostModuleUnits` asserts
the pairing instead.

Active, and load-bearing. Adding a second reader means adding a second thing that
can be wrong about the perimeter.
