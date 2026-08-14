# The last step of a provision: regenerate what the push could not carry.
#
# [Item 32](../docs/ledger/032-the-sideband-channel.md) dropped doctrine's boot
# snapshot from `statePaths` on a rule worth more than the file — **state a
# consumer regenerates per checkout does not travel**, because a derived file
# delivered into a foreign tree is stale authority the next tool there reads as
# that tree's own. This is that rule's positive half
# ([item 33](../docs/ledger/033-provision-is-a-sequence.md)): such state comes
# back by being regenerated where it is needed, and that belongs to
# **provisioning**, not to a collect.
#
# Target-agnostic in the same sense as `host/baseline.nix`: `command` is a
# command line and this file has no opinion about what is in it. The capability
# is *a target may declare a command that runs in a fresh checkout once it
# exists*; the value is that target's business, and nothing generic learns what a
# governance snapshot is.
#
# **Not a `capsule-baseline` invocation**, though it runs the same shape of
# thing, and the three reasons are the whole of why this file exists:
#
#   - **Lifecycle.** `baseline` is once per capsule warmup. A refresh is once per
#     *provision*, because what it regenerates derives from the content the push
#     just replaced. A cold build to obtain a seconds-long regeneration is the
#     wrong end of a three-order-of-magnitude ratio.
#   - **The record.** `history.tsv` exists to hold one figure — the cold build, the
#     largest term in time-to-interactive (docs/probes.md). A second command inside
#     that run contaminates the only measurement the apparatus is for. So this
#     records nothing, detaches from nothing, and is over when it is over.
#   - **Failure semantics are opposite.** `capsule-baseline` is deliberately not
#     `set -e`: a failing build is a result to record. A refresh that fails must be
#     **loud**, because a checkout whose derived state did not regenerate is
#     exactly the stale-authority trap — and it fails by *absence*, which reads as
#     fine right up until something answers from it.
#
# **It may commit, and that is the one thing here that writes to the agent's
# branch.** Not every target's derived state is gitignored; a target may keep a
# generated file in its history, and then a refresh that only *ran* would leave a
# dirty worktree that the next provision refuses on and that every subsequent
# collect records as noise in its `dirty.diff`. So the tracked half of the output
# is committed — under the precondition that makes it safe rather than a trap,
# which is written where it is enforced, below.
#
# Jail-agnostic like its neighbours: it knows an ssh destination, a fragment that
# reaches it, and one guest path.
{
  pkgs,
  lib,
  # The push-on-stdin seam and its two learned corrections (host/guest-exec.nix).
  guestExec,
  # Where to ssh, e.g. `agent@10.99.0.2`. Jail-shaped, so injected.
  guestHost,
  # Which capsule, and how to reach it: a shell fragment setting `$capsule` and
  # the `ssh_cmd` argv (host/guest-ssh.nix). Jail-shaped, so injected — and
  # required.
  transport,
  # The target's own regeneration, run by the guest's login shell in `workdir`.
  command,
  # Where to run it — the guest's checkout.
  workdir,
}: let
  cmd = lib.escapeShellArg command;

  # Pushed at each call rather than baked into the guest's closure, for
  # `host/guest-exec.nix`'s three reasons. Nothing is written to the volume: like
  # `observe`, it arrives on stdin, acts, and is gone.
  runner = pkgs.writeText "capsule-refresh-run" ''
    # Deliberately not `set -e`: the target's command is allowed to fail, and
    # this program's job is to say so precisely rather than to vanish at the
    # first non-zero. Every exit below is chosen.
    set -uo pipefail

    work=${lib.escapeShellArg workdir}

    cd "$work" 2>/dev/null || {
      echo "capsule-refresh: no checkout at $work" >&2
      exit 2
    }

    # Running the target's regeneration against a directory that is not its
    # repository is worse than not running it: whatever it writes there is
    # derived from nothing, and looks exactly like state that was derived from
    # something.
    git rev-parse --verify --quiet HEAD >/dev/null 2>&1 || {
      echo "capsule-refresh: $work has no commit — capsule-provision first" >&2
      exit 2
    }

    # Tracked changes only, and that is the whole precision of what follows. A
    # dirty **worktree** is what `receive.denyCurrentBranch = updateInstead`
    # refuses the next provision on; an ignored file is not one. So a refresh
    # that writes only ignored files moves neither reading, and every branch
    # below is inert for it.
    before=$(git status --porcelain --untracked-files=no)

    ( ${command} )
    status=$?

    after=$(git status --porcelain --untracked-files=no)

    if [ "$status" -ne 0 ]; then
      echo "capsule-refresh: ${cmd} exited $status" >&2
      if [ "$before" != "$after" ]; then
        echo "  It also left tracked changes behind. Not committing a half-result:" >&2
        echo "  the checkout is dirty, and the next capsule-provision will refuse" >&2
        echo "  on that until someone looks at it." >&2
      fi
      exit "$status"
    fi

    [ "$before" = "$after" ] && exit 0

    # ------------------------------------------------ the refresh writes tracked
    #
    # Some do. Derived state is not always gitignored — a target may keep a
    # generated file in its history — and then a refresh that merely *ran* leaves
    # a dirty worktree, which costs twice: the next provision is refused, and
    # every collect from here on records `dirty: N` with a `.capsule/dirty.diff`
    # full of regenerated boilerplate. That blob is the exhibit an auditor most
    # wants (NOTES item 32); filling it with output nobody wrote degrades it.
    #
    # So commit it — and the precondition is what makes the commit safe rather
    # than the trap `git add .` would be. `updateInstead` only lets a push land on
    # a **clean** tree, so immediately after a provision `$before` is empty, and
    # `git commit -a` can therefore contain the refresh's output and nothing else.
    # No pathspec to get right, and no way for the agent's in-flight work to ride
    # along, because there was none to ride.
    #
    # Untracked files are deliberately not added: whether a newly-created file
    # belongs in the repository is a judgement, and this program does not have the
    # standing to make it for a target.
    if [ -n "$before" ]; then
      echo "capsule-refresh: ${cmd} changed tracked files, and this checkout was" >&2
      echo "  already dirty before it ran — so there is no way to tell the two" >&2
      echo "  apart. Nothing committed, deliberately: the alternative is committing" >&2
      echo "  someone else's uncommitted work under this program's name." >&2
      echo "  Commit or discard what was there, then capsule-refresh again." >&2
      exit 3
    fi

    head=$(git rev-parse HEAD)
    if git commit -a -q \
      -m "capsule: refresh" \
      -m "refresh: ${cmd}" \
      -m "code-oid: $head"; then
      echo "capsule-refresh: committed $(git rev-parse --short HEAD) — ${cmd} writes tracked files"
    else
      echo "capsule-refresh: ${cmd} changed tracked files and the commit failed." >&2
      echo "  The checkout is dirty and the next capsule-provision will refuse." >&2
      exit 3
    fi
  '';

  script = guestExec.checked runner;

  # One command line, so a caller may write `if ! ${invoke}; then`. Self-contained
  # apart from `ssh_cmd`, which every transport fragment sets.
  invoke = ''"''${ssh_cmd[@]}" ${lib.escapeShellArg guestHost} ${lib.escapeShellArg guestExec.loginRun} < ${script}'';
in {
  inherit invoke;

  # Separately invocable, and not only for symmetry: a human who has just done a
  # hand `git checkout` in the guest wants exactly this and no push, and a
  # provision that failed *at* the refresh needs a way to retry the half that
  # failed. It is also how the thing is exercised without a full provision.
  program = pkgs.writeShellApplication {
    name = "capsule-refresh";
    runtimeInputs = [pkgs.openssh];
    text = ''
      ${transport}
      if [ "$#" -gt 0 ]; then
        echo "usage: capsule-refresh [--capsule <name>]" >&2
        echo "  runs ${cmd} in the capsule's checkout, to regenerate the derived" >&2
        echo "  state a provision cannot carry (NOTES item 33)." >&2
        exit 1
      fi
      echo "capsule-refresh: ${cmd} in $capsule"
      ${invoke}
    '';
  };
}
