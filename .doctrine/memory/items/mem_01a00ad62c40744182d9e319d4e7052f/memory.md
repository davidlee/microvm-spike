microvm.nix's templates are gated on
`ConditionPathExists=/var/lib/microvms/%i/current/bin/tap-up`. With no create the
tap unit is **skipped** — logged as `finished successfully` — and the proxy's
`BindsTo` on a unit that never went active fails.

The only message is `A dependency job for microvm@capsule.service failed`,
**naming neither**.

Read `ls /var/lib/microvms/<name>/current/bin` before anything else.

Same trap when the state dir is **stale** rather than absent: the VM tracks that
directory, not the flake, so a guest change needs `sudo microvm -u <name>`.