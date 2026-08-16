# What the module path's wrapper hands a program — `ISS-004`.
#
# **A fourth kind of check, and the reason it had to exist.** The three in
# `CLAUDE.md` cannot see this one between them: `hostModuleUnits` *evaluates* the
# module, so it proves the wrapper builds and says nothing about what it does;
# the `*Cases` suites run a program's *own text* against stubs, so they never see
# a wrapper at all. A wrapper defeating the program it wraps falls between them,
# which is why `ISS-004` shipped with item 52 naming the gap in the abstract
# ("nothing pins that the module's `wrap` exports the directory the module also
# creates") and reading it as a test that had not been written rather than as a
# defect. The subject here is neither a program nor a fragment but the
# **composition** — a wrapper around an inner program — and the question is
# whether a value the caller set survives the last line before that program runs.
#
# The subject is the shipped builder (`host/wrap.nix`), **handed a fixture** like
# the guard's stubbed kernel and the front end's pool that is nobody's: the paths
# below are not this host's, because what is pinned is the *rule* — supply a
# default, impose nothing — and a suite spelling `/var/lib/capsule` would go green
# on a host that had moved it. Each variable's *value* is read from the same
# `defaults` the wrapper builds from, so no case can agree with itself about one;
# the *set* of them is spelled out below instead, and the comment there is why.
#
# Both rules for writing a case apply. Each override case asserts *which* value
# arrived and not merely that the program ran, since a wrapper that dropped the
# variable entirely and one that honoured it are the same exit status; and the
# whole suite was watched going red against `wrap` as it shipped before this —
# the five `export V=<default>` lines — where every override case failed with the
# fixture's own path as the value it got.
#
# Then mutated, one break at a time, to see *which* rounds go red, which is how
# two of these got their present shape. Four rounds and what each one taught:
#
#   - the five bare `export V=<default>` lines, i.e. `wrap` as it shipped —
#     the five override cases, and nothing else. The red this suite was for.
#   - `"$@"` unquoted — **the build**, on `SC2068`, so no case ran at all and it
#     reads exactly like nothing going red (CLAUDE.md). `"$*"` is the honest
#     mutation that gets past shellcheck, and it lands on `argc` as 1 rather
#     than 4. A stub printing `"$*"` would have re-joined the split arguments
#     into the string the case wanted, which is why it prints each one bracketed.
#   - escaping *twice* — the space case, whose default arrives carrying its own
#     quote characters. This is the count-of-one rule and the live risk here.
#   - `escapeShellArg` removed — **nothing**, and that is a fact about the
#     construction rather than a hole: `lib.escapeShellArg` is a no-op on a path
#     of ordinary characters, and the right-hand side of an assignment is not
#     word-split, so even the spaced fixture arrives whole without it. A fixture
#     hostile enough to discriminate is not available — `writeShellApplication`
#     shellchecks the *built wrapper*, so a `$` in a declared path is `SC2016`
#     escaped or not, and a bare `'` is a parse error. That class is caught one
#     layer before this suite runs, and by shellcheck rather than by a case.
{
  pkgs,
  lib,
}: let
  # Nobody's host. Two sets, because the second pins the escaping.
  plain = {
    stateDir = "/fixture/state";
    repo = "/fixture/repo";
    policyDir = "/fixture/policy";
    allowlistDir = "/fixture/allow";
    profileDir = "/fixture/profiles";
  };

  # The only fixture value `escapeShellArg` does anything to — it is a no-op on a
  # path of ordinary characters — and so the only one that can see the escaping
  # being applied twice. Which is what it is for; the header's fourth mutation is
  # why it is not for the escaping being applied at all.
  spaced = lib.mapAttrs (_: v: "/fixture/two words${v}") plain;

  wrapWith = paths: (import ./wrap.nix {inherit pkgs lib paths;});

  # The smallest inner program that can answer the question: what did the
  # wrapper leave in the environment, and did the arguments survive it. Every
  # `CAPSULE_*` there is, not the five this suite remembers — that is what makes
  # a sixth variable appear in the output instead of being invisible.
  echoEnv = pkgs.writeShellApplication {
    name = "capsule-echo-env";
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep];
    text = ''
      # `|| true`, since a wrapper that supplied *nothing* is a verdict this
      # suite has cases for and not a stub that should die on an empty pipe.
      env | grep '^CAPSULE_' | sort || true
      # The count and each argument bracketed, never `"$*"`: a wrapper that lost
      # the quoting on `"$@"` re-splits `--profile 'two words'` into two
      # arguments, and `$*` joins them back with a space into the string the
      # unsplit case wanted. One `$*` assertion would have passed for the bug.
      printf 'argc=%s\n' "$#"
      for a in "$@"; do printf 'arg=[%s]\n' "$a"; done
    '';
  };

  subject = paths: (wrapWith paths).wrap "capsule-echo-env-wrapped" echoEnv;
  inherit (wrapWith plain) defaults;
  names = builtins.attrNames defaults;
in
  pkgs.runCommand "capsule-wrap-cases" {} ''
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

    plain=${lib.getExe (subject plain)}
    spaced=${lib.getExe (subject spaced)}

    # `env -i` and not the ambient environment: this build's own `CAPSULE_*`
    # would be indistinguishable from the wrapper's, and the "exactly these
    # five" case below is the one that would go green for the wrong reason.
    # `PATH` survives because the inner program's `runtimeInputs` prepend to it
    # rather than replacing it, so an empty one is a `writeShellApplication`
    # that cannot find `env`.
    clean() { env -i PATH="$PATH" "$@"; }

    # ------------------------------------------------- the default it supplies
    #
    # The wrapper's first job, and the one that already worked: a program run
    # from anywhere on `$PATH` must not derive its state directory from `$PWD`
    # (NOTES item 11).
    clean "$plain" >out 2>err
    ${lib.concatMapStringsSep "\n" (v: ''
        ck "${v} defaults to what this host declares" \
          "${defaults.${v}}" "$(sed -n 's/^${v}=//p' out)"
      '')
      names}

    # --------------------------------------------------- and the caller's win
    #
    # `ISS-004` itself. The defeated caller is the front end this module
    # installs: `host/cli.nix`'s `slotProfileName` resolves a slot's pinned
    # profile directory, exports it and execs `capsule-collect` — which on this
    # path is the wrapper, whose last line used to overwrite the answer.
    ${lib.concatMapStringsSep "\n" (v: ''
        clean env ${v}=/from/the/caller "$plain" >out 2>err
        ck "${v} set by the caller survives the wrapper" \
          /from/the/caller "$(sed -n 's/^${v}=//p' out)"
      '')
      names}

    # ------------------------------------------------------ and empty is unset
    #
    # `:-` and not `-`, deliberately: an exported-but-empty `CAPSULE_PROFILE_DIR`
    # would send `profileLoad` looking for `/<name>.json`, and a caller that
    # cleared a variable meant to stop overriding it rather than to name the
    # root directory.
    ${lib.concatMapStringsSep "\n" (v: ''
        clean env ${v}= "$plain" >out 2>err
        ck "${v} empty falls back to the default" \
          "${defaults.${v}}" "$(sed -n 's/^${v}=//p' out)"
      '')
      names}

    # ------------------------------------------- exactly these, and no others
    #
    # **Spelled here rather than read from `defaults`, and that is the one place
    # in this file where two copies is the right answer.** Every case above
    # takes its variable and its expected value from the same attribute set
    # `host/wrap.nix` builds the text from, which is what stops the suite
    # agreeing with itself about a value; but a *set* read from that same place
    # cannot notice the set changing. What the module path puts in a program's
    # environment is the interface, so a sixth variable — or a dropped one — is
    # a deliberate act that edits this line and writes a case, rather than five
    # generated cases quietly becoming six.
    clean "$plain" >out 2>err
    ck "the wrapper supplies exactly these and no others" \
      "CAPSULE_ALLOWLIST_DIR CAPSULE_POLICY_DIR CAPSULE_PROFILE_DIR CAPSULE_REPO CAPSULE_STATE" \
      "$(sed -n 's/^\(CAPSULE_[A-Z_]*\)=.*/\1/p' out | sort | tr '\n' ' ' | sed 's/ $//')"

    # ------------------------------------------------------------- the argv
    #
    # `exec … "$@"`, so a wrapper is not a place arguments get re-split. The
    # front end passes `--capsule <name> --profile <name>` through here, and
    # `capsule-brief`'s spec and `capsule <name> ssh <cmd>` are how a value with
    # a space arrives.
    clean "$plain" --capsule c --profile 'two words' >out 2>err
    ck "arguments cross the wrapper" 4 "$(sed -n 's/^argc=//p' out)"
    ckt "  unsplit" grep -qx 'arg=\[two words\]' out

    # ---------------------------------------------------------- the escaping
    #
    # One shell, so one level of `%q` (CLAUDE.md's escaping rule at the count of
    # one): nix builds this text and the wrapper's own shell reads it, and the
    # value never reaches a second parse. A host that keeps its profiles under
    # such a path is not this one, but the wrapper is built from `lib.mkOption`
    # values and nothing here refuses one. This is the case the double-`%q`
    # mutation lands on, and the only one that can — see `spaced`.
    clean "$spaced" >out 2>err
    ck "a declared path with a space arrives whole" \
      "${spaced.profileDir}" "$(sed -n 's/^CAPSULE_PROFILE_DIR=//p' out)"
    ck "  and the override still beats it" \
      /from/the/caller \
      "$(clean env CAPSULE_PROFILE_DIR=/from/the/caller "$spaced" | sed -n 's/^CAPSULE_PROFILE_DIR=//p')"

    [ "$fail" = 0 ] || exit 1
    cp "$log" $out
    cat $out
  ''
