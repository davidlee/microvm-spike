# The inbound direction of the sideband: putting one capsule's collected state
# *into* another one.
#
# [Item 32](../docs/ledger/032-the-sideband-channel.md) built the outbound half
# and reserved this one — "the ref name and the `-p` parent are here to reserve
# it" — for the case it named: a fresh audit capsule that must see the
# implementation capsule's phase sheets. `capsule-collect` takes that state out,
# `capsule-adopt` lays it on this host's disk, and neither of them puts it
# anywhere a second agent can read it
# ([item 35](../docs/ledger/035-briefing-a-capsule-with-state.md)).
#
# **The host validates and the guest only lays out**, which is the decision this
# file is shaped around. `host/exhibit.nix` is the same check `capsule-adopt`
# runs, spliced here rather than copied, because validation belongs where the
# policy is: the guest is the confined side, and a control that runs there is a
# control the confined thing could be made not to run. What crosses the door is
# a commit the host has already refused to send if it was refusable.
#
# **`code-oid` becomes a control here, and this is the first thing that reads
# it.** The commit message says which code the state was the state *of*, and the
# guest refuses unless its own HEAD is that commit. That refusal is what makes
# the rest safe: `git add -f -- <dir>` stages *worktree* content, so a state tree
# carries the other agent's uncommitted edits to tracked files under
# `statePaths`, and laying those over the same code reproduces the worktree that
# existed while laying them over different code composes a worktree that never
# did. It also teaches the flow rather than merely refusing — collect the source,
# `capsule <src> fetch` to bring the commit into the target repo, provision this
# capsule at it.
#
# Jail-agnostic like its neighbours: a git URL, an ssh destination, a fragment
# that reaches either, and one guest path.
{
  pkgs,
  lib,
  # The push-on-stdin seam and its build-time lint (host/guest-exec.nix).
  guestExec,
  # Where to ssh, e.g. `agent@10.99.0.2`. Jail-shaped, so injected.
  guestHost,
  # The guest's checkout as a git URL — this pushes the state commit in over the
  # same channel `capsule-provision` pushes code over. Jail-shaped, so injected.
  guestRepo,
  # Which capsule, how to reach it, and git's own view of that: a fragment
  # setting `$capsule`, `ssh_cmd` and `GIT_SSH_COMMAND` (host/programs.nix).
  gitSsh,
  # Where a collected exhibit lives and what its refs are called
  # (host/quarantine.nix). Read at two names here, not one: the source capsule's
  # quarantine and the destination capsule's identity.
  quarantine,
  # Whether a guest-authored tree may be written at all (host/exhibit.nix).
  exhibit,
  # The guest's checkout, which is where the tree lands.
  workdir,
}: let
  # Pushed at each call rather than baked into the guest's closure, for
  # `host/guest-exec.nix`'s three reasons — and for this file's own: a capsule
  # briefed with another's state is one that has been running, and rebuilding it
  # to teach it how to receive would be the restart the whole sideband exists to
  # avoid.
  #
  # **No login shell**, like `observe` and `state-snapshot`: nothing here reads
  # the guest's `environment.variables`, so item 24's trap cannot arise.
  #
  # **One line, tab-separated, fixed order:** `<files>\t<dirty>`. Diagnostics go
  # to stderr. Unlike the outbound snapshot there is no `-` case — a brief that
  # cannot happen is a failure rather than a skip, because the caller asked for
  # this state specifically and a capsule that silently did not get it is one an
  # agent will answer from anyway.
  #
  # **A function of the checkout it runs in**, which is the seam that makes it
  # testable at all — the same one `host/guard.nix` takes its `tools` through and
  # `perimeter/` takes its fragments through. The interesting branches here (a
  # code-oid that does not match, a worktree somebody else has dirtied) are ones a
  # live host can only reach by having two capsules and dirtying one, so
  # `briefCases` instantiates this same text against a throwaway checkout in a
  # build sandbox. One text, two instantiations, no second copy of an invariant.
  runner = workdir:
    pkgs.writeText "capsule-brief-run" ''
      # Deliberately not `set -e`: every exit below is chosen, and each one says
      # which of the three preconditions failed rather than vanishing at the first
      # non-zero.
      set -uo pipefail

      work=${lib.escapeShellArg workdir}
      commit=''${1:-}
      codeOid=''${2:-}

      if [ -z "$commit" ] || [ -z "$codeOid" ]; then
        echo "capsule-brief: usage: <commit> <code-oid>" >&2
        exit 2
      fi

      cd "$work" 2>/dev/null || {
        echo "capsule-brief: no checkout at $work" >&2
        exit 2
      }

      head=$(git rev-parse --verify --quiet HEAD) || {
        echo "capsule-brief: $work has no commit — capsule-provision first" >&2
        exit 2
      }

      # The control, and the reason this is git rather than tar at both ends. See
      # the header: a state tree carries worktree content, so it is only ever the
      # state of one commit and laying it over another makes a checkout that never
      # existed anywhere — which then gets read as one.
      if [ "$head" != "$codeOid" ]; then
        echo "capsule-brief: that state was the state of $codeOid, and this checkout" >&2
        echo "  is at $head. Refusing: the tree carries the other capsule's" >&2
        echo "  uncommitted work, and over different code that composes a worktree" >&2
        echo "  nobody ever had." >&2
        echo "  Provision this capsule at $codeOid first — if that commit is not in" >&2
        echo "  the target repo yet, it is the source capsule's collected code half." >&2
        exit 3
      fi

      # A brief overwrites tracked files, and that is intended — see above. What it
      # must not do is overwrite an agent's *own* uncommitted work, which is
      # exactly what it cannot tell apart afterwards. Immediately after a provision
      # this is empty by construction, because `updateInstead` only lets a push
      # land on a clean tree; a second brief onto an already-briefed capsule is
      # what this refuses, deliberately and with no override.
      if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "capsule-brief: this checkout has uncommitted changes to tracked files," >&2
        echo "  and a brief overwrites tracked files with another capsule's worktree" >&2
        echo "  content. There would be no way to tell the two apart afterwards, so" >&2
        echo "  nothing was written. Commit or discard them, or re-provision." >&2
        exit 3
      fi

      git rev-parse --verify --quiet "$commit^{commit}" >/dev/null || {
        echo "capsule-brief: $commit is not in this guest's repository — the push" >&2
        echo "  that should have put it there did not land." >&2
        exit 2
      }

      # An index of ours, never the agent's. The symmetry runs the whole length of
      # this channel: the source guest built the tree in a temporary index so its
      # agent's index never learned the paths (host/state-snapshot.nix), the host
      # reads it back through one (host/adopt.nix), and this writes it through one.
      # No repository anywhere has an index worth contaminating.
      #
      # Explicit per call rather than exported, which is not fastidiousness: with
      # `GIT_INDEX_FILE` in the environment, the `git status` below would compare
      # the worktree against the *state tree* and rewrite that index on the way
      # past — silently, and with a plausible wrong answer (the same trap
      # `host/state-snapshot.nix` orders itself around).
      idx=$(mktemp -u "''${TMPDIR:-/tmp}/capsule-brief-index.XXXXXX")
      trap 'rm -f "$idx"' EXIT
      gidx() { GIT_INDEX_FILE="$idx" git "$@"; }

      # git's own writer rather than a second one made of shell and tar. It also
      # refuses the path class independently of the host's check
      # (`error: invalid path '.git/…'`), which is the arrangement to want when the
      # other refusal is upstream and out of sight from here.
      gidx read-tree "$commit" || {
        echo "capsule-brief: read-tree refused $commit — see its message above." >&2
        exit 1
      }

      # `.capsule/` is *this system's* namespace inside a state tree, not the
      # target's: `dirty.diff` is a record *of* a worktree rather than part of one.
      # Writing it here would put it on disk as untracked content, which the next
      # collect from this capsule would pick up and carry again as though this
      # agent had written it. Dropped from the index and not from the tree, so the
      # exhibit in quarantine keeps it and `capsule <src> adopt` still hands it
      # over.
      while IFS= read -r -d "" p; do
        gidx update-index --force-remove -- "$p"
      done < <(gidx ls-files -z -- .capsule)

      files=$(gidx ls-files | wc -l)

      # `-f`, and the two refusals above are what earn it: same code, clean tree.
      gidx checkout-index -a -f || {
        echo "capsule-brief: checkout-index refused — see its message above." >&2
        exit 1
      }

      printf '%s\t%s\n' "$files" "$(git status --porcelain | wc -l)"
    '';

  script = guestExec.checked (runner workdir);
  # `rec`, so the standalone program is the fragment plus an argument parse
  # rather than a second spelling of the same sequence.
in rec {
  # The same text at another checkout, for `briefCases` in `flake.nix`. Lint
  # included: a case suite that ran an unlinted render would be asserting about
  # a program this repo does not ship.
  runnerFor = w: guestExec.checked (runner w);
  # The whole of it as one shell function, so `capsule-provision --state` and
  # `capsule-brief` are one construction and not two careful ones. It needs
  # `$capsule` and `ssh_cmd` in scope, which every transport fragment sets, and
  # it brings its own quarantine and exhibit fragments so that a call site has
  # exactly one thing to splice.
  fragment = ''
    ${quarantine.fragment}
    ${exhibit.fragment}

    # `<capsule>[:<stage>]` — the source, and which link of its chain. Two tokens
    # on one argument, each bounded before it reaches a ref or a path, and both
    # bounded **separately from the work**: `capsule-provision` calls this while
    # parsing its arguments and calls `briefState` after the push, so a misspelt
    # `--state` is refused before any code lands rather than after it. An
    # argument error is not a partial result.
    #
    # `$2` is what the operator actually typed it after, because this runs under
    # two spellings — `capsule-provision --state a` and `capsule-brief a` — and a
    # refusal that quotes the wrong one sends the reader looking in the wrong
    # place. That is the whole reason `checkToken` takes a `shown` at all.
    briefCheckSpec() {
      local spec="$1" flag="''${2:---state}"
      briefSrc="''${spec%%:*}"
      briefStage=implementation
      case "$spec" in *:*) briefStage="''${spec#*:}" ;; esac
      ${quarantine.checkToken ''"$briefSrc"'' "'$flag $spec'"}
      ${quarantine.checkToken ''"$briefStage"'' "'$flag $spec'"}

      if [ "$briefSrc" = "$capsule" ]; then
        echo "capsule-brief: '$briefSrc' is this capsule. A brief moves state" >&2
        echo "  between two of them; what puts a capsule's own state back is a" >&2
        echo "  provision." >&2
        return 1
      fi
    }

    briefState() {
      local spec="$1" flag="''${2:---state}"
      local src stage q commit codeOid line files dirty l
      briefCheckSpec "$spec" "$flag" || return 1
      src="$briefSrc"
      stage="$briefStage"

      q=${quarantine.repoOf "$src"}
      if [ ! -d "$q" ]; then
        echo "capsule-brief: nothing has been collected for '$src' — there is no" >&2
        echo "  quarantine at $q. 'capsule $src collect' first." >&2
        return 1
      fi

      if ! commit=$(git --git-dir="$q" rev-parse --verify --quiet \
        "${quarantine.stateRefsOf "$src"}/$stage^{commit}"); then
        echo "capsule-brief: $src has no state at stage '$stage'." >&2
        echo "  collected stages:" >&2
        git --git-dir="$q" for-each-ref --format='    %(refname:lstrip=4)' \
          "${quarantine.stateRefsOf "$src"}/" >&2 || true
        return 1
      fi

      # Which code this state was the state of, out of the commit message the
      # snapshot wrote (host/state-snapshot.nix). Read with the shell rather than
      # with `sed`, so a refusal never depends on a tool being on PATH.
      codeOid=""
      while IFS= read -r l; do
        case "$l" in "code-oid: "*) codeOid="''${l#code-oid: }" ;; esac
      done < <(git --git-dir="$q" show -s --format='%B' "$commit")
      if [ -z "$codeOid" ] || [ "$codeOid" = - ]; then
        echo "capsule-brief: that state commit names no code-oid, so there is" >&2
        echo "  nothing to check this capsule's checkout against — and the check is" >&2
        echo "  the whole reason a tree of someone else's worktree may land here." >&2
        return 1
      fi

      # Before the push, not after it: the check is upstream of every write on
      # both sides of the door.
      readExhibit "$q" "$commit"
      refuseExhibit "$q" "$commit"
      echo "capsule-brief: $src state/$stage $(git --git-dir="$q" rev-parse --short "$commit") -> $capsule"
      echo "  $total entries ($blobs files, $links symlinks), $bytes bytes, of code $codeOid"

      # Into the guest's own outbound namespace, under the stage it already had.
      # Not forced: a destination that has collected at this stage has its own
      # commit there, and overwriting one capsule's chain with another's is not
      # something a flag should make easy. It also means a later collect from
      # this capsule at this stage chains onto what it was given, which is the
      # provenance record item 32 described and reserved.
      if ! git --git-dir="$q" push --quiet ${lib.escapeShellArg guestRepo} \
        "$commit:refs/capsule/state/$stage"; then
        echo "capsule-brief: could not push that commit into $capsule — is the VM" >&2
        echo "  up, and has it already collected a state of its own at '$stage'?" >&2
        return 1
      fi

      if ! line=$("''${ssh_cmd[@]}" ${lib.escapeShellArg guestHost} 'bash -s' -- \
        "$commit" "$codeOid" < ${script}); then
        echo "capsule-brief: the guest refused to lay that state out (above)." >&2
        return 1
      fi
      IFS=$'\t' read -r files dirty <<<"$line"
      echo "capsule-brief: $files files into $capsule's checkout, which now differs"
      echo "  from its HEAD in $dirty paths — that difference is the other agent's"
      echo "  uncommitted work, and it is the point rather than a mess."
    }
  '';

  # Separately invocable for `host/refresh.nix`'s reasons, which are the same
  # ones a step of a sequence always has: a provision that failed *at* this step
  # needs a way to retry only it, and a human who has provisioned by hand wants
  # this and no push. It is also how the thing is exercised without a provision.
  program = pkgs.writeShellApplication {
    name = "capsule-brief";
    runtimeInputs = [pkgs.git pkgs.openssh pkgs.coreutils];
    text = ''
      ${gitSsh}
      ${fragment}

      usage() {
        echo "usage: capsule-brief [--capsule <name>] <source>[:<stage>]"
        echo
        echo "  Puts <source>'s collected state into this capsule's checkout, so a"
        echo "  second agent can read the first one's working state. Both capsules"
        echo "  must be at the same commit; the stage defaults to 'implementation'."
      }

      spec=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -*)
            usage >&2
            exit 1
            ;;
          *)
            [ -z "$spec" ] || {
              echo "capsule-brief: one source, and '$spec' was already it." >&2
              exit 1
            }
            spec="$1"
            ;;
        esac
        shift
      done
      if [ -z "$spec" ]; then
        echo "capsule-brief: which capsule's state? An exhibit comes from one." >&2
        usage >&2
        exit 1
      fi

      briefState "$spec" capsule-brief
    '';
  };
}
