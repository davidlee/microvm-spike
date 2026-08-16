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
  # Which *target*, and the same shape one axis over: a fragment that resolves
  # `--profile` and loads the document, setting `$profile_refresh` and
  # `$profile_guest_path` — the two values this file used to take as nix
  # arguments (host/profile.nix, NOTES item 51 step 4). Required, and refusing
  # without one, for `transport`'s reason.
  profileSelect,
}: let
  # Pushed at each call rather than baked into the guest's closure, for
  # `host/guest-exec.nix`'s three reasons. Nothing is written to the volume: like
  # `observe`, it arrives on stdin, acts, and is gone.
  #
  # **The two things that tie it to a host are its arguments**, and it is one
  # store path (NOTES item 51). It used to be a function of them, for the reason
  # `host/state-snapshot.nix`'s `snapshotFor` was one: the target's command line
  # and the checkout it runs in are exactly what a case suite must substitute,
  # and the branch that went unrun for the life of this file
  # ([item 47](../docs/ledger/047-a-script-on-stdin-and-the-command-that-eats-it.md))
  # is unreachable without substituting the first. A build-time function gave one
  # program per target; an argument gives one program.
  #
  # **Usage:** `<work> <command>`, and both are required — a refresh with no
  # command is a program with nothing to run, and one with no checkout would
  # regenerate a target's derived state wherever it happened to be standing.
  runText = pkgs.writeText "capsule-refresh-run" ''
    # Deliberately not `set -e`: the target's command is allowed to fail, and
    # this program's job is to say so precisely rather than to vanish at the
    # first non-zero. Every exit below is chosen.
    set -uo pipefail

    work=''${1:-}
    cmd=''${2:-}
    if [ "$#" -lt 2 ] || [ -z "$work" ] || [ -z "$cmd" ]; then
      echo "capsule-refresh: usage: <work> <command>" >&2
      exit 2
    fi

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
    #
    # **The patch and not `--porcelain`**, which is the second half of
    # [item 47](../docs/ledger/047-a-script-on-stdin-and-the-command-that-eats-it.md)
    # and was found by the case suite the first half needed. A status line names
    # a *file*; `git diff HEAD` is its content. With the status form, a refresh
    # that rewrites a file which was already modified produces the identical
    # line either side, the comparison below reads it as *nothing changed*, and
    # the run exits 0 leaving the tree dirty — so the one refusal that exists to
    # say `there is no way to tell your edit from mine` is unreachable in
    # precisely the case it is about. `HEAD` rather than a bare diff so a staged
    # change counts, and untracked files stay out of both, which is the whole
    # point of the distinction above.
    before=$(git diff HEAD)

    # `</dev/null` is the whole of
    # [item 47](../docs/ledger/047-a-script-on-stdin-and-the-command-that-eats-it.md),
    # and it is not defensive. This script *is* the guest shell's stdin —
    # `host/guest-exec.nix`'s `loginRun` is `bash -l -c 'bash -s'` with the script
    # redirected in — so a target command that reads stdin reads **the rest of this
    # file**, bash then has nothing left to execute, and the run ends at this line
    # with status 0 and no output of its own. Every check below it is skipped
    # silently, including the one whose header says a failed refresh must be loud.
    # doctrine's refresh is a TUI, so that is what happened, on every provision,
    # for the life of this file.
    #
    # The redirect goes on the command rather than on the ssh call or the script,
    # because the script is *supposed* to arrive on stdin and the one thing here
    # that must not inherit it is the one line this repo did not write.
    ( eval "$cmd" ) </dev/null
    status=$?

    after=$(git diff HEAD)

    if [ "$status" -ne 0 ]; then
      echo "capsule-refresh: $cmd exited $status" >&2
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
      echo "capsule-refresh: $cmd changed tracked files, and this checkout was" >&2
      echo "  already dirty before it ran — so there is no way to tell the two" >&2
      echo "  apart. Nothing committed, deliberately: the alternative is committing" >&2
      echo "  someone else's uncommitted work under this program's name." >&2
      echo "  Commit or discard what was there, then capsule-refresh again." >&2
      exit 3
    fi

    head=$(git rev-parse HEAD)
    if git commit -a -q \
      -m "capsule: refresh" \
      -m "refresh: $cmd" \
      -m "code-oid: $head"; then
      echo "capsule-refresh: committed $(git rev-parse --short HEAD) — $cmd writes tracked files"
    else
      echo "capsule-refresh: $cmd changed tracked files and the commit failed." >&2
      echo "  The checkout is dirty and the next capsule-provision will refuse." >&2
      exit 3
    fi
  '';

  script = guestExec.checked runText;

  # One shell function, so a caller may write `if ! refreshInvoke; then` — it was
  # one command *line* while both its values were nix strings, and it is a
  # function now because they are read off a document at run time (NOTES item 51
  # step 4). Self-contained apart from `ssh_cmd` and the `profile_*` variables,
  # which the two fragments beside it set.
  #
  # **Escaped once, not twice.** A value spliced into a program's text was parsed
  # by this host's shell and then by the guest's; an array element is parsed only
  # by the guest's, so `profileQuote` runs once over each (host/profile.nix).
  invoke = ''
    refreshInvoke() {
      local -a args
      # Reachable only from `capsule-refresh` run by hand against a target that
      # derives nothing: a provision asks the same question before it calls this,
      # because there a missing command is a step to skip and not a failure.
      if [ -z "$profile_refresh" ]; then
        echo "capsule-refresh: profile '$profile_name' declares no refresh, so" >&2
        echo "  there is nothing to regenerate in this capsule's checkout. That" >&2
        echo "  is a target with nothing derived from its code, not a fault." >&2
        return 1
      fi
      mapfile -t args < <(
        printf '%s\n' "$profile_guest_path" "$profile_refresh" | profileQuote
      )
      "''${ssh_cmd[@]}" ${lib.escapeShellArg guestHost} \
        ${lib.escapeShellArg guestExec.loginRun} "''${args[@]}" < ${script}
    }
  '';
in {
  inherit invoke;

  # The seam, exported for the same reason the state snapshot's text is: the only
  # interface to this logic is the script's own text, and the branches worth
  # pinning are the ones a live host reaches by having a target command that fails
  # or writes tracked files — neither of which any target here can be asked to do
  # on demand. `refreshCases` runs *this store path* with commands chosen to reach
  # them; there is no second copy and nothing to instantiate.
  refreshScript = script;

  # Separately invocable, and not only for symmetry: a human who has just done a
  # hand `git checkout` in the guest wants exactly this and no push, and a
  # provision that failed *at* the refresh needs a way to retry the half that
  # failed. It is also how the thing is exercised without a full provision.
  program = pkgs.writeShellApplication {
    name = "capsule-refresh";
    runtimeInputs = [pkgs.openssh];
    text = ''
      ${transport}
      ${profileSelect}
      ${invoke}
      if [ "$#" -gt 0 ]; then
        echo "usage: capsule-refresh [--capsule <name>] --profile <name>" >&2
        echo "  runs the profile's refresh in the capsule's checkout, to" >&2
        echo "  regenerate the derived state a provision cannot carry (NOTES" >&2
        echo "  item 33). This one is: ''${profile_refresh:-none}" >&2
        exit 1
      fi
      echo "capsule-refresh: $profile_refresh in $capsule"
      refreshInvoke
    '';
  };
}
