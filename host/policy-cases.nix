# `capsule`'s two *filled-in* flags, run against a declaration that is not this
# host's: the policy a slot resolves to, and — since item 51 step 4 — the profile
# it does. Both are the same shape, which is why they are one suite: a program
# refuses without the flag, this front end reads host state and fills it, and an
# explicit one wins.
#
# The third kind of check (CLAUDE.md), and its fourth instance. The branches
# worth pinning are refusals a live host reaches expensively or destructively
# — a slot declaring an empty set, an assigner naming a policy outside its
# slot's set, and a re-point that cannot be written — and the one success that
# matters is that the record and the allowlist link move *together*. Reaching
# any of them here would mean editing `capsules.nix`, rebuilding the host, and
# writing the live record of a slot that is actually assigned.
#
# Two seams, both already the ones the rule asks for: `capsules` is substituted
# the way `guard-cases.nix` substitutes it, and `moduleState` — the one thing
# tying this program to this host — is `host/cli.nix`'s argument, so the record
# lands in the sandbox. Every real call site takes its default, so the two
# shipped copies are still one store path.
#
# The one suite that re-renders what it pins, and deliberately: a fixture is the
# subject. The four values below are the shipped ones, threaded from the call
# site so this render differs from the shipped front end in nothing else.
{
  pkgs,
  lib,
  net,
  capsules,
  policies,
  guestSsh,
  observe,
  observeFragment,
  programVerbs,
  profileVerbs,
  stateRefPrefix,
}: let
  # Three slots, none of them this host's, each one a shape `capsules.nix`
  # itself would refuse: a set of one, a slot with no set at all, and a slot
  # whose declared default is not the first thing an assigner would pick.
  # That last is what makes "the record beats the declaration" assertable
  # rather than indistinguishable.
  fixture =
    capsules
    // {
      instances = capsules.instancesOf {
        one = {
          index = 0;
          policy = "build";
          policies = ["build"];
        };
        none = {index = 1;};
        both = {
          index = 2;
          policy = "sealed";
          policies = ["build" "sealed"];
        };
      };
    };
  cli = import ./cli.nix {
    inherit pkgs lib net policies guestSsh;
    inherit observe observeFragment programVerbs profileVerbs stateRefPrefix;
    capsules = fixture;
    moduleState = ''"$CASE_STATE"'';
    # NOTES item 41's branch and its failure, made reachable from a sandbox
    # that has neither systemd nor root — which is exactly why the front end
    # takes this as an argument: `pkgs.systemd` is in its `runtimeInputs`, so
    # a stub `systemctl` on PATH cannot shadow the real one.
    #
    # Two variables rather than two builds, so all three shapes — proxy down,
    # proxy restarted, proxy refusing to restart — come off one store path.
    # The restart *logs* as well as returning, because "did not restart" and
    # "restarted and the message was wrong" are different failures.
    proxyControl = ''
      proxyActive() { [ -n "''${CASE_PROXY_UP:-}" ]; }
      proxyRestart() {
        echo "restarted $1" >> "$CASE_PROXY_LOG"
        [ -z "''${CASE_PROXY_FAIL:-}" ]
      }
    '';
    # The guest, and the same argument `proxyControl` makes one field up:
    # `pkgs.openssh` is in the front end's `runtimeInputs`, so nothing in a
    # sandbox can stub `ssh` (CLAUDE.md) — and every branch item 53 is about
    # sits *downstream* of one round trip. What a live host would have to do to
    # reach them is drive two agents into disagreement and then force over the
    # second, which is the definition of a branch a suite is for.
    #
    # A file per slot rather than one variable, because a handoff asks two
    # capsules the same question and "the guest answered" and "the *source*
    # answered" are different facts. Absent means silent, which is what the
    # unprovisioned and the stopped both look like from here.
    #
    # What this does **not** pin is the ssh argv on the other side of these two
    # — the same boundary item 41's seam leaves around its sudo rule.
    guestControl = ''
      guestHead() { cat "$CASE_STATE/head/$1" 2> /dev/null; }
      guestDropState() {
        echo "$*" >> "$CASE_GUEST_LOG"
        [ -z "''${CASE_DROP_FAIL:-}" ] || return 1
        shift
        printf '${stateRefPrefix}/%s\n' "$@"
      }
    '';
  };
  buildFile = policies.policies.build.allowlist;
  sealedFile = policies.policies.sealed.allowlist;
in
  pkgs.runCommand "capsule-policy-cases" {nativeBuildInputs = [pkgs.jq pkgs.git];} ''
    export CASE_STATE=$PWD/state
    mkdir -p "$CASE_STATE" stub policies allow profiles
    touch policies/${buildFile} policies/${sealedFile}

    # The documents this host declares, and none of them is doctrine's: a
    # fixture that borrowed live values would go on passing while the
    # declaration moved onto it (item 38). One to start with, because the
    # interesting transition is a host acquiring a second one.
    export CAPSULE_PROFILE_DIR=$PWD/profiles
    # `statePaths` is the second argument because it is the one field step 6 is
    # about: `[]` is a target with no out-of-band state, and a holed template is
    # one whose exhibit is scoped to a unit of work (item 32). Everything else
    # is the same document, so a pair of runs differs in that field alone.
    writeProfile() {
      jq -n --arg n "$1" --argjson sp "''${2:-[]}" --arg bl "''${3:-}" \
        '{ schema: 1, name: $n,
        path: ("/h/" + $n), guestPath: ("/vol/" + $n), volumePath: "/vol",
        cachePaths: [], baseline: (if $bl == "" then null else $bl end),
        refresh: null, statePaths: $sp,
        stateMaxBytes: (if ($sp | length) > 0 then 4096 else 0 end),
        sizes: {vcpu: 1, mem: 1, volume: 1} }' > "profiles/$1.json"
    }
    writeProfile solo

    # What `work` execs once the front end has filled the flags in.
    # `capsule-collect` is deliberately *not* one of the front end's
    # `runtimeInputs` — it picks between two copies of it on PATH — so a stub
    # on PATH is what it finds, and this is the one place a case can watch
    # what the front end decided rather than what it said.
    for v in collect provision inject baseline; do
      cat > "stub/capsule-$v" <<EOF
    #!/bin/sh
    echo "$v argv: \$*"
    echo "\$*" > "\$PWD/out.argv"
    EOF
      chmod +x "stub/capsule-$v"
    done
    export PATH=$PWD/stub:$PATH

    capsule=${lib.getExe cli}
    log=$PWD/log
    : > "$log"
    fail=0
    run() {
      rc=0
      # The stub's record of what it was handed, cleared per run: a stale one
      # would let "nothing reached the program" pass on the previous call's
      # argv, which is a round that never discriminates (item 37).
      rm -f out.argv
      "$capsule" "$@" > out 2>&1 || rc=$?
    }
    ck() {
      if [ "$2" = "$3" ]; then
        echo "ok   $1" >> "$log"
      else
        echo "FAIL $1: exit $3, wanted $2" >&2
        sed 's/^/    /' out >&2
        fail=1
      fi
    }
    ckt() {
      if "''${@:2}"; then
        echo "ok   $1" >> "$log"
      else
        echo "FAIL $1" >&2
        sed 's/^/    /' out >&2
        fail=1
      fi
    }
    saw() { grep -qF -- "$1" out; }
    # Not `grep -qv`, which asks whether *some line* lacks the text and is
    # therefore true of almost any output — a round that never discriminates
    # (item 37).
    unsaw() { ! grep -qF -- "$1" out; }
    gen() { jq -r .generation "$CASE_STATE/slot/$1/assignment.json"; }
    # Which document a slot resolves to, written the way a provision would if
    # there were a guest to provision against. Six rounds below turn on it and
    # the write is the same two lines every time.
    assign() {
      jq --arg p "$2" '.profile = $p' "$CASE_STATE/slot/$1/assignment.json" > tmp.json
      mv tmp.json "$CASE_STATE/slot/$1/assignment.json"
    }
    # And its inverse, for the one round that needs a slot with a record and no
    # target: every slot here has been provisioned by the time the last section
    # runs, and `.profile` is what a provision writes.
    unassign() {
      jq 'del(.profile)' "$CASE_STATE/slot/$1/assignment.json" > tmp.json
      mv tmp.json "$CASE_STATE/slot/$1/assignment.json"
    }

    # ------------------------------------- what an unassigned slot resolves to
    #
    # The operator's declaration, in both readers. `sealed` rather than the
    # first name in the vocabulary, so a reader that returned a constant would
    # be caught.
    run both policy
    ck "an unassigned slot reads its declared policy" 0 "$rc"
    ckt "  which is the operator's, not the vocabulary's first" saw sealed
    run both collect
    ck "and a collect on one is filled from the same declaration" 0 "$rc"
    ckt "  as --policy, before the program sees it" \
      saw "collect argv: --capsule both --profile solo --policy sealed"

    # ------------------------------------------------------- the two refusals
    #
    # A declaration nobody can satisfy is not the same fault as an argument
    # outside a set, and a refusal for the wrong reason is a different program
    # passing — so each names its own half.
    run none policy build
    ck "a slot with no declared set refuses" 1 "$rc"
    ckt "  and names the declaration rather than the argument" \
      saw "declares no policies"
    run one policy sealed
    ck "a policy outside the slot's set refuses" 1 "$rc"
    ckt "  and names the argument rather than the declaration" \
      saw "may not take policy 'sealed'"
    ckt "  pointing at who may widen it" saw "capsules.nix"
    ckt "  and nothing was written" test ! -e "$CASE_STATE/slot/one/assignment.json"

    # The perimeter half is the module path's, and this copy has no policy
    # directory yet — which is also the proof that the selection above was
    # accepted, since this refusal is the next one after it.
    run one policy build
    ck "a selection with nowhere to point refuses" 1 "$rc"
    ckt "  naming the copy that can" saw "no policy directory"

    # Half of the pair is not the pair. A copy holding the policy directory
    # and not the directory the links live in would write a record and put
    # the link nowhere, which is the disagreement the lock exists to prevent
    # arriving by a different door (NOTES item 39).
    export CAPSULE_POLICY_DIR=$PWD/policies
    run one policy build
    ck "and so does a copy with only half the pair" 1 "$rc"
    ckt "  by the same refusal, since it means the same thing" \
      saw "no policy directory"
    ckt "  and nothing was written" test ! -e "$CASE_STATE/slot/one/assignment.json"

    export CAPSULE_ALLOWLIST_DIR=$PWD/allow

    # ------------------------------------------ the record and the link, once
    run one policy build
    ck "a declared selection is taken" 0 "$rc"
    ckt "  the record says so" \
      test "$(jq -r .policy "$CASE_STATE/slot/one/assignment.json")" = build
    ckt "  the link points at that policy's file" \
      test "$(readlink "$CAPSULE_ALLOWLIST_DIR/one")" = "$CAPSULE_POLICY_DIR/${buildFile}"
    # The point of item 39, asserted rather than commented: the directory a
    # proxy reads is not the directory the record is in. A link that came back
    # to sit beside the record would pass every other case in this file.
    ckt "  and it is not in the record's directory" \
      test ! -e "$CASE_STATE/slot/one/allowlist"
    ckt "  and the generation moved once" test "$(gen one)" = 1

    # A record that disagrees with the declaration is the whole point of there
    # being a record: an assigner selected, and that is what the slot runs.
    run both policy build
    ck "a slot may be moved off its declared default" 0 "$rc"
    ckt "  the link follows the record" \
      test "$(readlink "$CAPSULE_ALLOWLIST_DIR/both")" = "$CAPSULE_POLICY_DIR/${buildFile}"
    run both policy
    ck "and the record is what it reads back" 0 "$rc"
    ckt "  not the declaration" saw build
    run both collect
    ck "a collect is filled from the record once there is one" 0 "$rc"
    ckt "  and not from the declaration" \
      saw "collect argv: --capsule both --profile solo --policy build"
    run both collect --policy sealed
    ck "an explicit --policy wins" 0 "$rc"
    ckt "  and is not doubled" \
      saw "collect argv: --capsule both --profile solo --policy sealed"

    # ------------------------------------------- the proxy, and NOTES item 41
    #
    # The selection is only true of the wire once that slot's proxy has been
    # restarted, and until today no case could reach the branch that does it —
    # it needs a proxy that is up, and a sandbox has no systemd. So this is a
    # branch that had never been taken anywhere, which is the class item 41
    # belongs to.
    export CASE_PROXY_LOG=$PWD/proxy.log
    : > "$CASE_PROXY_LOG"

    # `both` is on `build` at generation 1 from the runs above.
    run both policy sealed
    ck "a selection with the proxy down is taken" 0 "$rc"
    ckt "  and says it will be rendered at the next start" \
      saw "will render sealed when it starts"
    ckt "  with nothing restarted" test ! -s "$CASE_PROXY_LOG"

    export CASE_PROXY_UP=1
    run both policy build
    ck "a selection with the proxy up restarts it" 0 "$rc"
    ckt "  and says egress is down for the length of it" \
      saw "restarting capsule-proxy-both"
    ckt "  and the proxy really was restarted" \
      grep -qF "restarted capsule-proxy-both" "$CASE_PROXY_LOG"

    # The item itself. A restart that fails must leave *nothing* moved — the
    # hook's contract (host/record.nix) — because the alternative is a record
    # and a link that read `sealed` over a proxy still serving `build`, which
    # is fail-open in the one direction a policy verb exists for.
    export CASE_PROXY_FAIL=1
    wasLink=$(readlink "$CAPSULE_ALLOWLIST_DIR/both")
    wasGen=$(gen both)
    run both policy sealed
    ck "a proxy that will not restart undoes the selection" 1 "$rc"
    ckt "  saying the selection was undone rather than half-done" \
      saw "would not restart, so the selection was undone"
    ckt "  and which policy still holds" saw "still holds build"
    ckt "  the link went back to where it was" \
      test "$(readlink "$CAPSULE_ALLOWLIST_DIR/both")" = "$wasLink"
    ckt "  the record did not move" test "$(gen both)" = "$wasGen"
    ckt "  and still names the old policy" \
      test "$(jq -r .policy "$CASE_STATE/slot/both/assignment.json")" = build
    unset CASE_PROXY_UP CASE_PROXY_FAIL

    # ------------------------------------------------- the ordering, asserted
    #
    # The link is written inside the record's lock and *before* the document
    # (host/record.nix's `recordAlso`), so the only failure either can have
    # leaves both as they were. A directory where the link should be is how a
    # sandbox reaches that; on a live host it is a disk or a permission.
    rm "$CAPSULE_ALLOWLIST_DIR/one"
    mkdir "$CAPSULE_ALLOWLIST_DIR/one"
    touch "$CAPSULE_ALLOWLIST_DIR/one/occupied"
    # `build` again rather than another name, because `one` declares a set of
    # one: this has to fail at the link and not at the selection, which is
    # what the run before it already proved is checked first.
    run one policy build
    ck "a link that cannot be re-pointed refuses" 1 "$rc"
    ckt "  and says which policy still holds" saw "still holds build"
    ckt "  the record did not move" test "$(gen one)" = 1
    ckt "  and still names the old policy" \
      test "$(jq -r .policy "$CASE_STATE/slot/one/assignment.json")" = build

    # -------------------------------------- which target, and item 51 decision 4
    #
    # The same shape as the policy above and a different authority: a program
    # refuses without a target, and *which* target a slot means is host state, so
    # this front end is where it is answered. The three sources are asserted in
    # the order they win.
    run both collect --profile other
    ck "an explicit --profile is passed through" 0 "$rc"
    # Where the human put it, untouched: this front end fills a flag in and
    # never reorders one somebody typed.
    ckt "  and is not doubled either" \
      saw "collect argv: --capsule both --policy build --profile other"

    # ----------------------------------- what a fetch says about each half
    #
    # A quarantine holds two ref namespaces and they are two different questions
    # (host/quarantine.nix). A slot's second assignment diverges from its first
    # in the code half, while the state half **fast-forwards across the
    # reassignment** — the guest parents each snapshot on the ref on its own
    # volume, which a provision does not touch (NOTES item 50, measured there and
    # met again by hand since). So one refspec is refused and the other is taken,
    # and the repository ends holding one assignment's code beside another's
    # state under two names that say they belong together.
    #
    # Reaching that on a host costs two assignments to one slot and a capsule to
    # fill them, which is what makes it this suite's: the fetch is git's, the
    # *reporting* is the front end's, and only the second is what this pins.
    export GIT_AUTHOR_NAME=case GIT_AUTHOR_EMAIL=case@example
    export GIT_COMMITTER_NAME=case GIT_COMMITTER_EMAIL=case@example
    repo=$PWD/repo
    export CAPSULE_REPO=$repo
    git init -q "$repo"
    g() { git -C "$repo" "$@"; }
    tree=$(g mktree < /dev/null)
    base=$(g commit-tree "$tree" -m base)
    first=$(g commit-tree "$tree" -p "$base" -m 'first assignment')
    second=$(g commit-tree "$tree" -p "$base" -m 'second assignment')
    st1=$(g commit-tree "$tree" -m 'state, first')
    st2=$(g commit-tree "$tree" -p "$st1" -m 'state, second')

    # `both` sorts before `one`, which is what makes the sweep below assert
    # anything: with the refusing slot last, a loop that stops at the first
    # failure passes the same round.
    git init -q --bare "$CASE_STATE/collect/both.git"
    g update-ref refs/capsule/both/heads/work "$first"
    g update-ref refs/capsule/both/state/implementation "$st1"
    g push -q "$CASE_STATE/collect/both.git" \
      "$second:refs/capsule/both/heads/work" \
      "$st2:refs/capsule/both/state/implementation"

    run both fetch
    ck "a fetch whose halves disagree refuses" 1 "$rc"
    # Each half named on its own, because "it failed" is the answer that left
    # the two refs disagreeing in the first place.
    ckt "  naming the half that landed" saw "state: landed"
    ckt "  and the half that did not" saw "code: refused"
    ckt "  and the state half really did move" \
      test "$(g rev-parse refs/capsule/both/state/implementation)" = "$st2"
    ckt "  while the code half stayed where it was" \
      test "$(g rev-parse refs/capsule/both/heads/work)" = "$first"
    # The remedy is item 50's key, named for the generation this slot is on, so
    # the message teaches the archive rather than the `--force` that loses it.
    ckt "  pointing at the archive that unblocks it" saw "refs/capsule/both/gen/"

    git init -q --bare "$CASE_STATE/collect/one.git"
    g push -q "$CASE_STATE/collect/one.git" \
      "$second:refs/capsule/one/heads/work" \
      "$st2:refs/capsule/one/state/implementation"
    run one fetch
    ck "a fetch whose halves agree takes both" 0 "$rc"
    ckt "  saying so for the code half" saw "code: landed"
    ckt "  and for the state half" saw "state: landed"

    # A sweep is N answers on one screen (`aggregable`, host/cli.nix), so a slot
    # that cannot fetch must not decide another's outcome — `set -e` on a git
    # that exits 1 used to end the loop wherever it had got to.
    g update-ref -d refs/capsule/one/heads/work
    g update-ref -d refs/capsule/one/state/implementation
    run all fetch
    ck "a sweep past a slot that refuses still fails" 1 "$rc"
    ckt "  having fetched the slot that could" \
      test "$(g rev-parse refs/capsule/one/heads/work)" = "$second"
    ckt "  and named the one that could not" saw "both: code: refused"
    unset CAPSULE_REPO

    # An unassigned slot on a host with **two** targets. Not a default and not
    # the first name: a slot's name says nothing about which project it holds, so
    # there is nothing to guess from — the same refusal an unnamed slot gets when
    # two are up, one axis over.
    writeProfile duo
    run both collect
    ck "an unassigned slot refuses once this host declares two" 1 "$rc"
    ckt "  naming both, rather than picking one" saw "duo solo"
    ckt "  and saying which command assigns it" saw "provision <ref> --profile"
    ckt "  with nothing having reached the program" test ! -s out.argv

    # ...and the explicit form is still the way through, which is what makes the
    # refusal a question rather than a wall.
    run both collect --profile duo
    ck "and --profile is the way through it" 0 "$rc"
    ckt "  carrying the one that was named" \
      saw "collect argv: --capsule both --policy build --profile duo"

    # The record beats the ambiguity, and it is the field `capsule-provision`
    # has written at every provision since item 29 and nothing read until now.
    # Written here rather than provisioned, because a provision needs a guest.
    assign both solo
    run both collect
    ck "a slot whose record names a target needs no help" 0 "$rc"
    ckt "  and it is the recorded one" \
      saw "collect argv: --capsule both --profile solo --policy build"
    # The record is read and the *other* slot is still ambiguous, which is what
    # says this was per slot rather than the host acquiring an answer.
    run one collect
    ck "and its neighbour still refuses" 1 "$rc"
    ckt "  naming both" saw "duo solo"

    # ------------------------------- the unit scope, and item 51's decision 3
    #
    # `stateNeedsUnit` was an eval-time predicate over *this host's* target, so
    # the front end offered the `unit` verb, printed the column and filled the
    # flag according to a project no slot here holds. Step 6 makes it a question
    # about the document a slot resolves to — and decision 3 draws the line
    # between the two halves of that: a **program** holds one profile and
    # branches on it, this **front end** holds N slots over M targets and does
    # not, so the column is always printed and the refusals are per slot.
    #
    # `both` is on `solo`, which declares no state paths at all.
    run both unit u1
    ck "a unit against a target with no state paths refuses" 1 "$rc"
    ckt "  naming the target rather than the slot" saw "profile solo"
    ckt "  and saying what the token would have scoped" saw "with a place for one"
    ckt "  with nothing written" test "$(jq -r .unit "$CASE_STATE/slot/both/assignment.json")" = null

    # Reading is not writing: the column below prints for every slot, so asking
    # what is recorded has to work wherever the column does.
    run both unit
    ck "reading the field is not refused" 0 "$rc"
    ckt "  and is the absent value" saw -

    # The other side of the fork, so neither answer is a constant. Same slot,
    # same record, one different document.
    writeProfile holed '["state/{unit}/notes"]'
    assign both holed
    run both unit u1
    ck "and a unit against a holed one is taken" 0 "$rc"
    ckt "  the record says so" \
      test "$(jq -r .unit "$CASE_STATE/slot/both/assignment.json")" = u1
    run both collect
    ck "a collect on it is filled from that record" 0 "$rc"
    ckt "  with the unit beside the policy and the profile" \
      saw "collect argv: --capsule both --profile holed --unit u1 --policy build"

    # The stale-token case, and it is the one that cannot be reached while the
    # predicate is a property of the build: the record still names `u1` and the
    # document it resolves to has nowhere to put it, so the front end must stop
    # filling it in — the program refuses a flag that scopes nothing, and a
    # front end that supplied one would make an unrelated collect impossible.
    assign both solo
    run both collect
    ck "a recorded unit is not filled in for a target with no hole" 0 "$rc"
    ckt "  so the argv is the one that target's collect accepts" \
      saw "collect argv: --capsule both --profile solo --policy build"
    ckt "  and the stale token is still on the record, unread" \
      test "$(jq -r .unit "$CASE_STATE/slot/both/assignment.json")" = u1

    # A slot nothing has assigned, on a host that now declares three documents:
    # there is no target for a token to be wrong against, so this is not the
    # refusal above. Three answers, not two — yes, no, and nothing to ask.
    run one unit u2
    ck "an unassigned slot may still record what it is driving" 0 "$rc"
    ckt "  because nothing has said which target it would scope" \
      test "$(jq -r .unit "$CASE_STATE/slot/one/assignment.json")" = u2

    # Decision 3 itself. One table for the fleet, one header, and the column is
    # there whatever any slot resolves to — `both` is on a document with no
    # hole, `one` is on none at all, and neither takes a column away from the
    # other. A pin rather than a discriminator against today's build, which is
    # what the mutation run is for.
    run all status
    ck "a fleet-wide status still answers" 0 "$rc"
    ckt "  and the unit column is always in the header" \
      grep -qE 'policy +unit +purpose' out
    ckt "  with the recorded token on the row of the slot that has one" \
      grep -qE '^one .+ u2 +-$' out

    # ------------------------------ what a provision records, and what it did not
    #
    # `recordProvisioned` grew a *profile* parameter at step 4 and its two
    # callers did not both grow an argument: `provision)` went on passing the ref
    # where the profile now goes, and `setup)` passed a variable only the other
    # branch ever set. Both are on the far side of a `work`, so both fail after
    # the code has landed in a capsule, and neither is reachable without a guest
    # — which is why a stub is the only thing that could have caught them and why
    # step 4's smoke test (a status and a collect) did not.
    run both provision somecommit
    ck "a provision records against the resolved profile" 0 "$rc"
    ckt "  having reached the program" saw "provision argv:"
    # There is no guest here, so the base is what cannot be recorded — and this
    # is the message that says the *record* step ran at all rather than dying on
    # its arguments.
    ckt "  and stops at the guest rather than at its own argv" \
      saw "did not answer for its HEAD"
    # The bug itself, stated as what must *not* appear: the ref in the profile's
    # place resolved as a profile name, and this is that refusal's own words.
    ckt "  not treating the ref as a target" \
      unsaw "profile named 'somecommit'"
    run both setup somecommit
    ck "and a setup gets through the same step" 0 "$rc"
    ckt "  injecting after the provision" saw "inject argv:"
    # The last of the build-time gates: `capsule-baseline` used to be *absent*
    # from a host whose target declared none, so `setup` was built without the
    # call. It is a question about the slot's document now, and a setup with
    # nothing to build is finished rather than failed.
    ckt "  and skipping a baseline this target does not declare" \
      saw "declares no baseline"
    ckt "  so nothing ran one" test "$(cat out.argv)" = "--capsule both"

    writeProfile built '[]' 'just test'
    assign both built
    run both setup somecommit
    ck "a target that declares one still gets it" 0 "$rc"
    ckt "  as the last step of the sequence" saw "baseline argv: --capsule both --profile built"
    ckt "  and says nothing about skipping" unsaw "declares no baseline"

    # ------------------------- the scope a setup carries, and NOTES item 53
    #
    # A `setup` *is* a provision, so state taken from this host's checkout is
    # scoped by the same token — and the interception was written into
    # `provision)`, `collect)` and `brief)` and not here, so the flags that
    # worked on a provision reached the state snapshot with nothing to scope by
    # and were refused there. Three copies of one construction were already one
    # too many; these rounds are over the fourth call site of the function they
    # became, and the first two of them are the same pair `provision` has.
    assign both holed
    run both setup somecommit --state-from-host
    ck "a setup that carries state is scoped from the record" 0 "$rc"
    ckt "  with the token beside the profile, before the program sees it" \
      saw "provision argv: --capsule both --profile holed --unit u1 somecommit --state-from-host"
    ckt "  and the rest of the sequence still ran" saw "inject argv:"

    # The carrier is the whole of what says an invocation has state to scope:
    # a setup that asks for none needs no token, and one filled in anyway is a
    # flag the program has nothing to apply.
    run both setup somecommit
    ck "a setup that carries none is not scoped" 0 "$rc"
    ckt "  so the argv is the one that provision accepts" \
      saw "provision argv: --capsule both --profile holed somecommit"

    # An explicit one wins and is not doubled, the same rule as `--policy` and
    # `--profile` two verbs over: a one-off under another unit's scope is a
    # human's call.
    run both setup somecommit --state-from-host --unit u9
    ck "an explicit --unit wins on a setup too" 0 "$rc"
    ckt "  and is not doubled" \
      saw "provision argv: --capsule both --profile holed somecommit --state-from-host --unit u9"

    # And the *document* decides whether there is anywhere to put one — the
    # stale-token round above, on the verb that did not have it. `built`
    # declares no state paths and the record still names `u1`.
    assign both built
    run both setup somecommit --state-from-host
    ck "a setup on a target with no hole is not scoped either" 0 "$rc"
    ckt "  so the stale token stays on the record, unread" \
      saw "provision argv: --capsule both --profile built somecommit --state-from-host"

    # ========================= the two coarse verbs, and NOTES item 53
    #
    # `handoff` and `land` are compositions in this front end and not programs
    # (item 53, "Where they live"), and the *order* is the whole of them: every
    # step is a rule some hand-run sequence supplied on the day, and a composite
    # that drops one is worse than the three commands it replaces. So each is a
    # round — and every one of them sits downstream of a round trip to a guest,
    # which is what `guestControl` above is for.
    export CAPSULE_REPO=$repo
    export CASE_GUEST_LOG=$PWD/guest.log
    : > "$CASE_GUEST_LOG"
    mkdir -p "$CASE_STATE/head"
    assign one holed
    assign both holed
    # The source's own refs in the repo, which the rounds above left diverging
    # from its quarantine on purpose. A handoff fetches its source — the
    # provision pushes from this repo and the tip has to be in it — so that
    # divergence is a refusal of its own, and it is `land`'s round below rather
    # than the setup for everything else.
    g update-ref -d refs/capsule/both/heads/work
    g update-ref -d refs/capsule/both/state/implementation

    # --------------------------------------------- what it refuses on sight
    #
    # In the order they are asked, so a round that passed for the next
    # refusal's reason would show up as the wrong message.
    run one handoff
    ck "a handoff with no source refuses" 1 "$rc"
    ckt "  saying what a source is for" saw "handoff needs a source"
    ckt "  with nothing having reached a program" test ! -s out.argv
    run one handoff nowhere --purpose x
    ck "a source that is not a capsule refuses" 1 "$rc"
    ckt "  naming the pair a handoff is between" saw "a handoff is"
    run one handoff both none --purpose x
    ck "two sources refuse" 1 "$rc"
    ckt "  naming both" saw "'both' and 'none' are two"
    run one handoff one --purpose x
    ck "a slot may not be handed its own work" 1 "$rc"
    ckt "  because a handoff is a second capsule" saw "cannot be handed its own work"
    run one handoff both
    ck "a handoff with no purpose refuses" 1 "$rc"
    # The token below is copied without asking and the sentence is not: item 29,
    # which is the line this pair of rounds is drawn from.
    ckt "  because the sentence is the human's" saw "handoff needs --purpose"
    ckt "  and is the one thing not derivable from the source" \
      saw "not derivable from"
    ckt "  with nothing having reached a program" test ! -s out.argv

    # Two slots on two documents have no work to hand between them, and this is
    # cheaper to refuse than to discover at a push into the wrong project.
    assign one duo
    run one handoff both --purpose x
    ck "a handoff across two targets refuses" 1 "$rc"
    ckt "  naming both documents" saw "on profile holed"
    ckt "  rather than the slots alone" saw "no work to hand between them"
    assign one holed

    # ----------------------------------- the verify, which is the whole item
    #
    # A quarantine is a snapshot and nothing said how old one was against its
    # source: a collect four hours stale and a current one were
    # indistinguishable at the point somebody merged. The comparison is against
    # the guest's own HEAD, so a source that does not answer cannot be verified
    # at all — and the refusal is *start it*, never a flag.
    run one handoff both --purpose x
    ck "a handoff from a source that is silent refuses" 1 "$rc"
    ckt "  saying there is nothing to check the exhibit against" \
      saw "did not answer for its HEAD"
    ckt "  and that there is no override for it" saw "There is no override"
    ckt "  with nothing provisioned" unsaw "provision argv"
    # It collected first, which is what makes the refusal a fact about now
    # rather than about whenever somebody last collected.
    ckt "  having collected the source first" saw "collect argv: --capsule both"

    # The failure itself: a guest ahead of its own exhibit. `first` is in the
    # repo and `second` is what both.git holds, so a head of `first` is a guest
    # the collect did not reach.
    printf '%s' "$first" > "$CASE_STATE/head/both"
    run one handoff both --purpose x
    ck "an exhibit that lags its guest refuses" 1 "$rc"
    ckt "  saying the collect did not take what the guest has" \
      saw "the collect that just ran did not"
    ckt "  and showing what the quarantine does hold" saw "capsule/both/heads/work"
    ckt "  with nothing provisioned" unsaw "provision argv"

    # ------------------------------- the modified tracked file, and decision 2
    #
    # Two classes with two fates. Untracked-but-not-ignored work is staged as
    # *content* into the state tree, so it travels; a modified tracked file is
    # in no code ref and no path list, so the exhibit carries it as a diff
    # nobody applied — and standing a second capsule on that is a checkout
    # nobody ever had. Read from the exhibit and never from the guest, so the
    # verdict does not change if the source goes down in between.
    printf '%s' "$second" > "$CASE_STATE/head/both"
    dblob=$(printf 'diff --git a/x b/x\n@@\ndiff --git a/y b/y\n@@\n' | g hash-object -w --stdin)
    dinner=$(printf '100644 blob %s\tdirty.diff\n' "$dblob" | g mktree)
    dtree=$(printf '040000 tree %s\t.capsule\n' "$dinner" | g mktree)
    stDirty=$(printf 'capsule state: implementation\n\nstage: implementation\ncode-oid: %s\ndirty: 5\nunit: u1\n' \
      "$second" | g commit-tree "$dtree")
    g push -q "$CASE_STATE/collect/both.git" \
      "+$stDirty:refs/capsule/both/state/implementation"
    run one handoff both --purpose x
    ck "a source with modified tracked files refuses" 1 "$rc"
    ckt "  counting the files in the diff the exhibit carries" \
      saw "has 2 modified tracked file(s)"
    ckt "  and naming the remedy in the source" saw "Commit them in 'both'"
    ckt "  while saying the untracked half travelled" saw "own count is 5"
    ckt "  with nothing provisioned" unsaw "provision argv"

    # The other side of the fork, so neither answer is a constant: the same
    # exhibit with an empty diff and the same `dirty:` count is uncommitted
    # work that *travelled*, and it is not a refusal.
    eblob=$(printf "" | g hash-object -w --stdin)
    einner=$(printf '100644 blob %s\tdirty.diff\n' "$eblob" | g mktree)
    etree=$(printf '040000 tree %s\t.capsule\n' "$einner" | g mktree)
    stClean=$(printf 'capsule state: implementation\n\nstage: implementation\ncode-oid: %s\ndirty: 5\nunit: u1\n' \
      "$second" | g commit-tree "$etree")
    g push -q "$CASE_STATE/collect/both.git" \
      "+$stClean:refs/capsule/both/state/implementation"

    # --------------------------- the archive, and decision 3's collision rule
    #
    # A generation is superseded once. `create` in the transaction refuses a
    # name that is taken, so two archives under one name is a refusal with
    # nothing moved rather than a rename that quietly loses the first.
    wasGen=$(gen one)
    g update-ref "refs/capsule/one/gen/$wasGen/heads/work" "$base"
    run one handoff both --purpose x
    ck "an archive whose name is taken refuses" 1 "$rc"
    ckt "  saying nothing was moved" saw "nothing was moved"
    ckt "  and nothing may be forced over it" saw "nothing may be forced over them"
    ckt "  leaving the destination's refs where they were" \
      test "$(g rev-parse refs/capsule/one/heads/work)" = "$second"
    ckt "  with nothing provisioned" unsaw "provision argv"
    g update-ref -d "refs/capsule/one/gen/$wasGen/heads/work"

    # ---------------------------------------- the destination's own chain
    #
    # A provision does not touch `${stateRefPrefix}/*` on the destination's
    # volume and the brief inside one is not forced, so a stale link there
    # refuses the incoming chain — which is rooted elsewhere entirely — for a
    # reason that reads as a bug (item 50's fast-forward half). A drop that
    # fails must stop *before* the force.
    printf '%s' "$second" > "$CASE_STATE/head/one"
    export CASE_DROP_FAIL=1
    run one handoff both --purpose x
    ck "a stale chain that cannot be dropped stops the handoff" 1 "$rc"
    ckt "  naming what the push would otherwise be refused for" \
      saw "non-fast-forward"
    ckt "  and saying nothing was provisioned" saw "Nothing was provisioned"
    ckt "  because nothing was" unsaw "provision argv"
    unset CASE_DROP_FAIL
    # The archive did run, which is what says the order is the one that makes
    # the force safe — and it is undone here so the round below is the whole
    # sequence rather than half of it.
    ckt "  though what the destination had is already archived" \
      test "$(g rev-parse "refs/capsule/one/gen/$wasGen/heads/work")" = "$second"
    g update-ref "refs/capsule/one/heads/work" "$second"
    g update-ref "refs/capsule/one/state/implementation" "$st2"
    g update-ref -d "refs/capsule/one/gen/$wasGen/heads/work"
    g update-ref -d "refs/capsule/one/gen/$wasGen/state/implementation"

    # A handoff fetches its *source* as well, because `capsule-provision`
    # resolves its ref in this repo and the tip has to be here to be pushed. A
    # source whose refs in the repo diverge from its quarantine is item 50 one
    # slot over, and it stops the handoff before anything is archived or
    # forced: the archive this verb runs is the **destination's**, and a
    # divergence somebody left behind is somebody's.
    g update-ref refs/capsule/both/heads/work "$first"
    run one handoff both --purpose x
    ck "a handoff whose source cannot be fetched stops" 1 "$rc"
    ckt "  with the archive as the remedy there too" saw "refs/capsule/both/gen/"
    ckt "  and nothing provisioned" unsaw "provision argv"
    g update-ref -d refs/capsule/both/heads/work

    # ------------------------------------------------ the whole sequence
    #
    # Cleared, because the round above logged the drop it then refused to
    # believe — and a round that passes on the previous call's evidence is a
    # round that never discriminates (item 37).
    : > "$CASE_GUEST_LOG"
    run one handoff both --purpose "a second pair of eyes"
    ck "a handoff runs" 0 "$rc"
    ckt "  collecting the source" saw "collect argv: --capsule both"
    ckt "  and the destination, before anything is forced over it" \
      saw "collect argv: --capsule one"
    ckt "  archiving what the destination held" \
      test "$(g rev-parse "refs/capsule/one/gen/$wasGen/heads/work")" = "$second"
    ckt "  including its state half" \
      test "$(g rev-parse "refs/capsule/one/gen/$wasGen/state/implementation")" = "$st2"
    # Freed rather than left holding the superseded assignment, so the next
    # collect of *this* assignment fetches into a name nothing is sitting on —
    # which is the refusal item 50 measured, not happening.
    ckt "  and freeing the live names" \
      test "$(g for-each-ref --format=x refs/capsule/one/heads/)" = ""
    ckt "  dropping the destination's own chain" \
      grep -qx "one implementation" "$CASE_GUEST_LOG"
    ckt "  and saying which link went" saw "${stateRefPrefix}/implementation"
    # One provision, carrying its state: on a target whose refresh commits
    # there is no moment after a provision when a brief can land (item 47).
    ckt "  provisioning once, at the source's tip, carrying its state" \
      saw "provision argv: --capsule one --profile holed $second --force --state both"
    ckt "  and never briefing separately afterwards" unsaw "brief argv"
    ckt "  the token is the source's" \
      test "$(jq -r .unit "$CASE_STATE/slot/one/assignment.json")" = u1
    ckt "  the sentence is the human's" \
      test "$(jq -r .purpose "$CASE_STATE/slot/one/assignment.json")" = "a second pair of eyes"
    ckt "  and the base is what was handed over" \
      test "$(jq -r .base.oid "$CASE_STATE/slot/one/assignment.json")" = "$second"

    # ------------------------------------------------ land, and its report
    #
    # It stops at refs: which branch a result belongs on is the target's
    # governance (item 18's direction, applied to naming), so the default is a
    # report and there is no default *name*.
    run both land nope
    ck "land takes no bare argument" 1 "$rc"
    ckt "  saying why there is no default branch" saw "is the target's to say"

    # The same verify, from the other verb — one exhibit read and one shipped.
    printf '%s' "$first" > "$CASE_STATE/head/both"
    run both land
    ck "a land whose exhibit lags its guest refuses" 1 "$rc"
    ckt "  by the same comparison" saw "the collect that just ran did not"
    printf '%s' "$second" > "$CASE_STATE/head/both"

    # A repo holding one assignment's refs while the quarantine holds another's
    # is what a land runs into when a slot has been reassigned and nobody
    # archived — item 50, from the accepting end.
    g update-ref refs/capsule/both/heads/work "$first"
    g update-ref refs/capsule/both/state/implementation "$st1"
    run both land
    ck "a land whose fetch is refused stops there" 1 "$rc"
    ckt "  with the archive as the remedy, not a force" saw "refs/capsule/both/gen/"
    # Both halves, because both diverged — the archive by hand that the message
    # above asks for, which is what `handoff` does for itself one section up.
    g update-ref -d refs/capsule/both/heads/work
    g update-ref -d refs/capsule/both/state/implementation

    g update-ref refs/heads/main "$base"
    g symbolic-ref HEAD refs/heads/main
    run both land
    ck "a land lands" 0 "$rc"
    ckt "  fetching the code half" saw "capsule both: code: landed"
    ckt "  under the refs the git channel already owns" \
      test "$(g rev-parse refs/capsule/both/heads/work)" = "$second"
    # A fact about that repo rather than a value of ours: the branch is named
    # without ever having been chosen.
    ckt "  reporting against the branch it found" saw "against main"
    ckt "  with the divergence in both directions" \
      saw "1 commit(s) here that it has not, 0 there"
    ckt "  and no branch written" test "$(g for-each-ref --format=x refs/heads/)" = "x"

    run both land --branch accepted
    ck "a land may be handed a name" 0 "$rc"
    ckt "  and writes it" test "$(g rev-parse refs/heads/accepted)" = "$second"
    run both land --branch accepted
    ck "and refuses a name that exists rather than moving it" 1 "$rc"
    ckt "  so nothing a land does can lose a commit" saw "never"
    ckt "  and it did not move" test "$(g rev-parse refs/heads/accepted)" = "$second"

    # The conflicting-paths half of the report, which is the part that earns
    # the verb: one file, two edits, one common base.
    bA=$(printf 'A\n' | g hash-object -w --stdin)
    bB=$(printf 'B\n' | g hash-object -w --stdin)
    bC=$(printf 'C\n' | g hash-object -w --stdin)
    tA=$(printf '100644 blob %s\tf\n' "$bA" | g mktree)
    tB=$(printf '100644 blob %s\tf\n' "$bB" | g mktree)
    tC=$(printf '100644 blob %s\tf\n' "$bC" | g mktree)
    cBase=$(g commit-tree "$tA" -m 'f is A')
    cMine=$(g commit-tree "$tB" -p "$cBase" -m 'f is B here')
    cTheirs=$(g commit-tree "$tC" -p "$cBase" -m 'f is C in the capsule')
    g update-ref refs/heads/main "$cMine"
    run none unit u3
    assign none holed
    git init -q --bare "$CASE_STATE/collect/none.git"
    g push -q "$CASE_STATE/collect/none.git" "$cTheirs:refs/capsule/none/heads/work"
    printf '%s' "$cTheirs" > "$CASE_STATE/head/none"
    run none land
    ck "a land whose work would conflict still lands" 0 "$rc"
    ckt "  reporting the divergence" saw "1 commit(s) here that it has not, 1 there"
    ckt "  and the paths a merge would fall over" saw "would conflict on:"
    ckt "  naming them" grep -qE '^ +f$' out
    # A destination nothing has ever been assigned to has no generation to key
    # an archive by, because it has nothing to archive — not a refusal, but the
    # ordinary first assignment of a free slot. The record is *removed* rather
    # than never written, because reaching this state any other way would mean
    # a fourth slot in the fixture; and the documents come down to one so that
    # a slot with no record still resolves to a target.
    rm -rf "''${CASE_STATE:?}/slot/none"
    rm profiles/duo.json profiles/holed.json profiles/built.json
    assign both solo
    run none handoff both --purpose "a fresh pair"
    ck "a handoff into a slot nothing has assigned runs" 0 "$rc"
    ckt "  saying there was nothing to archive" saw "nothing to archive"
    ckt "  and provisioning it anyway" \
      saw "provision argv: --capsule none --profile solo $second --force --state both"
    unset CAPSULE_REPO

    # A host that has rendered nothing at all: a different fault from an
    # ambiguous one, and a refusal that names the directory rather than the slot.
    rm profiles/solo.json
    unassign one
    run one collect
    ck "a host with no documents refuses too" 1 "$rc"
    ckt "  and names where it looked" saw "$CAPSULE_PROFILE_DIR"
    ckt "  rather than reporting an ambiguity" saw "has rendered no"

    [ "$fail" = 0 ] || exit 1
    cp "$log" $out
    cat $out
  ''
