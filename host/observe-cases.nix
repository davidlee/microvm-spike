# The guest half of a status, run against fixtures no capsule would produce
# on demand — and the first suite for a program that had none
# ([item 51](../docs/ledger/051-the-target-in-four-store-paths.md)). It was
# three interpolated paths and no case, which is the pairing that let a whole
# class of defect live in `capsule-netns` unread by shellcheck (NOTES item 37):
# a program nothing builds is a program nothing checks.
#
# What a live host cannot cheaply reach here is the *unhappy* half — an
# unprovisioned volume, a baseline that failed, a run in flight — each of which
# means driving a real capsule into that state and reading it before it leaves.
#
# The contract is one tab-separated line, `head dirty baseline stamp disk`,
# defined in `host/observe.nix` and nowhere else, so every case reads a field
# by number and none of them counts words.
{
  pkgs,
  # `host/observe.nix` as it ships, never a second render of it.
  observe,
  # And the other end of its interface, which is what step 4 made worth pinning:
  # the fragment `host/cli.nix` builds that command line with — the profile
  # reader, the record convention and the argument order composed in
  # `host/programs.nix`. The order in the fragment and the order the script reads
  # are two readings of one fact, and a suite that only ever composed the line by
  # hand would agree with itself. This one is **silent** when it disagrees: a
  # status would answer about the wrong three directories and every field would
  # look plausible.
  observeFragment,
  inputs,
}: let
  # The fragment plus the smallest `main` that exercises it.
  argv = pkgs.writeShellApplication {
    name = "capsule-observe-argv";
    runtimeInputs = inputs;
    text = ''
      ${observeFragment}
      profileLoad "$1"
      observeArgs
    '';
  };
in
  pkgs.runCommand "capsule-observe-cases" {nativeBuildInputs = [pkgs.git pkgs.jq];} ''
    export HOME=$PWD GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    fail=0
    ck() {
      if [ "$2" = "$3" ]; then echo "ok   $1" >>"$log"
      else echo "FAIL $1: got '$3', wanted '$2'" >&2; fail=1; fi
    }
    log=$PWD/log
    : >"$log"

    # Field by number, never by position in a sentence: this is the only
    # definition of that order and a suite that re-spelled it would agree with
    # itself rather than with the program.
    f() { cut -f"$1" out; }
    run() { bash ${observe} "$@" >out 2>err; }

    # ------------------------------------------------- nothing provisioned yet
    #
    # What a fresh volume answers, and the reason every field has a `-`: this
    # is a state to report, not an error to abort on.
    mkdir -p vol/rec
    rc=0; run vol/nothing vol/rec vol || rc=$?
    ck "an unprovisioned checkout still answers" 0 "$rc"
    ck "  head is unknown" - "$(f 1)"
    ck "  dirty is unknown" - "$(f 2)"
    ck "  and no baseline has ever run" none "$(f 3)"
    ck "  while the volume still reports its disk" 1 "$(f 5 | grep -c '%')"

    # ------------------------------------------------------ a clean checkout
    mkdir -p vol/work && cd vol/work
    git init -q --initial-branch=work .
    echo code >src.txt
    git add -A && git commit -qm base
    oid=$(git rev-parse HEAD)
    cd ../..
    rc=0; run vol/work vol/rec vol || rc=$?
    ck "a provisioned checkout answers its head" 0 "$rc"
    # The **full** oid: the caller shortens it for a column, and the assignment
    # record pins it. A pin is not an abbreviation.
    ck "  in full, not abbreviated" "$oid" "$(f 1)"
    ck "  and says it is clean" no "$(f 2)"

    echo "the agent's edit" >>vol/work/src.txt
    run vol/work vol/rec vol
    ck "an edited worktree is dirty" yes "$(f 2)"

    # ------------------------------------------------------------- the record
    #
    # **The record, never an exit status** (NOTES item 24): the line on the
    # volume was right throughout the period the status was wrong, which is
    # why a status reads it rather than asking anything to re-run.
    printf 'stamp\tstatus\tseconds\tcommit\tmib_before\tmib_after\tcommand\n' \
      > vol/rec/history.tsv
    printf '20260101T000000Z\t0\t61\tabc\t1\t2\tjust test\n' >> vol/rec/history.tsv
    run vol/work vol/rec vol
    ck "a green baseline is ok" ok "$(f 3)"
    ck "  and its stamp is the host's" 20260101T000000Z "$(f 4)"

    printf '20260102T000000Z\t7\t61\tabc\t1\t2\tjust test\n' >> vol/rec/history.tsv
    run vol/work vol/rec vol
    ck "a failed baseline carries its status" fail:7 "$(f 3)"
    ck "  and the last run is the one reported" 20260102T000000Z "$(f 4)"

    # A run in flight outranks the last verdict — the answer to "what is this
    # slot doing" is not what it did yesterday.
    echo $$ > vol/rec/running
    run vol/work vol/rec vol
    ck "a live run outranks the last record" running "$(f 3)"
    # A pid file left behind by a killed run is not a run. `1` is init, which
    # exists and is not ours; the check is liveness, not existence.
    echo 2147483646 > vol/rec/running
    run vol/work vol/rec vol
    ck "a stale pid file is not a run" fail:7 "$(f 3)"
    rm vol/rec/running

    # ------------------------------------------- what used to be in the text
    #
    # Three paths, one store path, and each of them named by the caller
    # ([item 51](../docs/ledger/051-the-target-in-four-store-paths.md)). A
    # second volume in the same run is the smallest form of the claim: two
    # projects, one program.
    mkdir -p other/rec other/work && cd other/work
    git init -q --initial-branch=work .
    echo elsewhere >other.txt
    git add -A && git commit -qm base
    second=$(git rev-parse HEAD)
    cd ../..
    printf 'stamp\tstatus\tseconds\tcommit\tmib_before\tmib_after\tcommand\n' \
      > other/rec/history.tsv
    printf '20260303T000000Z\t0\t9\tdef\t1\t2\tmake\n' >> other/rec/history.tsv
    run other/work other/rec other
    ck "the checkout is an argument" "$second" "$(f 1)"
    ck "  and so is the record directory" 20260303T000000Z "$(f 4)"
    ck "  and the two answers differ" different \
      "$(if [ "$second" != "$oid" ]; then echo different; else echo same; fi)"

    rc=0; run vol/work >/dev/null 2>&1 || rc=$?
    ck "a status with too few arguments refuses" 2 "$rc"

    # ----------------------------------------- and where the caller gets them
    #
    # The front end no longer spells those three: it loads a document and calls
    # `observeArgs` (host/programs.nix). What has to hold is that the order it
    # prints is the order this script reads, and that the record directory is the
    # one `capsule-baseline` writes — a convention neither end declares and both
    # derive. A disagreement here is silent at every field.
    mkdir -p profiles third/third third/baseline && cd third/third
    git init -q --initial-branch=work .
    echo third >third.txt
    git add -A && git commit -qm base
    third=$(git rev-parse HEAD)
    cd ../..
    printf 'stamp\tstatus\tseconds\tcommit\tmib_before\tmib_after\tcommand\n' \
      > third/baseline/history.tsv
    printf '20260404T000000Z\t0\t9\tabc\t1\t2\tmake\n' >> third/baseline/history.tsv
    jq -n --arg v "$PWD/third" \
      '{ schema: 1, name: "third", path: "/h/third", guestPath: ($v + "/third"),
         volumePath: $v, cachePaths: [], baseline: "b", refresh: null,
         statePaths: [], stateMaxBytes: 0,
         sizes: {vcpu: 1, mem: 1, volume: 1} }' > profiles/third.json
    mapfile -t fromDoc < <(CAPSULE_PROFILE_DIR=$PWD/profiles ${pkgs.lib.getExe argv} third)
    ck "the caller's tail is three words" 3 "''${#fromDoc[@]}"
    run "''${fromDoc[@]}"
    ck "  naming the checkout the document does" "$third" "$(f 1)"
    # The convention, asserted rather than commented: `<volume>/baseline`, derived
    # once in host/programs.nix and read from both ends.
    ck "  the record directory beside it, not in it" 20260404T000000Z "$(f 4)"
    ck "  and the volume, which is the disk column" 1 "$(f 5 | grep -c '%')"

    [ "$fail" = 0 ] || exit 1
    cp "$log" $out
    cat $out
  ''
