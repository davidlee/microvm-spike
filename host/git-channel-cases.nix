# The two programs a live slot uses, at the one seam item 51 step 4 moved:
# **which target's values a run is about**.
#
# The third kind of check (CLAUDE.md), and the ninth suite. The other eight pin
# the *guest* halves — the scripts step 2 gave a command line — and none of them
# can see the half that builds that command line, which is exactly the half this
# step rewrote. `capsule-provision` and `capsule-collect` are what a slot holding
# real work runs, so a refactor that reports success while collecting nothing is
# the failure this repo has already had once
# ([item 47](../docs/ledger/047-a-script-on-stdin-and-the-command-that-eats-it.md)),
# and the cheapest guard against the next one is a build that fails.
#
# **What this suite can reach, and what it deliberately cannot.** Both programs
# have `pkgs.openssh` in their `runtimeInputs`, so `writeShellApplication` puts it
# on `PATH` ahead of anything a sandbox could stub (CLAUDE.md) — there is no
# faking a guest here. What that leaves is everything *upstream* of the door, and
# it is the whole of what step 4 changed: which document a program resolves,
# what it refuses without one, and which values out of that document reach the
# host checkout, the guest URL and the ceiling. Every case below is a refusal or
# a message, and each names a value that used to be in the program's text.
#
# **Two things are borrowed and both are the subject rather than a fixture.** The
# slot name comes from the caller's own declaration, because the shipped program
# has that list baked in and a suite that invented a name would be testing a
# program this host does not have; and the guest address is `net.nix`'s, for the
# same reason — it is in the text under test. What is *not* borrowed is the
# target: every profile here is a fixture, since a document that agreed with
# doctrine's would go on passing while the declaration moved onto it
# ([item 38](../docs/ledger/038-a-probe-that-became-a-borrower.md)).
{
  pkgs,
  lib,
  # The store paths this host ships (host/git-channel.nix), never a re-render.
  provision,
  collect,
  # A slot this host declares. The transport refuses a name that is not one, and
  # that refusal is not what any case here is about.
  slot,
}:
pkgs.runCommand "capsule-git-channel-cases" {
  nativeBuildInputs = [pkgs.jq pkgs.git];
} ''
  export HOME=$PWD
  git config --global user.email c@example.invalid
  git config --global user.name cases
  git config --global init.defaultBranch main

  fail=0
  log=$PWD/log
  : >"$log"
  ck() {
    if [ "$2" = "$3" ]; then echo "ok   $1" >>"$log"
    else echo "FAIL $1: got '$3', wanted '$2'" >&2; sed 's/^/    /' out >&2; fail=1; fi
  }
  saw() {
    if grep -qF -- "$1" out; then echo "ok   ...and says '$1'" >>"$log"
    else echo "FAIL missing reason '$1' in:" >&2; sed 's/^/    /' out >&2; fail=1; fi
  }
  never() {
    if grep -qF -- "$1" out; then echo "FAIL said '$1' and should not have:" >&2; sed 's/^/    /' out >&2; fail=1
    else echo "ok   ...and never says '$1'" >>"$log"; fi
  }

  # A real repository, so a provision gets *past* reading the host checkout and
  # the next thing it names is the guest URL. Without one every case would stop
  # at the same refusal and none of them would discriminate (item 37).
  mkdir -p src
  git -C src init -q
  git -C src commit -q --allow-empty -m first
  head=$(git -C src rev-parse HEAD)

  mkdir -p profiles
  export CAPSULE_PROFILE_DIR=$PWD/profiles
  write() { printf '%s' "$2" | jq -S . > "profiles/$1.json"; }

  # Two targets, one host, and every value below is one a program used to carry
  # in its text. `alpha` has this sandbox's repository as its checkout; `beta`
  # names a directory that is not one, which is what makes the *pair* of
  # refusals below distinguishable.
  write alpha "{ \"schema\": 1, \"name\": \"alpha\", \"path\": \"$PWD/src\",
    \"guestPath\": \"/vol/alpha\", \"volumePath\": \"/vol\",
    \"cachePaths\": [], \"baseline\": null, \"refresh\": null,
    \"statePaths\": [\".a/{unit}\"], \"stateMaxBytes\": 4096,
    \"sizes\": {\"vcpu\": 1, \"mem\": 1, \"volume\": 1} }"

  write beta '{ "schema": 1, "name": "beta", "path": "/nowhere/beta",
    "guestPath": "/other/beta", "volumePath": "/other",
    "cachePaths": [], "baseline": null, "refresh": null,
    "statePaths": [".b/{unit}"], "stateMaxBytes": 4096,
    "sizes": {"vcpu": 1, "mem": 1, "volume": 1} }'

  # A third, and it is the one step 6 is about: a target that declares no
  # out-of-band state at all. Its checkout is this sandbox's, so the only thing
  # separating it from `alpha` is the field under test.
  write gamma "{ \"schema\": 1, \"name\": \"gamma\", \"path\": \"$PWD/src\",
    \"guestPath\": \"/vol/gamma\", \"volumePath\": \"/vol\",
    \"cachePaths\": [], \"baseline\": null, \"refresh\": null,
    \"statePaths\": [], \"stateMaxBytes\": 0,
    \"sizes\": {\"vcpu\": 1, \"mem\": 1, \"volume\": 1} }"

  prov=${lib.getExe provision}
  coll=${lib.getExe collect}
  slot=${lib.escapeShellArg slot}
  run() { rc=0; "$@" >out 2>&1 || rc=$?; }

  # ------------------------------------------------------------- no profile at all
  #
  # Decision 4's whole claim: a program is handed the target it is about and
  # there is nothing to fall back to. Asserted on both, because the two of them
  # are what a slot holding live work runs.
  run "$prov" --capsule "$slot" "$head"
  ck "a provision with no profile refuses" 1 "$rc"
  saw "which target?"
  # Before the door and before the checkout: an argument error that has already
  # pushed is an argument error the program made worse.
  never "$PWD/src"

  run "$coll" --capsule "$slot" --policy build --unit 1
  ck "and so does a collect" 1 "$rc"
  saw "which target?"
  # The order is the claim, not an accident: the profile is resolved where the
  # transport is, so it is refused ahead of every flag the program parses
  # itself. A collect that asked for a policy first would be one that can be
  # made to open a quarantine for a target nobody named.
  never "no policy"

  run "$prov" --capsule "$slot" --profile nosuch "$head"
  ck "a profile this host has not rendered refuses" 1 "$rc"
  saw "no profile named 'nosuch'"

  # ------------------------------------------------- the host checkout, from the document
  #
  # `path` used to be `target.path` interpolated into the program's text
  # (host/git-channel.nix's `src`). These two runs differ in one argument and
  # name two different directories, which is the interpolation being gone.
  run "$prov" --capsule "$slot" --profile alpha
  ck "a provision with no ref refuses" 1 "$rc"
  saw "any commit-ish in $PWD/src"
  run "$prov" --capsule "$slot" --profile beta
  ck "and names the other target's checkout under the other name" 1 "$rc"
  saw "any commit-ish in /nowhere/beta"

  run "$prov" --capsule "$slot" --profile beta "$head"
  ck "a ref that is not in that checkout refuses" 1 "$rc"
  saw "/nowhere/beta has no commit at"

  # `CAPSULE_REPO` is the override this whole item generalises from
  # (host/git-channel.nix), and it still wins: the lookup replaced the *baked
  # default*, not the environment.
  run env CAPSULE_REPO=/nowhere/else "$prov" --capsule "$slot" --profile alpha
  ck "CAPSULE_REPO still beats the document" 1 "$rc"
  saw "any commit-ish in /nowhere/else"

  # -------------------------------------------------------- the guest URL, likewise
  #
  # The last thing a provision names before it needs a guest, and the value the
  # inventory listed first: `guestPath` reached six store paths. There is no
  # guest here, so what is asserted is *which* one it tried.
  run "$prov" --capsule "$slot" --profile alpha "$head"
  ck "a provision at a real ref gets as far as the guest" 1 "$rc"
  saw "cannot reach ssh://agent@"
  saw "/vol/alpha"
  never "/other/beta"

  # -------------------------------------------- the unit scope, per document
  #
  # `stateNeedsUnit` was an eval-time predicate over *this host's* target, so
  # every profile got doctrine's answer whatever it declared itself: a document
  # with no hole in its state paths was refused for being scoped to a unit it
  # does not have, and a `--unit` against one was accepted and scoped nothing
  # (item 51 step 6). Both runs exit 1 either way — they die at the door a
  # moment later — so the **reason** is the whole assertion here, which is the
  # lesson step 4 paid for.
  run "$coll" --capsule "$slot" --profile alpha --policy build
  ck "a collect on a holed document with no unit refuses" 1 "$rc"
  saw "scopes its state paths to"
  # Naming the document and not "this target", which is the only thing that
  # tells a human *which* of two a refusal is about.
  saw "profile 'alpha'"
  # Before the door: a scope error that has already pushed a script into a
  # capsule is one this program made worse.
  never "the state snapshot failed"

  run "$coll" --capsule "$slot" --profile gamma --policy build --unit u
  ck "and a --unit against a document with no hole refuses" 1 "$rc"
  saw "with a place for one"
  saw "profile 'gamma'"
  never "scopes its state paths to"

  # The degrade, per document rather than per build: a target that declares no
  # state gets the code-only collect this program used to be, and it is *this
  # run* that decides so rather than the flake the host was built from.
  run "$coll" --capsule "$slot" --profile gamma --policy build
  ck "a document with no state paths collects code only" 1 "$rc"
  never "scopes its state paths to"
  never "the state snapshot failed"
  saw "capsule-collect: policy build"

  # The other side of the same fork, so neither answer is a constant.
  run "$coll" --capsule "$slot" --profile alpha --policy build --unit u
  ck "and a holed one with a unit takes the state half" 1 "$rc"
  saw "the state snapshot failed"

  [ "$fail" = 0 ] || exit 1
  cp "$log" $out
  cat $out
''
