# What the two devshell VM verbs do with argv — `ISS-002`.
#
# The third kind of check (CLAUDE.md) over `host/vm-name.nix`, which is a
# *library*: what a suite can run is the fragment spliced into something with a
# `main`, and here the two shipped programs already are that. So both subjects
# are the store paths the devshell hands a human, never a second render — which
# is also what makes this suite fail if only one of them is rewired.
#
# The one thing tying `vm` to this host is its last line, `exec nix run`, and it
# is reached by exactly one case below. Everything else is a refusal that lands
# before it, which is the point: the fix is the ordering, not the messages.
# `vm-stop`'s tie is a running VMM, so nothing here goes past its argv.
#
# Both rules for writing a case apply. The reason is asserted and not only the
# status — `vm --help` exiting 0 while making `.vm/--help/` is the bug itself, so
# every refusal also asserts that no state was invented. And each was watched
# going red against the programs as they shipped before this: `--help` created
# the directory, `--nope` created one too, and `vm a b` ran the first argument.
{
  pkgs,
  # `vm` and `vm-stop` as the devshell installs them.
  vm,
  vm-stop,
}:
pkgs.runCommand "capsule-vm-cases" {} ''
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

  # A root of this suite's own, so `.vm/` is a thing that either appeared or did
  # not. `vm` reads `CAPSULE_ROOT` before `$PWD`, which is the same knob a human
  # running a capsule out of a checkout uses.
  export CAPSULE_ROOT=$PWD/root
  mkdir -p "$CAPSULE_ROOT"

  # `nix` is not in `vm`'s `runtimeInputs` — it is the host's, resolved from
  # PATH — so a stub is what lets the one non-refusing case run to its last line
  # and say where it stood and what it asked for.
  mkdir -p stub
  {
    echo '#!/bin/sh'
    echo 'echo "cwd $PWD" >"$NIX_LOG"'
    echo 'echo "argv $*" >>"$NIX_LOG"'
  } >stub/nix
  chmod +x stub/nix
  export PATH=$PWD/stub:$PATH NIX_LOG=$PWD/nixlog

  # Whether the run left anything behind. `.vm/` and not `.vm/<name>`: the bug
  # made a directory named after the argument, and a suite that looked for one
  # name would pass for the next mistake.
  litter() { [ -e "$CAPSULE_ROOT/.vm" ] && echo yes || echo no; }

  # ------------------------------------------------------ asking for the usage
  #
  # `ISS-002` as found: the exit status was already 0 and the state directory was
  # already there.
  rc=0; ${vm}/bin/vm --help >out 2>err || rc=$?
  ck "vm --help is a question, not a name" 0 "$rc"
  ckt "  answered on stdout" grep -q '^usage: vm <name>' out
  ck "  and nothing was created" no "$(litter)"

  rc=0; ${vm}/bin/vm -h >out 2>err || rc=$?
  ck "the short form is the same question" 0 "$rc"
  ckt "  with the same answer" grep -q '^usage: vm <name>' out
  ck "  and nothing was created" no "$(litter)"

  # ----------------------------------------------------------- no name at all
  #
  # Unchanged behaviour, pinned because it is the one refusal that predates the
  # fix and the usage now comes from a fragment that could drop it.
  rc=0; ${vm}/bin/vm >out 2>err || rc=$?
  ck "vm with no name still refuses" 1 "$rc"
  ckt "  on stderr, since it is an error" grep -q '^usage: vm <name>' err
  ck "  and nothing was created" no "$(litter)"

  # -------------------------------------------------------- an option, not a name
  rc=0; ${vm}/bin/vm --nope >out 2>err || rc=$?
  ck "an unknown option is refused" 2 "$rc"
  ckt "  naming the option and not the flake" grep -q 'vm: not an option: --nope' err
  ck "  and nothing was created" no "$(litter)"

  # ------------------------------------------------------------ more than one
  #
  # Silently running the first argument is how `vm capsule --foo` becomes a VM
  # boot nobody asked for.
  rc=0; ${vm}/bin/vm capsule hello >out 2>err || rc=$?
  ck "two arguments are refused" 2 "$rc"
  ckt "  saying how many arrived" grep -q 'one name, and this is 2 arguments' err
  ck "  and nothing was created" no "$(litter)"
  ck "  and nix was never asked" no "$([ -e $NIX_LOG ] && echo yes || echo no)"

  # ----------------------------------------------------- a name that is a path
  #
  # `.vm/$name` is a path built from the argument, so a name carrying a
  # separator writes outside the state directory.
  rc=0; ${vm}/bin/vm ../elsewhere >out 2>err || rc=$?
  ck "a name that is a path is refused" 2 "$rc"
  ckt "  as a name and not as a missing attribute" grep -q 'vm: not a VM name: ' err
  ck "  and nothing was created" no "$(litter)"
  ckt "  least of all above the root" test ! -e "$CAPSULE_ROOT/../elsewhere"

  # ------------------------------------------------------------- a real name
  #
  # The only case that reaches the last line. A slot letter rather than
  # `capsule`, so what the run asks nix for is the argument and not a default
  # that happens to match.
  rc=0; ${vm}/bin/vm c >out 2>err || rc=$?
  ck "a declared name runs" 0 "$rc"
  ckt "  under its own state directory" test -d "$CAPSULE_ROOT/.vm/c"
  ckt "  which is where the runner stood" grep -qx "cwd $CAPSULE_ROOT/.vm/c" "$NIX_LOG"
  ckt "  and the attribute is the name it was given" \
    grep -qx "argv run $CAPSULE_ROOT#c" "$NIX_LOG"

  # ------------------------------------------------- the other consumer
  #
  # `vm-stop` never made a directory, so its half of `ISS-002` was only ever the
  # wrong answer to a right question: `--help` went looking for a VMM. Nothing
  # here gets past argv, which is the whole of what the fragment owns.
  rc=0; ${vm-stop}/bin/vm-stop --help >out 2>err || rc=$?
  ck "vm-stop --help is a question too" 0 "$rc"
  ckt "  naming itself, not its sibling" grep -q '^usage: vm-stop <name>' out

  rc=0; ${vm-stop}/bin/vm-stop >out 2>err || rc=$?
  ck "vm-stop with no name refuses" 1 "$rc"
  ckt "  on stderr" grep -q '^usage: vm-stop <name>' err

  rc=0; ${vm-stop}/bin/vm-stop --nope >out 2>err || rc=$?
  ck "vm-stop refuses an option" 2 "$rc"
  ckt "  by its own name" grep -q 'vm-stop: not an option: --nope' err

  [ "$fail" = 0 ] || exit 1
  cp "$log" $out
  cat $out
''
