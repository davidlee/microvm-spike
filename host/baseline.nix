# The last step of making a fresh capsule usable, host-initiated: run the
# target's own build-and-test to green, and record that it went green and what
# it cost. On a fresh volume that run is the **cold build** — the largest term
# in time-to-interactive, and the one figure `probe/freshness.sh` cannot take,
# because its namespace has no upstream (docs/probes.md).
#
# Three properties it exists to keep, and each of them cost something to learn:
#
#   - **The record is not the terminal.** Two sizing runs were lost to a figure
#     whose only copy was scrollback. Every run writes its log and one line of
#     `history.tsv` onto the capsule's volume as it goes, so a closed terminal,
#     a dropped link or a Ctrl-C costs nothing that had already happened. The
#     volume is where a figure survives the session; docs/probes.md is where it
#     survives the capsule.
#   - **The run does not depend on the session.** The guest half detaches into
#     its own session, so the host may leave and come back — re-running this
#     program while one is in flight attaches to it rather than starting a
#     second. A second run would interleave into the same record and make both
#     figures meaningless.
#   - **It is a push, over the channel that already exists.** Same seam as
#     `capsule-provision` and `capsule-inject`: the host initiates, as you,
#     nothing listens, and the guest cannot ask for any of it.
#
# Jail-agnostic in the same sense as `perimeter/` and `git-channel.nix`: it
# knows an ssh destination, a fragment that reaches it, and four guest paths. No
# tap, no namespace, no hypervisor — under netns only `transport` changes, at the
# call site. Target-agnostic too: `command` is a command line and this file has
# no opinion about what is in it.
{
  pkgs,
  # Where to ssh, e.g. `agent@10.99.0.2`. Jail-shaped, so injected.
  guestHost,
  # Which capsule, and how to reach it: a shell fragment setting `$capsule` and
  # the `ssh_cmd` argv, for the reason `host/inject.nix` gives. Jail-shaped, so
  # injected — and required.
  transport,
  # The target's own build-and-test, run by the guest's login shell in `workdir`.
  command,
  # Where to run it — the guest's checkout.
  workdir,
  # Where the log and the record live. Must be outside `workdir`: a record
  # written into the checkout is a dirty worktree, and a dirty worktree is what
  # `receive.denyCurrentBranch = updateInstead` refuses a provision on.
  recordDir,
  # Guest paths to size before and after, so a recorded run says for itself
  # whether it was cold. Per-path in the log, totalled in the record.
  measure,
}: let
  inherit (pkgs) lib;

  cmd = lib.escapeShellArg command;

  # The guest half. Pushed at each run rather than baked into the guest's
  # closure, because it is host-side policy about a measurement, not part of
  # what a capsule is — and because a volume outlives this program, so a runner
  # left on it from an older build would be drift nothing reports.
  #
  # Two verbs in one file: the only quote-free thing the host can say over ssh
  # is `bash -l <path> <word> <word>`, and everything else about this program's
  # remote commands is quoting.
  runner = pkgs.writeText "capsule-baseline-run" ''
    #!/usr/bin/env bash
    #   start STAMP  guard, detach `run`, return
    #   run   STAMP  the run itself, writing its record as it goes
    #
    # Deliberately not `set -e`: a failing build is a result to record, not an
    # error to abort on. It is the whole question this program asks.
    set -uo pipefail

    dir=${lib.escapeShellArg recordDir}
    work=${lib.escapeShellArg workdir}
    measured=(${lib.escapeShellArgs measure})

    verb=''${1:-}
    stamp=''${2:-}
    if [ -z "$verb" ] || [ -z "$stamp" ]; then
      echo "capsule-baseline: usage: run.sh start|run STAMP" >&2
      exit 64
    fi

    running="$dir/running"
    history="$dir/history.tsv"
    log="$dir/$stamp.log"

    # Two questions, and one `du` cannot answer both once a toolchain hardlinks
    # between the paths being measured. What the volume *pays* dedupes hardlinks,
    # so the total stays one invocation over every path. What each tree *holds*
    # does not: in a single `du` a shared inode is charged to whichever argument
    # came first, so a `.venv` hardlinked into a uv cache recorded the checkout at
    # 105 MiB and the cache at 4 when the trees are 8 and 97 — an artefact of
    # argument order, and doctrine never showed it because cargo does not share
    # inodes between `target/` and `.cargo` (NOTES item 23). So the per-path
    # display asks each path on its own, and those may sum to more than the total.
    sizes() {
      local p
      for p in "''${measured[@]}"; do du -sm "$p" 2>/dev/null || true; done
    }
    total() {
      {
        du -sm "''${measured[@]}" 2>/dev/null || true
      } | awk '{n += $1} END {print n + 0}'
    }

    case "$verb" in
      start)
        # A live run owns the record. A stale marker — the VMM died under one —
        # is not a live run, so ask the kernel rather than the file.
        if [ -e "$running" ] && kill -0 "$(cat "$running")" 2>/dev/null; then
          echo "attached $(cat "$dir/stamp")"
          exit 0
        fi
        rm -f "$running"

        # A red for want of a checkout is a mistake, not a result, and it would
        # sit in the record looking like one.
        if ! git -C "$work" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
          echo "capsule-baseline: $work has no commit — capsule-provision first" >&2
          exit 2
        fi

        printf '%s' "$stamp" > "$dir/stamp"
        # A new session, so closing the ssh channel does not SIGHUP the build.
        # That is the point: the host may leave and the run continues.
        #
        # `bash -l` is the *outer* invocation's job (the host's), and this
        # inherits its environment: the proxy and cache variables are
        # `environment.variables`, which is login-shell scope (NOTES item 6), and
        # a build that cannot reach the proxy fails looking like a network fault.
        setsid bash "$0" run "$stamp" </dev/null >"$log" 2>&1 &
        # The child writes $running first thing; wait for it, so the host can
        # attach by pid without racing. Not $! — `setsid` execs or forks
        # depending on whether its caller leads a process group, so $! is not
        # reliably the worker.
        for _ in $(seq 100); do
          [ -e "$running" ] && break
          sleep 0.1
        done
        echo "started $stamp"
        ;;

      run)
        echo "$$" > "$running"
        trap 'rm -f "$running"' EXIT
        cd "$work" || exit 1

        commit=$(git rev-parse --short HEAD 2>/dev/null || echo none)
        before=$(total)
        echo "capsule-baseline $stamp"
        echo "  command : ${cmd}"
        echo "  workdir : $work"
        echo "  commit  : $commit"
        # Cheap, and it turns the commonest failure — no proxy, so nothing
        # fetches — into one line at the top of the log instead of a puzzle.
        echo "  proxy   : ''${http_proxy:-unset}"
        echo "  before  :"
        sizes | sed 's/^/    /'
        echo

        start=$(date +%s)
        ( ${command} )
        status=$?
        seconds=$(( $(date +%s) - start ))

        echo
        echo "  after   :"
        sizes | sed 's/^/    /'
        after=$(total)

        # Header on first write, so the file explains itself wherever it is read
        # — including in a paste into docs/probes.md, which is where these end up.
        [ -s "$history" ] \
          || printf 'stamp\tstatus\tseconds\tcommit\tmib_before\tmib_after\tcommand\n' \
             > "$history"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "$stamp" "$status" "$seconds" "$commit" "$before" "$after" ${cmd} \
          >> "$history"
        echo "capsule-baseline: exit $status in ''${seconds}s"
        ;;

      *)
        echo "capsule-baseline: unknown verb $verb" >&2
        exit 64
        ;;
    esac
  '';

  # The same lint the host-side programs get. `writeShellApplication` would run
  # shellcheck for us but would also bake this host's store paths into a script
  # that runs in the guest, so the check is asked for by hand instead.
  checkedRunner =
    pkgs.runCommand "capsule-baseline-run.sh" {
      nativeBuildInputs = [pkgs.shellcheck];
    } ''
      shellcheck -s bash ${runner}
      cp ${runner} $out
    '';
in
  pkgs.writeShellApplication {
    name = "capsule-baseline";
    runtimeInputs = [pkgs.openssh pkgs.coreutils];
    text = ''
      ${transport}
      host=${lib.escapeShellArg guestHost}
      dir=${lib.escapeShellArg recordDir}

      detach=""
      for arg in "$@"; do
        case "$arg" in
          --detach) detach=1 ;;
          *)
            echo "usage: capsule-baseline [--capsule <name>] [--detach]" >&2
            echo "  runs ${cmd} in the capsule's checkout and records it." >&2
            echo "  run it again while one is in flight to re-attach." >&2
            exit 1
            ;;
        esac
      done

      # The host names the run: the guest's clock is the guest's business, and
      # this is the one name both ends can agree on. Digits and two letters, so
      # it needs no quoting anywhere it is spliced into a remote command below.
      stamp=$(date -u +%Y%m%dT%H%M%SZ)

      "''${ssh_cmd[@]}" "$host" "mkdir -p '$dir' && cat > '$dir/run.sh'" \
        < ${checkedRunner}

      # `bash -l`, and it is load-bearing: `ssh host cmd` is neither a login nor
      # an interactive shell, so it has none of the guest's `environment.variables`
      # — no proxy, no CARGO_HOME, no TMPDIR (NOTES item 6). The detached run
      # inherits this shell's environment.
      reply=$("''${ssh_cmd[@]}" "$host" "bash -l '$dir/run.sh' start $stamp")
      echo "capsule-baseline: $reply"
      # `started STAMP` or `attached STAMP` — the second is an older run, and
      # from here on the two are the same thing.
      stamp=''${reply##* }

      if [ -n "$detach" ]; then
        echo "  in the capsule: $dir/$stamp.log, and $dir/history.tsv when it lands"
        exit 0
      fi

      echo "  Ctrl-C leaves the run going — capsule-baseline again to re-attach."
      trap 'echo; echo "capsule-baseline: detached — the run continues."' INT

      # `tail --pid` exits when the run does, so this is the wait as much as the
      # output; the pid is read in the guest, because the host never knew it.
      # If the run has already finished — a warm baseline can beat this call —
      # there is no pid to wait on and the whole log is simply printed.
      "''${ssh_cmd[@]}" "$host" "
        if pid=\$(cat '$dir/running' 2>/dev/null); then
          tail -n +1 -f --pid=\"\$pid\" '$dir/$stamp.log'
        else
          cat '$dir/$stamp.log'
        fi
      " || true

      line=$("''${ssh_cmd[@]}" "$host" "grep -m1 '^$stamp' '$dir/history.tsv'" || true)
      if [ -z "$line" ]; then
        echo "capsule-baseline: no record for $stamp — still running, or interrupted." >&2
        exit 1
      fi
      status=$(printf '%s' "$line" | cut -f2)
      echo "capsule-baseline: recorded in $dir/history.tsv"
      printf '  %s\n' "$line"
      exit "$status"
    '';
  }
