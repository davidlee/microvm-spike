NixOS's `/etc/bash_logout` opens by reading an **unset guard variable**, so
`bash -l script` where the script sets `-u` dies on the way out and **the shell
reports 1 whatever the script returned**.

A program whose job is to relay a build's exit status then reports a **red build
that was green**. Cost a session, and hid two green baselines (`NOTES item 24`).

Run it as a child instead: `bash -l -c "bash script args"` keeps the login
shell's environment — the load-bearing part (`NOTES item 6`) — and lets `set -u`
die with the child. `host/guest-exec.nix`'s `loginRun` is
`bash -l -c 'bash -s "$@"'` for exactly that reason, and `host/baseline.nix` uses
the same `"$0" "$@"` shape to keep a third parse out of a staged run.

`NOSYSBASHLOGOUT=1` does **not** help: under `-u` the guard read errors before
the `||` beside it.