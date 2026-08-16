# `capsule-collect`'s guest half, run against a checkout the sandbox builds,
# plus the token bound that stands between an assignment and a path.
#
# The third kind of check (CLAUDE.md), a third instance of it, and the branch
# it exists for is item 32's scope invariant: *a collect brings back the
# out-of-band state of the work the capsule was assigned, and none that is
# not*. Reaching that on a live host means a capsule that has driven a real
# unit of work in a checkout holding several — which is a thirteen-hour slice
# and one host, so it is asserted here on a checkout that holds two units and
# costs a second. The seam is `host/state-snapshot.nix`'s script, which takes
# the checkout it runs in on its command line, exactly as `brief.nix`'s runner
# does.
#
# The token cases are here rather than in a suite of their own because they
# are the *other half of the same control*: the bound is what makes a unit
# token safe to substitute into the middle of a path, and a suite that pinned
# the scoping without pinning the bound would pin the half that is easy.
#
# Only built for a target that declares `statePaths`: with no snapshot there is
# nothing to assert about one, which is the call site's condition and not this
# file's.
{
  pkgs,
  quarantine,
  # **One text and no instantiation** ([item 51](../docs/ledger/051-the-target-in-four-store-paths.md)).
  # The checkout, the ceiling and the declared templates are arguments now, so
  # this suite chooses its own rather than substituting a target's — which is
  # what makes the last three cases below reachable at all, and what keeps the
  # three call sites (a capsule, a host origin, this sandbox) one store path.
  # This is that store path, arriving here rather than being rebuilt.
  snapshot,
  # And the other end of the same interface, which is what step 4 made worth
  # pinning: `snapshotArgs` builds that command line off a loaded profile
  # (host/state-snapshot.nix), so the order in the fragment and the order in the
  # script are two readings of one fact — and a suite that only ever composed the
  # line by hand would agree with itself. `profileFragment` is the reader it
  # needs; both arrive from `host/programs.nix`, never re-rendered.
  snapshotArgs,
  profileFragment,
  inputs,
}: let
  # The fragment plus the smallest `main` that exercises it: load a document,
  # print the tail. `host/profile-cases.nix`'s arrangement, one file over.
  argv = pkgs.writeShellApplication {
    name = "capsule-snapshot-argv";
    runtimeInputs = inputs;
    text = ''
      ${profileFragment}
      ${snapshotArgs}
      profileLoad "$1"
      snapshotArgs "$2"
    '';
  };

  # The bound as a program, so the case suite runs the real fragment rather
  # than a description of it (host/quarantine.nix).
  token = pkgs.writeText "capsule-token-check" ''
    ${quarantine.checkToken ''"$1"'' "'unit $1'"}
  '';
in
  pkgs.runCommand "capsule-snapshot-cases" {nativeBuildInputs = [pkgs.git pkgs.jq];} ''
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

    # What a target used to bake into this text and now hands it: the
    # checkout, the ceiling, and the declared templates. Spelled here rather
    # than taken from `target.nix`, because a suite that borrowed the live
    # values would pass for the same reason a probe on the real /30 does
    # (NOTES item 38) — and because the three cases at the end need values no
    # target has.
    paths=('.doctrine/state/slice/{unit}' '.doctrine/slice/{unit}')
    max=67108864
    snap() { bash ${snapshot} "$1" "$2" "$3" src "$max" "''${paths[@]}"; }

    # ------------------------------------------- the command line, off a document
    #
    # The seam item 51 step 4 moved, and the one thing neither end pins on its
    # own: `snap` above composes this line by hand, and a collect composes it
    # from a profile. Two orders that must be one — and the failure if they are
    # not is the one this repo has already had, a collect that reports success
    # and brings back half a result (item 47).
    mkdir -p profiles
    jq -n --arg m "$max" --arg a "''${paths[0]}" --arg b "''${paths[1]}" \
      '{ schema: 1, name: "fixture", path: "/h/fixture", guestPath: "/vol/fixture",
         volumePath: "/vol", cachePaths: [], baseline: null, refresh: null,
         statePaths: [$a, $b], stateMaxBytes: ($m | tonumber),
         sizes: {vcpu: 1, mem: 1, volume: 1} }' > profiles/fixture.json
    mapfile -t fromDoc < <(CAPSULE_PROFILE_DIR=$PWD/profiles ${pkgs.lib.getExe argv} fixture src)
    ck "the tail is the checkout it was handed" src "''${fromDoc[0]}"
    ck "  then the ceiling" "$max" "''${fromDoc[1]}"
    ck "  then every declared template, in order" "''${paths[*]}" "''${fromDoc[*]:2}"
    ck "  and nothing else" 4 "''${#fromDoc[@]}"

    # ------------------------------------------------------- the token bound
    #
    # `.` and `..` are the cases the character class admits and the comment
    # always claimed it did not. Harmless while a token only ever landed at
    # the end of a ref; a path escape the moment one lands in the middle of a
    # path, which is what a unit token does.
    for good in 254 a.b-c_d 0 x; do
      rc=0; bash ${token} "$good" >/dev/null 2>&1 || rc=$?
      ck "token '$good' is a name" 0 "$rc"
    done
    for bad in "" . .. a/b "a b" 'a;b' '$x' '*'; do
      rc=0; bash ${token} "$bad" >/dev/null 2>&1 || rc=$?
      ck "token '$bad' is refused" 1 "$rc"
    done

    # ------------------------------------------------ a checkout of two units
    #
    # Shaped like the one the invariant was measured against: a runtime tier
    # the project ignores on purpose, authored content beside it, two units of
    # work in both, and an agent's uncommitted edit to one of them.
    mkdir src && cd src
    git init -q --initial-branch=work .
    printf '%s\n' '.doctrine/state/' > .gitignore
    mkdir -p .doctrine/slice/254 .doctrine/slice/253
    mkdir -p .doctrine/state/slice/254 .doctrine/state/slice/253
    echo authored-254 >.doctrine/slice/254/spec.md
    echo authored-253 >.doctrine/slice/253/spec.md
    echo code >src.txt
    git add -A && git commit -qm base
    echo "edited by the agent" >.doctrine/slice/254/spec.md
    echo phase-254 >.doctrine/state/slice/254/phase-01.md
    echo phase-253 >.doctrine/state/slice/253/phase-01.md
    echo scratch >notes.md
    # Tracked, committed, and edited since — outside every declared path, so
    # it can only ever travel as the diff. Which is the whole question a host
    # origin asks of `dirty.diff` (NOTES item 42).
    echo "an edit outside every declared path" >>src.txt
    cd ..

    # Into a file rather than down a pipe: `ckt` takes a command, and a
    # pipeline reaching it would grep `ckt`'s own output instead of git's —
    # which passes, silently, for the wrong reason.
    entries() { git -C src ls-tree -r --name-only "$1" >list; }

    # ------------------------------------------------------- no unit, no scope
    #
    # The guest's own guard, and the reason it is not left to the host's: a
    # missing token substitutes as the empty string, which collapses every
    # scoped path onto its parent — the unscoped collect wearing the scoped
    # one's name.
    rc=0; snap implementation "" all >out 2>err || rc=$?
    ck "refuses a scoped policy with no unit" 1 "$rc"
    ckt "  and says the two ends disagree" grep -q "scoped to one unit" err
    ckt "  and wrote no ref" \
      test -z "$(git -C src for-each-ref 'refs/capsule/state/')"

    # ----------------------------------------------------------- scoped, green
    rc=0; snap implementation 254 all >out 2>err || rc=$?
    ck "takes a snapshot scoped to one unit" 0 "$rc"
    oid=$(cut -f1 out)
    ckt "  and reported a commit" test "$oid" != -

    entries "$oid"
    ckt "  the unit's runtime tier is in it" \
      grep -qx '.doctrine/state/slice/254/phase-01.md' list
    ckt "  the unit's authored tree is in it" \
      grep -qx '.doctrine/slice/254/spec.md' list
    # The invariant, stated as the thing that used to be false: another unit's
    # state in this exhibit is a second, older answer to the question the
    # exhibit exists to settle, and nothing in the tree marks which is which.
    ckt "  and no other unit's state is" \
      test -z "$(grep 253 list || true)"

    # Generic, so unscoped: "the agent has not committed this" is nobody's
    # project's concept and there is no template to put a hole in.
    ckt "  untracked-but-not-ignored still travels" grep -qx 'notes.md' list
    ckt "  and the tracked edit travels as the diff" \
      grep -qx '.capsule/dirty.diff' list
    # A state tree is worktree content, which is what makes `code-oid` a
    # control rather than a note (NOTES item 35).
    ckt "  the authored file carries the agent's uncommitted edit" \
      test "$(git -C src cat-file -p "$oid:.doctrine/slice/254/spec.md")" = "edited by the agent"
    # What the tree cannot say. An exhibit whose scope is not on the record is
    # one nobody can check the scope of.
    git -C src cat-file commit "$oid" >msg
    ckt "  the commit message names the unit" grep -qx 'unit: 254' msg
    ckt "  the agent's real index was not touched" \
      test -z "$(git -C src diff --cached --name-only)"

    # ------------------------------------------- a unit this checkout never had
    #
    # Not a refusal: a target says what its state *is*, not what any one run
    # produced, and that has to keep holding once the paths are scoped.
    rc=0; snap implementation 999 all >out 2>err || rc=$?
    ck "a unit with no state is a skip, not a failure" 0 "$rc"
    ckt "  and names the paths it skipped" grep -q 'slice/999 in this checkout' err
    oid=$(cut -f1 out)
    entries "$oid"
    ckt "  nothing of any unit is in it" \
      test -z "$(grep -E '25[34]|999' list || true)"
    ckt "  and the uncommitted work still is" grep -qx 'notes.md' list

    # ------------------------------------------------ the other origin
    #
    # The same text at a checkout nobody confined (NOTES item 42). What
    # changes is not the tree-builder but the premise under one sentence of
    # item 32: untracked-but-not-ignored is *the agent's* work in a guest,
    # where one agent works on one thing, and is whatever is lying around in
    # a human's checkout. So the sweep is an argument, and it has no default
    # because the value one would fall back to is the failure.
    rc=0; snap implementation 254 >out 2>err || rc=$?
    ck "refuses an origin it was not told" 1 "$rc"
    ckt "  and names both of them" grep -q "'all'" err
    rc=0; snap implementation 254 sideways >out 2>err || rc=$?
    ck "refuses an origin that is neither" 1 "$rc"

    rc=0; snap implementation 254 declared >out 2>err || rc=$?
    ck "takes a host origin scoped to the declared paths" 0 "$rc"
    oid=$(cut -f1 out)
    entries "$oid"
    ckt "  the unit's runtime tier is still in it" \
      grep -qx '.doctrine/state/slice/254/phase-01.md' list
    ckt "  the unit's authored tree is still in it" \
      grep -qx '.doctrine/slice/254/spec.md' list
    # The sentence that goes silently false at a host origin: this file is a
    # scratch note on somebody's desk and not an agent's work in progress.
    ckt "  and the desk around it is not" \
      test -z "$(grep -x 'notes.md' list || true)"
    ckt "  nor another unit's state" test -z "$(grep 253 list || true)"
    # The same leak by the other route: `dirty.diff` is a whole-repo patch,
    # which from a capsule is one agent's work and from here is everything
    # this host happens to have open.
    git -C src cat-file -p "$oid:.capsule/dirty.diff" >diff
    ckt "  the diff carries the declared path's edit" \
      grep -q 'slice/254/spec.md' diff
    ckt "  and nothing outside it" test -z "$(grep 'src.txt' diff || true)"
    git -C src cat-file commit "$oid" >msg
    ckt "  and the dirty count is the scoped one" grep -qx 'dirty: 1' msg

    # Same unit, same checkout, two origins, and the pair is the point: a
    # capsule takes the desk along with it and a host origin has nothing to
    # take at all.
    rc=0; snap implementation 999 declared >out 2>err || rc=$?
    ck "a host origin with no declared path present takes nothing" 0 "$rc"
    ckt "  and reports no commit" test "$(cut -f1 out)" = -
    ckt "  and says why" grep -q 'takes nothing outside them' err

    # ------------------------------------------- what used to be in the text
    #
    # Three values a target used to interpolate, each pinned by a case that is
    # only reachable once it arrives as an argument
    # ([item 51](../docs/ledger/051-the-target-in-four-store-paths.md)). None of
    # them can be reached by choosing a different *instantiation*, which is why
    # they are here rather than in a second one: the whole claim is that there
    # is no second one.
    #
    # The checkout. A second repository, snapshotted by the same store path in
    # the same run — which is one store path serving two projects, in the
    # smallest form the claim has.
    mkdir other && cd other
    git init -q --initial-branch=work .
    mkdir -p .doctrine/slice/7
    echo elsewhere >.doctrine/slice/7/spec.md
    git add -A && git commit -qm base
    cd ..
    rc=0; bash ${snapshot} implementation 7 all other "$max" "''${paths[@]}" >out 2>err || rc=$?
    ck "the checkout is an argument, not the text" 0 "$rc"
    oid=$(cut -f1 out)
    # Guarded, so a text that ignored the argument fails *this* case by name
    # rather than killing the run at git with `not a tree object` — which is
    # what the mutation that proves this suite does, and a suite whose red is
    # a hard stop names the wrong round (NOTES item 37).
    git -C other ls-tree -r --name-only "$oid" >list 2>/dev/null || : >list
    ckt "  and the snapshot is of that one" grep -qx '.doctrine/slice/7/spec.md' list
    ckt "  and nothing of the first is in it" \
      test -z "$(grep -E '25[34]' list || true)"

    # The ceiling. A byte count no real target would set, which is the point:
    # the branch is chosen by the argument and not by the build.
    rc=0; bash ${snapshot} implementation 254 all src 1 "''${paths[@]}" >out 2>err || rc=$?
    ck "the ceiling is an argument" 0 "$rc"
    ckt "  and a snapshot over it is skipped" test "$(cut -f1 out)" = -
    ckt "  naming the bound it tripped" grep -q 'over the 1 ceiling' err
    ckt "  and the code half is still collectable" test "$(cut -f2 out)" -gt 1

    # The declared set — and with it `needsUnit`, which was an *eval-time*
    # predicate over a build-time list. A target whose state is not per-unit
    # writes no hole and must not be refused for having no unit; that used to
    # be decided by which flake this host built.
    rc=0; bash ${snapshot} implementation "" all src "$max" .doctrine/slice >out 2>err || rc=$?
    ck "an unscoped template needs no unit" 0 "$rc"
    oid=$(cut -f1 out)
    git -C src ls-tree -r --name-only "$oid" >list 2>/dev/null || : >list
    ckt "  and takes every unit under it" \
      test "$(grep -c 'doctrine/slice/25[34]/spec.md' list)" = 2
    rc=0; snap implementation "" all >/dev/null 2>&1 || rc=$?
    ck "  while a scoped one still refuses" 1 "$rc"

    # A template no target here declares, and the reason the two arg forms in
    # `host/state-snapshot.nix` are two: a value with a space in it is carried
    # by argv and destroyed by any hop that re-parses it. This pins the local
    # form. The ssh hop's second escaping has no sandbox that can reach it —
    # there is no guest here — and is the call site's until step 4 moves it.
    mkdir -p 'src/.doctrine/two words'
    echo spaced >'src/.doctrine/two words/note.md'
    rc=0; bash ${snapshot} implementation "" all src "$max" '.doctrine/two words' >out 2>err || rc=$?
    ck "a declared path with a space survives argv" 0 "$rc"
    oid=$(cut -f1 out)
    git -C src ls-tree -r --name-only "$oid" >list 2>/dev/null || : >list
    ckt "  and its file is in the tree" grep -q 'two words/note.md' list

    [ "$fail" = 0 ] || exit 1
    cp "$log" $out
    cat $out
  ''
