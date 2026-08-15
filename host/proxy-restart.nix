# The one spelling of "bounce a slot's egress proxy", as `sudo` will see it.
#
# Three things have to agree about this command and they used to say it three
# times: `host/cli.nix`'s `proxyControl` runs it, `host/services.nix` grants it,
# and `flake.nix`'s `unrestartable` check asserts the grant covers every proxy
# unit. Two of the three agreed and the one that mattered did not (NOTES item
# 44) — the rule named this path and the program ran `sudo systemctl`, which is
# a *different command* to sudoers.
#
# **Sudo on this host has no `secure_path`**, so it resolves an unqualified
# command against the *caller's* `PATH` — and `writeShellApplication` prepends
# `runtimeInputs` to that, so the front end's `systemctl` is
# `${pkgs.systemd}/bin/systemctl` and a rule naming `/run/current-system/sw/bin`
# never fires. The reverse of what NOTES item 41 wrote down, and the reason this
# is a value rather than a comment: an invariant two files must share is one
# construction, not two careful ones (CLAUDE.md).
#
# Why the `/run` path and not the store one: a store path pins the rule to one
# systemd build, so the grant would lapse on the next bump of an input that has
# nothing to do with this repo — silently, and in the fail-open direction the
# whole verb exists to close.
unit: "/run/current-system/sw/bin/systemctl restart ${unit}"
