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
  stateNeedsUnit,
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
    inherit observe observeFragment programVerbs profileVerbs stateNeedsUnit;
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
  };
  buildFile = policies.policies.build.allowlist;
  sealedFile = policies.policies.sealed.allowlist;
in
  pkgs.runCommand "capsule-policy-cases" {nativeBuildInputs = [pkgs.jq];} ''
    export CASE_STATE=$PWD/state
    mkdir -p "$CASE_STATE" stub policies allow profiles
    touch policies/${buildFile} policies/${sealedFile}

    # The documents this host declares, and none of them is doctrine's: a
    # fixture that borrowed live values would go on passing while the
    # declaration moved onto it (item 38). One to start with, because the
    # interesting transition is a host acquiring a second one.
    export CAPSULE_PROFILE_DIR=$PWD/profiles
    writeProfile() {
      jq -n --arg n "$1" '{ schema: 1, name: $n, path: ("/h/" + $n),
        guestPath: ("/vol/" + $n), volumePath: "/vol", cachePaths: [],
        baseline: null, refresh: null, statePaths: [], stateMaxBytes: 0,
        sizes: {vcpu: 1, mem: 1, volume: 1} }' > "profiles/$1.json"
    }
    writeProfile solo

    # What `work` execs once the front end has filled the flags in.
    # `capsule-collect` is deliberately *not* one of the front end's
    # `runtimeInputs` — it picks between two copies of it on PATH — so a stub
    # on PATH is what it finds, and this is the one place a case can watch
    # what the front end decided rather than what it said.
    cat > stub/capsule-collect <<'EOF'
    #!/bin/sh
    echo "collect argv: $*"
    echo "$*" > "$PWD/out.argv"
    EOF
    chmod +x stub/capsule-collect
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
    gen() { jq -r .generation "$CASE_STATE/slot/$1/assignment.json"; }

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
    # shellcheck disable=SC2016
    jq '.profile = "solo"' "$CASE_STATE/slot/both/assignment.json" > tmp.json
    mv tmp.json "$CASE_STATE/slot/both/assignment.json"
    run both collect
    ck "a slot whose record names a target needs no help" 0 "$rc"
    ckt "  and it is the recorded one" \
      saw "collect argv: --capsule both --profile solo --policy build"
    # The record is read and the *other* slot is still ambiguous, which is what
    # says this was per slot rather than the host acquiring an answer.
    run one collect
    ck "and its neighbour still refuses" 1 "$rc"
    ckt "  naming both" saw "duo solo"

    # A host that has rendered nothing at all: a different fault from an
    # ambiguous one, and a refusal that names the directory rather than the slot.
    rm profiles/solo.json profiles/duo.json
    run one collect
    ck "a host with no documents refuses too" 1 "$rc"
    ckt "  and names where it looked" saw "$CAPSULE_PROFILE_DIR"
    ckt "  rather than reporting an ambiguity" saw "has rendered no"

    [ "$fail" = 0 ] || exit 1
    cp "$log" $out
    cat $out
  ''
