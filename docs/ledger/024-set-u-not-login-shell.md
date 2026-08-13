# NOTES item 24 — a `set -u` script must not *be* the login shell

*State: fixed in-tree, unshipped on this host.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**A `set -u` script must not *be* the login shell, and the pressure figure that
came out of the wreckage.** Numbered 24 rather than 23 because 23 was spent on
branch `second-target` before either reached `main`: the numbers are frozen
across branches, not per branch, so a branch that appends picks the next free
number globally and neither a merge nor a cherry-pick has to renumber.
[Item 23](./023-second-target.md) arrived here by the second route, with the two
fixes it documents.

**The bug.** `capsule-baseline` ran the guest-side runner as `bash -l run.sh
start STAMP`, and the login shell is load-bearing — `ssh host cmd` gets none of
`environment.variables`, so without it the build has no proxy and no caches
([item 6](./006-proxy-env-login-shell-scope.md)). The runner carries `set -uo
pipefail`. A login shell sources `/etc/bash_logout` on the way out; the
NixOS-generated one opens with a read of an unset guard variable, `set -u` was
still in force, and an unbound variable is fatal — **so the shell's exit status
became 1 whatever the script had returned**. Proven both ways on the host: a
script exiting 64 came back as 64 under `bash -l -c "bash script"` and as 1
under `bash -l script`. The fix is the extra process: the runner is a *child* of
the login shell, inherits the environment that was the whole point, and takes
`set -u` with it when it exits.

**Nothing in this repo changed to cause it.** The guest rebuild at the end of
the second-target round brought a nixpkgs whose `bash_logout` has that guard;
the same code had been green three runs earlier. The general form is worth more
than the instance: **a script that sets `-u` and is invoked *as* a login or
interactive shell inherits that shell's own startup and shutdown files**, and
those are written for a shell without `-u`. `NOSYSBASHLOGOUT=1` does not help —
under `set -u` the guard read errors before the `||` beside it is reached.

**What it cost, and what it did not.** Only the attach. `start` detaches the run
*before* the login shell exits, so both builds ran to green and recorded
themselves while the host program was dying with exit 1 — the volume's
`history.tsv` was the truth and the terminal was the lie, which is exactly the
first property [item 19](./019-baseline-build-and-figures.md) built this program
around. It stayed invisible because an exit 1 from a program whose job is to
report a build's exit status reads as a red build.

**And the open pressure question closed as a side effect.** Because nothing had
been stopped, the cgroups still held the whole run: cpu and io `total=` are
cumulative microseconds, so the figures were readable *after* the fact
([probes](../probes.md#pressure-under-two-concurrent-cold-builds)). Two
concurrent cold builds stalled 0.033% of their wall clock on cpu and 0.002% on
io — **and io being the smaller by an order of magnitude reverses what the disk
table had this repo expecting**. The bound is honest rather than tight: the
window is each cgroup's life, so the figure is an upper bound, and at 0.03% a
bound is enough to settle it.

**Two corrections to the instrument, from one 7-second smoke run.** `just load`
sampled `avg10` only, which is a decaying average that misses anything between
samples, so it now reads cpu/io `total=` at both ends — same argument as the
memory peaks, one field over. And its pressure files are checked for
readability up front, because a kernel with PSI off has the cgroup and not
them, and an absent pressure file defaulted to zero is an instrument reporting
*no contention* when what it means is *no measurement*. The run also caught
what review could not: awk reads a bare `s > 0` inside a `printf` argument list
as an output redirection, and shellcheck does not look inside an awk program.
A rendered-and-linted script is not a run.
