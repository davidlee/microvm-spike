# Running a host-authored script *inside* a live capsule — the other half of
# `host/guest-ssh.nix`, which only says how to reach one.
#
# Everything the host runs in a guest arrives the same way, and the reasons are
# `host/observe.nix`'s and `host/state-snapshot.nix`'s: **pushed at each call,
# never baked into the guest's closure.** It is host-side policy about what a
# capsule does rather than part of what a capsule *is*; a copy left on a volume
# by an older build is drift nothing reports; and a capsule with a real workload
# in it cannot be rebuilt without a restart, which is the case that needs it most
# (NOTES item 32).
#
# What is here is the part that is easy to get wrong a second time. Guest scripts
# fall into two classes, and one question sorts them: **does it read the guest's
# `environment.variables`?**
#
#   - **No** — `observe` and `state-snapshot`. Asking git for a sha needs no
#     proxy and no `CARGO_HOME`, so `bash -s` is the whole invocation and item
#     24's trap cannot arise. Those two say so in their own headers.
#   - **Yes** — `baseline` and `refresh`. `ssh host cmd` is neither a login nor
#     an interactive shell, so without `-l` there is no proxy, no `CARGO_HOME`
#     and no `TMPDIR` ([item 6](../docs/ledger/006-proxy-env-login-shell-scope.md)),
#     and a command that cannot reach the proxy fails looking like a network
#     fault.
#
# One thing `-l` does **not** buy, because login and interactive are different
# flags and `bash -l -c` is only the first: `programs.bash.interactiveShellInit`
# does not run. In this guest that init does two things (`vm/capsule.nix`) — `cd`
# into the checkout, and source `/work/.env`, which is where `capsule-inject`
# puts secrets. So a guest script gets `environment.variables` and not the
# injected environment, and it must `cd` for itself. Both callers here do.
#
# `loginRun` is the second class's invocation, and it is a named constant rather
# than a line at each call site because it is a *rule* and not a convenience:
# the script must be a **child** of the login shell and must not *be* one. A
# login shell sources `/etc/bash_logout` on the way out, NixOS generates one
# whose first line reads an unset guard variable, and a `set -u` script that is
# that shell has its exit status replaced by 1 whatever it returned
# ([item 24](../docs/ledger/024-set-u-not-login-shell.md)). That cost three green
# runs reported as red, and nothing in this repo changed to cause it — a nixpkgs
# bump did. One more process, and `set -u` dies with the child.
{pkgs}: {
  # Lint a guest script at build time. `writeShellApplication` would run
  # shellcheck for us but would also bake this host's store paths into a script
  # that runs in the guest, so the check is asked for by hand instead.
  #
  # Takes the script derivation and gives back the same bytes, having refused to
  # build if shellcheck objects. Note what it cannot see: shellcheck does not
  # look inside an embedded awk program, which is where item 24's own review pass
  # missed a bug that one 7-second run caught. A rendered-and-linted script is
  # not a run.
  checked = script:
    pkgs.runCommand "${script.name}-checked" {
      nativeBuildInputs = [pkgs.shellcheck];
    } ''
      shellcheck -s bash ${script}
      cp ${script} $out
    '';

  # What ssh should be handed to run a script arriving on its stdin under the
  # guest's login environment. Spliced escaped, because it is one remote command
  # line and ssh joins its arguments with spaces:
  #
  #     "the ssh_cmd array" <guestHost> <loginRun> < <the script>
  #
  # with the last three spliced through `lib.escapeShellArg`. `host/refresh.nix`'s
  # `invoke` is the whole of it, in one line.
  #
  # One caller today (`host/refresh.nix`). `capsule-baseline` needs the same form
  # but composes its command line at run time — a staged path and a stamp neither
  # of which exists at eval — so it spells its own and cites the same item. This
  # is where the rule lives; that is a second instance of it, not a second
  # decision.
  loginRun = "bash -l -c 'bash -s'";
}
