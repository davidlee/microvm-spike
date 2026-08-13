# NOTES item 9 — egress allowlist unproven; and the `MaxClients` hang that was not it

*State: half — slots fixed, list still unproven.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Egress allowlist is unproven** against a real Claude Code session —
expect to add hosts on first run. `perimeter/egress-allow.txt`, restart
`capsule-host`, no rebuild.

**The first real workload found a limit that was not the allowlist.**
`bun install` in the guest hung mid-download, repeatably, and succeeded
instantly when killed and re-run. Nothing was denied and nothing was logged:
tinyproxy was at `MaxClients 32`, so it had stopped accepting, while the
kernel went on completing handshakes — 32 connections sat in the listener's
accept queue (`ss -lnt 'sport = :3128'`, `Recv-Q 32`) and bun waited on
sockets no worker would ever read. bun's default `--network-concurrency` is
48, so it deadlocked against 32 workers every time; it looked intermittent
only because how many packages are already cached decides how wide it fans
out. `MaxClients 128` and `Timeout 300` now (`perimeter/default.nix`, with
the reasoning). Worth generalising: a proxy in the path turns *any* client's
parallelism into a shared resource, and the failure mode is a hang with no
error on either side — not a refusal. The allowlist is the control; the slot
count is capacity, and they fail in completely different ways.
