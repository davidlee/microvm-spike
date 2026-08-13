# NOTES item 19 — the baseline build, and where a figure is allowed to live

*State: built, run, measured.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**The baseline build, and where a figure is allowed to live.** The last of
the three setup problems (docs/design.md) is a *command*, not a payload: run
the target's own build-and-test to green, which both proves the capsule works
and fills its caches. On a fresh volume that is the **cold build** — the
largest term in time-to-interactive, and the one figure `probe/freshness.sh`
cannot take, because its namespace has no upstream to fetch a crate from.

Built as `capsule-baseline` (`host/baseline.nix`, `target.nix`'s `baseline`).
Four decisions in it are worth freezing, because three of them are paid-for
lessons rather than preferences:

- **The record is not the terminal.** The sizing runs that produced the
  figures in [probes.md](../probes.md) lost two attempts to scrollback: the
  first printed its numbers after the agent exited, the agent was exited with
  Ctrl-C, and SIGINT killed the shell that was going to print them. So the
  run writes its log and one line of `/work/baseline/history.tsv` onto the
  volume *as it goes*. The volume is where a figure survives the session;
  probes.md is where it survives the capsule, since freshness is implemented
  by deleting volumes.
- **The run does not depend on the session.** The guest half `setsid`s into
  its own session, so closing the channel cannot SIGHUP a twenty-minute
  build. The host attaches with `tail --pid` to watch, and leaving is free —
  re-running attaches to the run in flight rather than starting a second,
  because two runs interleaved into one record are two figures lost, not one
  gained.
- **It is `bash -l` in the guest, and that is
  [item 6](./006-proxy-env-login-shell-scope.md) arriving.** `ssh host cmd` is
  neither login nor interactive, so it has no `environment.variables` — no
  proxy, no `CARGO_HOME`, no `TMPDIR`. A baseline run without the proxy fails
  looking like a network fault, which is the most expensive shape a failure can
  take here. The log's header prints `http_proxy` for that reason.
- **It is not a probe.** `probe/` is evidence that needs root and answers a
  design question about the shape; this is a lifecycle command a human runs
  on a capsule they are about to work in, which happens to produce a figure.
  Putting it in `probe/` would have meant a probe that needs the real
  perimeter up, the real credentials in, and twenty minutes — none of which
  the others need.

Generic-plus-a-value, per CLAUDE.md's guinea-pig rule: the capability is *run
the instance's declared build-and-test and record what it cost*, and `just
web-build test` is one target's instance of it. `baseline = null` drops the
program rather than shipping one that cannot work — the same absent-path
discipline as `toolsPackage`.

**Run 1 took the number: 109 s to green on a deleted volume**, ~1.1 GiB of
volume, figures in [probes.md](../probes.md). Two things it established beyond
the duration. The record proves its own coldness — caches 123 MiB before,
`.cargo` alone 144 MiB after — which is why the sizes are in the row and not
only in the log: a duration is a cold-build figure only if something in the
same row says the caches were empty. And **time-to-interactive is ~2 minutes,
~93% of it this one build**, which reorders what is worth optimising: every
other figure this repo has taken is noise beside it.

The `before:` breakdown was lost to scrollback on the very first run, and cost
nothing, because it was also in the log on the volume. The lesson that shaped
the program was confirmed by the program's first use.

Still open: the pair probe's question. Two capsules building at once is a
scheduling question, and two `capsule-baseline`s are how it gets asked — each
with its own record on its own volume, which is the attribution half.
