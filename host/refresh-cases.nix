# The third step of a provision, run against commands that are not this
# target's — which is the whole point, because the branches worth pinning are
# chosen by what the *target's* command does and no target can be asked to
# fail on demand (NOTES item 47).
#
# The fifth instance of the third kind of check, and the one that had no seam
# until the bug it exists for was found on a live host: the script takes the
# command line and the checkout, this host's call site passes `target.refresh`
# and `target.guestPath`, and there is one text.
#
# **The invocation is load-bearing and is not `bash <script>`.** These run the
# script the way a guest does — `bash -s` with the script on stdin — because
# the defect this suite exists for is a command *inside* the script reading
# that stdin. A case that ran `bash <script>` would pass against the broken
# text, which is the same shape of vacuous pass as a probe asserting a
# convention it spelled itself (NOTES item 38).
#
# Only built for a target that derives something, on the same rule as its
# neighbours — the call site's condition, not this file's.
{
  pkgs,
  lib,
  # One text, no instantiation
  # ([item 51](../docs/ledger/051-the-target-in-four-store-paths.md)). The
  # checkout and the command are arguments now, so a suite that wants a command
  # no target would run passes one rather than building a second copy of this
  # program — and this is `host/refresh.nix`'s script as it ships.
  script,
}: let
  # A command that reads stdin and writes a tracked file — doctrine's refresh
  # in miniature, and the only shape that discriminates. `cat` is not a
  # caricature of a TUI here: at this boundary a TUI that drains stdin and
  # `cat` are the same program, which is what the live control established.
  greedy = "cat >/dev/null; echo regenerated >derived.txt";
  # The same write with stdin left alone, so a red case can be told from a
  # suite that cannot pass at all.
  polite = "echo regenerated >derived.txt";
in
  pkgs.runCommand "capsule-refresh-cases" {nativeBuildInputs = [pkgs.git];} ''
    export HOME=$PWD GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    fail=0
    ck() {
      if [ "$2" = "$3" ]; then echo "ok   $1" >>"$log"
      else echo "FAIL $1: exit $3, wanted $2" >&2; fail=1; fi
    }
    ckt() {
      if "''${@:2}"; then echo "ok   $1" >>"$log"
      else echo "FAIL $1" >&2; fail=1; fi
    }
    log=$PWD/log
    : >"$log"

    # A checkout shaped like one a provision has just landed on: clean, one
    # commit, a tracked file the refresh will rewrite and an ignored one it
    # will not.
    seed() {
      rm -rf src && mkdir src && cd src
      git init -q --initial-branch=work .
      printf '%s\n' 'ignored.txt' > .gitignore
      echo original >derived.txt
      git add -A && git commit -qm base
      cd ..
    }
    # As a guest runs it: the script *is* stdin, and everything it is about
    # arrives on the command line beside it — `bash -s <args>` is how a value
    # reaches a script that has already claimed stdin.
    run() { bash -s src "$1" <${script} >out 2>err; }

    # ------------------------------------------- the command that eats stdin
    #
    # The defect, and the reason `</dev/null` is in the file. Before the fix
    # every one of these fails: the script is truncated at the command, so the
    # run is a silent success that commits nothing.
    seed
    rc=0; run ${lib.escapeShellArg greedy} || rc=$?
    ck "a refresh whose command reads stdin still finishes" 0 "$rc"
    ckt "  and commits the tracked half" \
      test "$(git -C src rev-list --count HEAD)" = 2
    ckt "  and says which commit it made" grep -q 'committed' out
    ckt "  leaving the checkout clean for the next provision" \
      test -z "$(git -C src status --porcelain --untracked-files=no)"

    # The control. Same write, stdin untouched — so a suite that went red
    # everywhere would be caught here rather than read as this finding.
    seed
    rc=0; run ${lib.escapeShellArg polite} || rc=$?
    ck "and so does one that leaves stdin alone" 0 "$rc"
    ckt "  with the same commit" test "$(git -C src rev-list --count HEAD)" = 2

    # ------------------------------------------------------ a failing refresh
    #
    # The header's own requirement — a refresh that fails must be **loud** —
    # asserted against a command that fails *and* eats stdin, which is the
    # pairing that was silently returning 0.
    seed
    rc=0; run ${lib.escapeShellArg "cat >/dev/null; exit 7"} || rc=$?
    ck "a failing refresh is the run's status" 7 "$rc"
    ckt "  and says so" grep -q 'exited 7' err
    ckt "  and commits nothing" test "$(git -C src rev-list --count HEAD)" = 1

    # ---------------------------------------------------- nothing to commit
    #
    # A refresh that writes only ignored files moves neither reading, so every
    # branch below the comparison is inert for it — including, now, the fact
    # that it is reached at all.
    seed
    rc=0; run ${lib.escapeShellArg "cat >/dev/null; echo x >ignored.txt"} || rc=$?
    ck "a refresh that writes only ignored files commits nothing" 0 "$rc"
    ckt "  and leaves HEAD alone" test "$(git -C src rev-list --count HEAD)" = 1

    # ------------------------------------------------- already dirty before
    #
    # The refusal that keeps the commit honest: with tracked changes present
    # before the command ran, there is no way to tell them from its output, so
    # nothing is committed and it is loud about why.
    seed
    echo "somebody else's edit" >src/derived.txt
    rc=0; run ${lib.escapeShellArg greedy} || rc=$?
    ck "a refresh onto an already-dirty checkout refuses" 3 "$rc"
    ckt "  naming the reason and not the symptom" \
      grep -q 'no way to tell the two' err
    ckt "  and commits nothing" test "$(git -C src rev-list --count HEAD)" = 1

    # ------------------------------------------- what used to be in the text
    #
    # Five commands have already gone through one store path above, which is
    # the command half of [item 51](../docs/ledger/051-the-target-in-four-store-paths.md)
    # asserted by the shape of this suite rather than by a case. The checkout
    # half needs one, because every case so far names the same directory the
    # old text baked.
    seed
    rm -rf elsewhere && mkdir elsewhere && cd elsewhere
    git init -q --initial-branch=work .
    echo original >derived.txt
    git add -A && git commit -qm base
    cd ..
    rc=0; bash -s elsewhere ${lib.escapeShellArg polite} <${script} >out 2>err || rc=$?
    ck "the checkout is an argument, not the text" 0 "$rc"
    ckt "  and the second repository is the one that moved" \
      test "$(git -C elsewhere rev-list --count HEAD)" = 2
    ckt "  while the first stands still" \
      test "$(git -C src rev-list --count HEAD)" = 1

    # A refusal rather than a run against whatever the guest's cwd happens to
    # be: this is item 28's rule where the fall-back value is a directory.
    rc=0; bash -s <${script} >out 2>err || rc=$?
    ck "a refresh with no arguments refuses" 2 "$rc"
    ckt "  and says what it wanted" grep -q 'usage: <work> <command>' err

    [ "$fail" = 0 ] || exit 1
    cp "$log" $out
    cat $out
  ''
