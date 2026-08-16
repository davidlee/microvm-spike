# What a profile document is, and what a bad one gets — NOTES item 51 step 3.
#
# The third kind of check (CLAUDE.md) over a *library* rather than a program:
# `host/profile.nix` ships a shell fragment for `host/record.nix`'s reason, so
# what a suite can run is that fragment spliced into something with a `main`. The
# fragment is handed here from the same construction `flake.nix` gives every
# caller, so there is one text and this suite is not a second render of it.
#
# **Two subjects, and both are the shipped ones.** The fragment, and the
# directory this host actually rendered — the first case loads `<target>.json`
# with no environment at all, which is also the only thing that makes the
# document a build input of anything
# ([item 37](../docs/ledger/037-a-teardown-that-only-unnames.md): a document
# nothing builds is a document nothing checks).
#
# What a live host reaches only expensively or not at all is everything after
# that: a second target on this host, a document truncated mid-write, one from a
# newer schema, one whose ceiling is missing. Each of those is a rebuild, a
# migration, or a fault on a host holding live work.
#
# Two rules for a case here, as everywhere: assert the **reason** and not only
# the status, since a refusal for the wrong reason is a different program
# passing; and every one of these was watched going red against a mutated copy of
# the fragment.
{
  pkgs,
  lib,
  # `host/profile.nix` as every caller gets it, never a second render.
  fragment,
  # The argv parse every host-side program splices beside its `transport`
  # (item 51 step 4). Its own subject: what a program does with no `--profile` is
  # the refusal decision 4 turns on, and it is not reachable through `fragment`.
  select,
  inputs,
  # The directory this host rendered, and the name of the document in it.
  dir,
  name,
  # The same file as a function of a target, for the *render's* own refusals —
  # the third subject, and a fixture rather than this host's target for
  # `guardCases`' reason: what is being pinned is a check that fires on a
  # document nobody can render, so there is nothing shipped to run it against.
  # One construction, handed down from `flake.nix`, so this is still not a second
  # spelling of the file under test.
  render,
}: let
  # A target that satisfies every check, so each mutation below differs from a
  # rendering document in exactly one thing. Nothing here is doctrine's: a
  # fixture that borrowed live values would go on passing while the declaration
  # moved onto it ([item 38](../docs/ledger/038-a-probe-that-became-a-borrower.md)).
  base = {
    name = "fixture";
    path = "/h/fixture";
    volumePath = "/vol";
    guestPath = "/vol/fixture";
    cachePaths = ["/vol/.cache"];
    statePaths = [".s/{unit}"];
    stateMaxBytes = 1024;
    baseline = "build it";
    refresh = "boot it";
    sizes = {
      vcpu = 1;
      mem = 1;
      volume = 1;
    };
  };

  # Forcing the store path is what forces the checks: they guard the document on
  # its way into `writeText`, so a render that is never asked for never throws.
  renders = t: (builtins.tryEval (builtins.seq (render t).dir.outPath true)).success;

  # One invariant each, and the name is what the log prints — a suite that only
  # counted refusals would pass with one check doing all the work.
  mutations = [
    {
      why = "a guestPath that is not derived from volumePath and name";
      t = base // {guestPath = "/vol/somewhere-else";};
    }
    {
      why = "a name that is a path";
      t = base // {name = "a/b";};
    }
    {
      why = "a relative host checkout";
      t = base // {path = "h/fixture";};
    }
    {
      why = "a cache outside the volume";
      t = base // {cachePaths = ["/etc/cache"];};
    }
    {
      why = "a state template that escapes the checkout";
      t = base // {statePaths = ["../elsewhere/{unit}"];};
    }
    {
      why = "a state template that is absolute";
      t = base // {statePaths = ["/etc/{unit}"];};
    }
    {
      why = "a state template holding two unit holes";
      t = base // {statePaths = ["{unit}/x/{unit}"];};
    }
    {
      why = "declared state paths with no ceiling over them";
      t = base // {stateMaxBytes = 0;};
    }
    {
      why = "a size that is not a positive integer";
      t =
        base
        // {
          sizes = base.sizes // {vcpu = 0;};
        };
    }
    {
      why = "a baseline that is an empty command line";
      t = base // {baseline = "";};
    }
    {
      why = "a value with a newline in it";
      t = base // {path = "/h/two\nlines";};
    }
  ];

  # `refused`/`RENDERED` per line, decided at eval and asserted in the shell —
  # the same arrangement `hostModuleUnits` uses, for the same reason: what is
  # being read is a *throw*, and a throw is not a build.
  renderReport =
    lib.concatMapStringsSep "\n"
    (m: "${
      if renders m.t
      then "RENDERED"
      else "refused"
    } ${m.why}")
    mutations;

  # The control, so a render that refuses everything cannot be read as this
  # suite passing (item 37: a round that never discriminates).
  controlRenders = renders base;

  # The fragment plus the smallest `main` that exercises it: load, then print.
  # `profileShow`'s output is the contract every case below reads a field out
  # of, so no case spells a jq path of its own.
  probe = pkgs.writeShellApplication {
    name = "capsule-profile-probe";
    runtimeInputs = inputs;
    text = ''
      ${fragment}
      profileLoad "''${1:-}"
      profileShow
    '';
  };

  # The second subject, and the smallest thing that has one: a program's argv,
  # parsed by the fragment every real program splices, with what survives the
  # parse printed back. `left` is how a case asserts that a target's name did not
  # stay in the arguments a ref or a payload name is read out of.
  selector = pkgs.writeShellApplication {
    name = "capsule-profile-select-probe";
    runtimeInputs = inputs;
    text = ''
      ${fragment}
      ${select}
      printf 'left\t%s\n' "$*"
      profileShow
      profileNames | sed 's/^/declared\t/'
      # The hop's escaping, round-tripped rather than compared against a spelling
      # of what `%q` produces: what has to hold is that a second shell reading
      # these words gets the values back, and asserting the *bytes* would be
      # asserting about bash's choice of quoting style.
      printf '%s\n' "$profile_path" ''${profile_cache_paths[@]+"''${profile_cache_paths[@]}"} \
        | profileQuote | sed 's/^/quoted\t/'
    '';
  };
in
  pkgs.runCommand "capsule-profile-cases" {nativeBuildInputs = [pkgs.jq];} ''
    fail=0
    log=$PWD/log
    : >"$log"
    ck() {
      if [ "$2" = "$3" ]; then echo "ok   $1" >>"$log"
      else echo "FAIL $1: got '$3', wanted '$2'" >&2; fail=1; fi
    }
    # One field of `profileShow`'s output. Repeated keys — the two arrays — come
    # back one line each, which is what makes a count an assertion.
    field() { awk -F'\t' -v k="$1" '$1 == k {print $2}' out; }
    run() { rc=0; ${lib.getExe probe} "$@" >out 2>err || rc=$?; }
    saw() {
      if grep -qF -- "$1" err; then echo "ok   ...and says '$1'" >>"$log"
      else echo "FAIL missing reason '$1' in: $(cat err)" >&2; fail=1; fi
    }

    # ------------------------------------------------ the document this host has
    #
    # No CAPSULE_PROFILE_DIR, so the baked default is what answers — the shipped
    # render read by the shipped reader.
    run ${lib.escapeShellArg name}
    ck "this host's own profile loads" 0 "$rc"
    ck "  under the name it was rendered as" ${lib.escapeShellArg name} "$(field name)"
    ck "  with a host checkout" 1 "$(field path | grep -c '^/')"
    ck "  and a volume mount point" 1 "$(field volumePath | grep -c '^/')"
    # Read out of the document rather than compared against nix: what is asserted
    # is that the derivation survived the render, and a suite that spelled the
    # expected value would be agreeing with itself instead.
    ck "  whose checkout is derived from the two of them" \
      "$(field guestPath)" "$(field volumePath)/$(field name)"
    ck "  and a positive vCPU count" 1 "$(field vcpu | grep -c '^[1-9][0-9]*$')"

    # From here the documents are fixtures: a second target on this host is a
    # rebuild away, and a broken one cannot be rendered at all.
    mkdir -p profiles
    export CAPSULE_PROFILE_DIR=$PWD/profiles
    write() { printf '%s' "$2" | jq -S . > "profiles/$1.json"; }

    write alpha '{ "schema": 1, "name": "alpha", "path": "/home/h/alpha",
      "guestPath": "/work/alpha", "volumePath": "/work",
      "cachePaths": ["/work/.cargo"], "baseline": "just test",
      "refresh": "alpha boot", "statePaths": [".a/state/{unit}", ".a/unit/{unit}"],
      "stateMaxBytes": 1024, "sizes": {"vcpu": 4, "mem": 6144, "volume": 32768} }'

    write beta '{ "schema": 1, "name": "beta", "path": "/srv/beta",
      "guestPath": "/vol/beta", "volumePath": "/vol",
      "cachePaths": [], "baseline": null, "refresh": null,
      "statePaths": [], "stateMaxBytes": 0,
      "sizes": {"vcpu": 1, "mem": 512, "volume": 1024} }'

    # ------------------------------------------------------ one reader, N targets
    #
    # The claim the whole item is about, in its smallest form: two projects, one
    # store path, and the only thing that differs is a name on a command line.
    run alpha
    ck "a second target loads from the same reader" 0 "$rc"
    ck "  and answers its own checkout" /home/h/alpha "$(field path)"
    run beta
    ck "a third does too" 0 "$rc"
    ck "  with a different one" /srv/beta "$(field path)"

    # ------------------------------------------------------- the optional fields
    #
    # `null` is a target that declares no baseline, which is a working absent
    # path (contract-target.md); a *missing* key is a broken document. The two
    # must not arrive as the same thing, which is why the reader separates them
    # and why this pair sits beside the refusal for the other one.
    run beta
    ck "a declared-absent baseline is empty and not a failure" "" "$(field baseline)"
    ck "  and so is its refresh" "" "$(field refresh)"
    ck "  and it declares no state paths" 0 "$(field statePath | grep -c . || true)"
    ck "  nor any caches" 0 "$(field cachePath | grep -c . || true)"

    run alpha
    ck "a target's state templates arrive one per entry" 2 "$(field statePath | grep -c . || true)"
    # Opaque here. The hole is substituted in the guest, by the one program that
    # knows what a unit is (host/state-snapshot.nix) — a reader that expanded it
    # would be a second place deciding an exhibit's scope.
    ck "  with the unit hole unsubstituted" 2 "$(field statePath | grep -c '{unit}' || true)"
    ck "  and its caches likewise" /work/.cargo "$(field cachePath)"

    # ------------------------------------------- whether the exhibit is scoped
    #
    # `stateNeedsUnit` was an eval-time predicate over `target.nix`'s list, so
    # "does this target scope its state by a unit of work?" was a property of
    # which flake the host had built (item 51 step 6). It is a question about a
    # loaded document now, and this fragment is the only host-side spelling of
    # it — the guest half asks the same thing of the argv it was handed
    # (host/state-snapshot.nix), which is one fact read from two ends rather
    # than two predicates that can disagree.
    run alpha
    ck "a holed template makes the target unit-scoped" yes "$(field needsUnit)"
    run beta
    ck "  and a target with no state paths is not" no "$(field needsUnit)"

    # The third shape, and the one neither of the others reaches: declared state
    # with nowhere to put a unit. A target whose out-of-band state is not
    # per-unit writes no hole and nothing about it changes (contract-target.md),
    # so "declares state" and "needs a unit" have to come apart here.
    write flat '{ "schema": 1, "name": "flat", "path": "/srv/flat",
      "guestPath": "/vol/flat", "volumePath": "/vol",
      "cachePaths": [], "baseline": null, "refresh": null,
      "statePaths": [".f/notes", ".f/log"], "stateMaxBytes": 2048,
      "sizes": {"vcpu": 1, "mem": 1, "volume": 1} }'
    run flat
    ck "  nor is one declaring state with no hole in it" no "$(field needsUnit)"
    ck "  which still declares its state" 2 "$(field statePath | grep -c . || true)"

    # ------------------------------------------------------- a value with a space
    #
    # The class item 51 named twice: a value that splits silently is what a
    # command line has to survive, and an array read back a line at a time is
    # where it would happen here.
    write spaced '{ "schema": 1, "name": "spaced", "path": "/home/h/two words",
      "guestPath": "/work/spaced", "volumePath": "/work",
      "cachePaths": ["/work/a cache"], "baseline": "just  test --all",
      "refresh": null, "statePaths": [], "stateMaxBytes": 0,
      "sizes": {"vcpu": 1, "mem": 1, "volume": 1} }'
    run spaced
    ck "a path with a space survives the read" "/home/h/two words" "$(field path)"
    ck "  and so does one in an array" "/work/a cache" "$(field cachePath)"
    ck "  and a command line keeps its spacing" "just  test --all" "$(field baseline)"

    # ------------------------------------------------- which profile a program means
    #
    # Decision 4, at the layer that takes it: a program is handed a name and
    # refuses without one. Its own directory, so a case about *what this host
    # declares* is not a case about what the rest of this file happened to write.
    mkdir -p sel
    cp profiles/alpha.json profiles/beta.json profiles/spaced.json sel/
    runsel() { rc=0; CAPSULE_PROFILE_DIR=$PWD/sel ${lib.getExe selector} "$@" >out 2>err || rc=$?; }

    runsel --profile alpha
    ck "a named profile is what a program loads" 0 "$rc"
    ck "  and it is the one named" /home/h/alpha "$(field path)"
    ck "  with nothing of it left in the arguments" "" "$(field left)"
    runsel --profile=beta
    ck "the joined form names one too" 0 "$rc"
    ck "  and it is that one" /srv/beta "$(field path)"

    # The half `selectCapsule` exists for: a program's own flag loop must not see
    # this, or a target's name is one more thing a ref could be read as.
    runsel --profile alpha some-ref --force
    ck "everything else survives the parse" 0 "$rc"
    ck "  in the order it arrived" "some-ref --force" "$(field left)"

    runsel some-ref
    ck "and a program with no profile refuses rather than defaulting" 1 "$rc"
    saw "which target?"
    # The reason, not only the status: a refusal that said "no such profile"
    # would send a human looking for a document instead of for an argument.
    saw "nothing to fall back to"
    ck "  having read nothing" "" "$(field path)"

    rc=0; CAPSULE_PROFILE=beta CAPSULE_PROFILE_DIR=$PWD/sel ${lib.getExe selector} >out 2>err || rc=$?
    ck "the environment names one, as CAPSULE_NAME does" 0 "$rc"
    ck "  and is what loads" /srv/beta "$(field path)"
    rc=0; CAPSULE_PROFILE=beta CAPSULE_PROFILE_DIR=$PWD/sel ${lib.getExe selector} --profile alpha >out 2>err || rc=$?
    ck "an explicit --profile wins over it" 0 "$rc"
    ck "  which is the one-off form winning, as everywhere here" /home/h/alpha "$(field path)"

    runsel --profile
    ck "a --profile with nothing after it refuses" 1 "$rc"
    saw "--profile needs the name"
    runsel --profile nosuch
    ck "and a name this host has not rendered refuses" 1 "$rc"
    saw "no profile named 'nosuch'"

    # ------------------------------------------------ what this host declares
    #
    # The front end's half, and the only reader of it: resolving what an
    # *unassigned* slot means is host-state resolution, which a program may not
    # do (item 20). Asserted as the whole list, since a reader that returned the
    # first entry would pass a containment test.
    runsel --profile alpha
    ck "the declared set is every document in the directory" \
      "alpha beta spaced" "$(field declared | tr '\n' ' ' | sed 's/ $//')"

    # ------------------------------------------------------------ across the door
    #
    # A value read out of a document and then handed to a guest-pushed script is
    # parsed once more, by the guest's shell (host/guest-exec.nix). Round-tripped
    # through a second parse rather than compared against a spelling of `%q`:
    # what has to hold is that the words come back, and the quoting style is
    # bash's business.
    runsel --profile spaced
    eval "back=( $(field quoted | tr '\n' ' ') )"
    ck "a value with a space survives a second shell" "/home/h/two words" "''${back[0]}"
    ck "  and so does one out of an array" "/work/a cache" "''${back[1]}"
    ck "  as two words and not four" 2 "''${#back[@]}"

    # --------------------------------------------------------------- the refusals
    #
    # Each names what is wrong with *this* document. A reader that answered "no
    # such profile" to a truncated one would send a human looking for a file that
    # is plainly there.
    run nosuch
    ck "an unrendered profile refuses" 1 "$rc"
    saw "no profile named 'nosuch'"
    saw "$CAPSULE_PROFILE_DIR"

    run
    ck "and an unnamed one refuses rather than defaulting" 1 "$rc"
    saw "no profile name"

    # A name reaches a path, so it is checked before the filesystem is touched.
    # The document it would otherwise reach is a real one, which is what makes
    # this a test of the check rather than of the layout.
    mkdir -p profiles/sub
    cp profiles/alpha.json profiles/sub/alpha.json
    run sub/alpha
    ck "a name that is a path refuses" 1 "$rc"
    saw "is a path, and a name is not one"
    ck "  without having read what it points at" 0 "$(grep -c alpha out || true)"

    printf '%s' '{ "schema": 1, "name": "cut", "path": "/h/c"' > profiles/cut.json
    run cut
    ck "a half-written document refuses" 1 "$rc"
    saw "is not a readable JSON object"

    printf '%s' '[]' > profiles/list.json
    run list
    ck "a document that is not an object refuses" 1 "$rc"
    saw "is not a readable JSON object"

    jq -S '.schema = 2' profiles/alpha.json > profiles/newer.json
    run newer
    ck "a document from a newer schema refuses" 1 "$rc"
    saw "declares schema 2; this host reads 1"

    jq -S 'del(.guestPath)' profiles/alpha.json > profiles/nopath.json
    run nopath
    ck "a document missing a required field refuses" 1 "$rc"
    saw "has no 'guestPath'"

    jq -S 'del(.sizes.mem)' profiles/alpha.json > profiles/nomem.json
    run nomem
    ck "and one missing a nested required field refuses" 1 "$rc"
    saw "has no 'sizes.mem'"

    # The one invariant the reader enforces that is about two fields rather than
    # one: a ceiling is what keeps an over-budget state half from taking a
    # collect's code refs down with it (host/state-snapshot.nix), so declared
    # paths with no ceiling is a document to refuse and not a default to invent.
    jq -S 'del(.stateMaxBytes)' profiles/alpha.json > profiles/noceil.json
    run noceil
    ck "state paths with no ceiling refuse" 1 "$rc"
    saw "declares state paths and no stateMaxBytes"

    jq -S '.stateMaxBytes = "lots"' profiles/alpha.json > profiles/words.json
    run words
    ck "a ceiling that is not a byte count refuses" 1 "$rc"
    saw "is not a byte count"

    # ------------------------------------------------------- what will not render
    #
    # The other half of the file, and the half a reader cannot do: these are the
    # checks that hold *because* nix is what renders the document, which is
    # decision 2's whole argument for starting in the store. Each fixture differs
    # from a rendering one in exactly one thing, and the control below is what
    # stops "everything throws" from reading as a pass.
    printf '%s\n' ${lib.escapeShellArg renderReport} > render
    while read -r verdict why; do
      ck "the render refuses $why" refused "$verdict"
    done < render
    ck "and a target that breaks nothing renders" true \
      ${
      if controlRenders
      then "true"
      else "false"
    }

    # ---------------------------------------------------------- the lookup itself
    #
    # `CAPSULE_PROFILE_DIR` over a baked default is `CAPSULE_REPO`'s shape, and is
    # the reason this half of the item can move to a plain file without touching
    # a caller. The override decides while it is set, and unsetting it comes back
    # to what this host rendered.
    run alpha
    ck "the override chooses the directory" /home/h/alpha "$(field path)"
    unset CAPSULE_PROFILE_DIR
    run ${lib.escapeShellArg name}
    ck "and without it the baked render is what answers" 0 "$rc"
    ck "  which is the store path this host built" 1 \
      "$(printf '%s' ${dir} | grep -c '^/nix/store/')"

    [ "$fail" = 0 ] || exit 1
    cp "$log" $out
    cat $out
  ''
