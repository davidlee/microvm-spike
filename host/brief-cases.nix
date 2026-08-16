# `capsule-brief`'s guest half, run against hand-built git objects.
#
# The third kind of check (CLAUDE.md), a second instance of it: `guard-cases.nix`
# runs the guard's own text with its tools stubbed, and this runs the brief
# runner's own text in a git repository the sandbox builds. Same argument for
# the same reason — the branches that decide whether an exhibit may land are
# a `code-oid` that does not match and a worktree somebody else dirtied, and
# reaching those on a live host means two capsules and a deliberate mess in
# one of them. The seam is `host/brief.nix`'s `runner`, a function of the
# checkout it runs in, exactly as the guard's is a function of its tools.
#
# Only built for a target that declares `statePaths`: with no program there is
# nothing to assert about one, which is the call site's condition and not this
# file's.
{
  pkgs,
  # One text, no instantiation ([item 51](../docs/ledger/051-the-target-in-four-store-paths.md)):
  # the checkout the guest half lays a tree out in is its third argument now, so
  # the sandbox runs the store path a capsule runs rather than a copy of it
  # built for `dest`. Which is also why they arrive here rather than being
  # rebuilt: a suite runs the store path the program ships.
  runner,
  spec,
}:
pkgs.runCommand "capsule-brief-cases" {nativeBuildInputs = [pkgs.git];} ''
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

  # ------------------------------------------------- the source capsule
  #
  # A checkout shaped like the one this was written from: authored content
  # under a declared path, an agent's uncommitted edit to it, runtime state
  # that is only ever ignored, and the contained symlink item 34 found.
  mkdir src && cd src
  git init -q --initial-branch=work .
  mkdir -p .doctrine/state/slice/254/phases .doctrine/slice/254
  echo authored >.doctrine/slice/254/spec.md
  echo code >src.txt
  git add -A && git commit -qm base
  code=$(git rev-parse HEAD)
  echo "edited by the agent" >.doctrine/slice/254/spec.md
  echo "phase 3 notes" >.doctrine/state/slice/254/phases/03.md
  ln -s ../../state/slice/254/phases .doctrine/slice/254/phases

  # The outbound snapshot, built as `host/state-snapshot.nix` builds one —
  # temporary index, the `.capsule/dirty.diff` blob, the same message
  # fields. Hand-built rather than run, because that program's own
  # invocation is an ssh into a guest.
  git diff HEAD >../dirty.patch
  export GIT_INDEX_FILE=$PWD/../tmpidx
  git read-tree --empty
  git add -f -- .doctrine/state/slice .doctrine/slice
  blob=$(git hash-object -w --stdin <../dirty.patch)
  git update-index --add --cacheinfo "100644,$blob,.capsule/dirty.diff"
  tree=$(git write-tree)
  state=$(printf '%s\n' "capsule state: implementation" "" \
    "stage: implementation" "code-oid: $code" "dirty: 2" |
    git commit-tree "$tree")
  git update-ref refs/capsule/state/implementation "$state"
  unset GIT_INDEX_FILE
  cd ..

  # -------------------------------------------------- the guest briefed
  git clone -q src dest -b work
  git -C dest fetch -q "$PWD/src" '+refs/capsule/state/*:refs/capsule/state/*'

  rc=0; bash ${runner} "$state" 0000000000000000000000000000000000000000 dest >out 2>&1 || rc=$?
  ck "refuses a state that was the state of other code" 3 "$rc"
  ckt "  and names the commit it was of" grep -qF "that state was the state of" out
  ckt "  and wrote nothing" test ! -e dest/.doctrine/state/slice/254/phases/03.md

  echo mine >>dest/src.txt
  rc=0; bash ${runner} "$state" "$code" dest >out 2>&1 || rc=$?
  ck "refuses over an agent's own uncommitted work" 3 "$rc"
  ckt "  and wrote nothing" test ! -e dest/.doctrine/state/slice/254/phases/03.md
  git -C dest checkout -q -- src.txt

  rc=0; bash ${runner} "$state" "$code" dest >out 2>&1 || rc=$?
  ck "lays the tree out over matching code" 0 "$rc"
  ckt "  the ignored runtime file landed" test -f dest/.doctrine/state/slice/254/phases/03.md
  # The whole reason the code-oid check earns the overwrite: a state tree
  # carries worktree content, so this is the other agent's edit and not the
  # commit's version of the file.
  ckt "  the tracked file carries the other agent's edit" \
    test "$(cat dest/.doctrine/slice/254/spec.md)" = "edited by the agent"
  ckt "  the contained symlink resolves after extraction" \
    test "$(cat dest/.doctrine/slice/254/phases/03.md)" = "phase 3 notes"
  # `.capsule/` is this system's namespace, not the target's: on disk it
  # would be untracked content the *next* collect carries again.
  ckt "  .capsule/ is not on disk" test ! -e dest/.capsule
  ckt "  and .capsule/ is still in the exhibit" \
    test -n "$(git -C dest ls-tree -r --name-only "$state" -- .capsule)"
  ckt "  the agent's real index was not touched" \
    test -z "$(git -C dest diff --cached --name-only)"
  ckt "  the worktree now differs from its HEAD" \
    test -n "$(git -C dest status --porcelain)"

  rc=0; bash ${runner} "$state" "$code" dest >out 2>&1 || rc=$?
  ck "refuses a second brief onto an already-briefed capsule" 3 "$rc"

  # ------------------------------------------- what used to be in the text
  #
  # The checkout, which every case above names as the same directory the old
  # text baked ([item 51](../docs/ledger/051-the-target-in-four-store-paths.md)).
  # A second capsule of the same source, briefed by the same store path in
  # the same run — and the refusal above is what makes it discriminate, since
  # a text that ignored the argument would refuse this as already briefed.
  git clone -q src second -b work
  git -C second fetch -q "$PWD/src" '+refs/capsule/state/*:refs/capsule/state/*'
  rc=0; bash ${runner} "$state" "$code" second >out 2>&1 || rc=$?
  ck "the checkout is an argument, not the text" 0 "$rc"
  ckt "  and the tree landed in that one" \
    test -f second/.doctrine/state/slice/254/phases/03.md
  ckt "  while the first is untouched by it" \
    test "$(cat dest/.doctrine/slice/254/spec.md)" = "edited by the agent"

  # ------------------------------------------------ which names a source
  #
  # The half [item 42](../docs/ledger/042-a-state-half-no-capsule-has-held.md)
  # had to decide, and the only half of this file that needs no guest: **a
  # quarantine is what a capsule sent back**, not a place state lives. So a
  # directory of the right shape under a name nobody declared is not a
  # source, and the host's own checkout is a flag rather than a name.
  #
  # `dest` is this capsule here, matching the fixture above.
  for src in a b; do
    rc=0; bash ${spec} "$src" >out 2>err || rc=$?
    ck "'$src' is a declared slot and may be a source" 0 "$rc"
  done
  rc=0; bash ${spec} a:audit >out 2>err || rc=$?
  ck "a stage rides the source name" 0 "$rc"

  rc=0; bash ${spec} dest >out 2>err || rc=$?
  ck "refuses this capsule as its own source" 1 "$rc"
  ckt "  and says a brief moves state between two capsules" \
    grep -q 'is this capsule' err

  rc=0; bash ${spec} scratch >out 2>err || rc=$?
  ck "refuses a name that is not a slot" 1 "$rc"
  ckt "  and says a quarantine is what a capsule sent back" \
    grep -q 'what a capsule sent back' err
  ckt "  and names the other origin" grep -q -- '--from-host' err
  rc=0; bash ${spec} ../a >out 2>err || rc=$?
  ck "refuses a source that is not a name at all" 1 "$rc"

  [ "$fail" = 0 ] || exit 1
  cp "$log" $out
  cat $out
''
