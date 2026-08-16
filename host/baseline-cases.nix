# The guest half of a baseline, run against commands no target can be asked to
# supply — the second suite for a program that had none
# ([item 51](../docs/ledger/051-the-target-in-four-store-paths.md)), and the
# same argument `refresh-cases.nix` makes: the branches worth pinning are chosen
# by what the *target's* build does, and this target's build takes an hour and
# goes green.
#
# What a live host cannot cheaply reach: a build that fails (a red recorded as
# a result rather than an error), a checkout with no commit (a red that is a
# mistake and must not enter the record), and a run already in flight (which
# must attach rather than interleave a second set of figures into one file).
#
# `run` rather than `start` wherever a case is about the record, because
# `start` detaches and a suite that raced the detached half would be timing a
# build in a sandbox.
{
  pkgs,
  # `host/baseline.nix`'s `runner` as it ships, never a second render of it.
  runner,
}:
pkgs.runCommand "capsule-baseline-cases" {
  nativeBuildInputs = [pkgs.git pkgs.util-linux];
} ''
  export HOME=$PWD GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  fail=0
  ck() {
    if [ "$2" = "$3" ]; then echo "ok   $1" >>"$log"
    else echo "FAIL $1: got '$3', wanted '$2'" >&2; fail=1; fi
  }
  ckt() {
    if "''${@:2}"; then echo "ok   $1" >>"$log"
    else echo "FAIL $1" >&2; fail=1; fi
  }
  log=$PWD/log
  : >"$log"

  # A record directory and a checkout, the way a provisioned capsule has
  # them: the record beside the checkout and never inside it, because a
  # record in the worktree is the dirty worktree the next provision refuses.
  #
  # **Absolute, and that is not tidiness**: the `run` verb `cd`s into the
  # checkout before it writes anything, so a relative record directory would
  # be written *inside* the tree being built — which is the one placement
  # this program exists to avoid.
  seed() {
    rm -rf rec work && mkdir -p rec work && cd work
    git init -q --initial-branch=work .
    echo code >src.txt
    git add -A && git commit -qm base
    cd ..
  }
  # The field order is `host/baseline.nix`'s, and this suite reads it by
  # number rather than re-spelling it.
  field() { tail -1 "$1/history.tsv" | cut -f"$2"; }

  # ---------------------------------------------------------- a green run
  seed
  rc=0; bash ${runner} run 20260101T000000Z "$PWD/rec" "$PWD/work" 'echo built' "$PWD/work" \
    >ran 2>&1 || rc=$?
  ck "a green build is recorded" 0 "$rc"
  ckt "  and the file explains itself" grep -q '^stamp	status' rec/history.tsv
  ck "  the status is the command's" 0 "$(field rec 2)"
  ck "  under the stamp the host minted" 20260101T000000Z "$(field rec 1)"
  ck "  and the command is on the line" "echo built" "$(field rec 7)"
  ckt "  the command's own output is in the run's" grep -qx built ran
  ckt "  the marker is gone afterwards" test ! -e rec/running

  # ------------------------------------------------------------ a red run
  #
  # **A failing build is a result, not an error** — the whole question this
  # program asks. So the run itself is still 0 and the record carries the
  # status, which is the property NOTES item 24 was about from the other end.
  rc=0; bash ${runner} run 20260102T000000Z "$PWD/rec" "$PWD/work" 'exit 3' "$PWD/work" \
    >/dev/null 2>&1 || rc=$?
  ck "a failing build still records" 0 "$rc"
  ck "  with the build's status on the line" 3 "$(field rec 2)"

  # ------------------------------------------- the log is not the terminal
  #
  # `start`'s redirect is what puts a run's output on the volume, and it is
  # the property two lost sizing runs paid for. Only `start` detaches, so
  # this is the one case that waits.
  reply=$(bash ${runner} start 20260103T000000Z "$PWD/rec" "$PWD/work" 'echo built' "$PWD/work")
  ck "a start detaches and says so" "started 20260103T000000Z" "$reply"
  for _ in $(seq 100); do
    [ -n "$(grep 20260103 rec/history.tsv || true)" ] && break
    sleep 0.1
  done
  ckt "  the log is on the volume" test -s rec/20260103T000000Z.log
  ckt "  and names the command it ran" grep -q 'command : echo built' rec/20260103T000000Z.log
  ckt "  and the detached half wrote the record" \
    test -n "$(grep 20260103 rec/history.tsv || true)"

  # ------------------------------------------------- no checkout to build
  #
  # A red for want of a checkout is a mistake and would sit in the record
  # looking like a result. `start`, because that is where the guard is.
  rm -rf empty && mkdir empty
  rc=0; bash ${runner} start 20260104T000000Z "$PWD/rec" "$PWD/empty" 'echo built' "$PWD/empty" \
    >/dev/null 2>err || rc=$?
  ck "a checkout with no commit refuses" 2 "$rc"
  ckt "  and says which step comes first" grep -q 'capsule-provision first' err
  ckt "  and recorded nothing" test -z "$(grep 20260104 rec/history.tsv || true)"

  # ------------------------------------------------- a run already in flight
  #
  # A second run would interleave into one record and make both figures
  # meaningless, so this attaches. The marker is a *live* pid, never the
  # file: a VMM that died under a run leaves the file behind.
  sleep 300 & live=$!
  echo "$live" > rec/running
  printf '%s' 20260101T000000Z > rec/stamp
  reply=$(bash ${runner} start 20260105T000000Z "$PWD/rec" "$PWD/work" 'echo built' "$PWD/work")
  ck "a run in flight is attached, not restarted" "attached 20260101T000000Z" "$reply"
  ckt "  and started nothing of its own" test -z "$(grep 20260105 rec/history.tsv || true)"
  kill "$live" 2>/dev/null || true
  echo 2147483646 > rec/running
  reply=$(bash ${runner} start 20260106T000000Z "$PWD/rec" "$PWD/work" 'echo built' "$PWD/work")
  ck "a stale marker is not a run" "started 20260106T000000Z" "$reply"

  # ------------------------------------------- what used to be in the text
  #
  # Four values, one store path ([item 51](../docs/ledger/051-the-target-in-four-store-paths.md)).
  # The command has already been three different things above, which no
  # target could have supplied; these are the other three.
  rm -rf other && mkdir -p other/rec other/work other/big && cd other/work
  git init -q --initial-branch=work .
  echo elsewhere >other.txt
  git add -A && git commit -qm base
  cd ../..
  head -c 2000000 /dev/zero > other/big/blob
  rc=0; bash ${runner} run 20260201T000000Z "$PWD/other/rec" "$PWD/other/work" 'echo built' \
    "$PWD/other/big" >/dev/null 2>&1 || rc=$?
  ck "the record directory is an argument" 0 "$rc"
  ckt "  and the second record is where it landed" test -s other/rec/history.tsv
  ckt "  while the first is untouched" \
    test -z "$(grep 20260201 rec/history.tsv || true)"

  # The measured paths decide the two figures a recorded run is *for*, so
  # this asks for a number a differently-measured run could not produce:
  # `other/big` is ~2 MiB and every other path here is a few kilobytes.
  ck "the measured paths are an argument" 2 "$(field other/rec 5)"

  rc=0; bash ${runner} run 20260202T000000Z >/dev/null 2>err || rc=$?
  ck "a runner with too few arguments refuses" 64 "$rc"
  ckt "  and says what it wanted" grep -q 'STAMP DIR WORK CMD' err

  [ "$fail" = 0 ] || exit 1
  cp "$log" $out
  cat $out
''
