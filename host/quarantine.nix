# Where a capsule's collected exhibit lives, host-side — one definition.
#
# `capsule-collect` writes it and `capsule-adopt` reads it, and until the second
# of those existed the convention was a `let` binding inside the git channel with
# a note saying not to spell it twice. Two programs is where a note stops being
# enough: **anything built at two call sites needs one construction, not two
# careful ones** (CLAUDE.md), and a path convention is built at a call site the
# same way a program is.
#
# `perimeter/default.nix` defines the same two variables and deliberately still
# does, because it may not import anything host-shaped — that is what keeps a
# seatbelt or VM shape able to reuse it (docs/plan-b-other-jails.md). So this
# collapses two of the three copies and leaves the one that has a reason. Change
# this, change that.
#
# Shell fragments rather than values, because none of it is known at eval:
# `$capsule` is a run-time argument (NOTES item 20) and `CAPSULE_STATE` belongs
# to the process — the module path wraps its copies with the host's own state
# directory (host/services.nix), the devshell path falls through to the
# checkout's `.vm/host`, and neither is a nix value. Every consumer here has
# `$capsule` in scope before it uses any of this, because the transport fragment
# is the first thing in all of them.
rec {
  # Sets `root` and `state`. `CAPSULE_ROOT` is the checkout, `CAPSULE_STATE` the
  # directory this host keeps per-capsule state in — a wrapped program on `$PATH`
  # has the second and must not derive it from `$PWD`, which is the trap the
  # module's `wrap` exists for.
  fragment = ''
    root="''${CAPSULE_ROOT:-''${MICROVM_SPIKE_ROOT:-$PWD}}"
    state="''${CAPSULE_STATE:-$root/.vm/host}"
  '';

  # The bare repository a capsule's collect fetches into, as a shell expression.
  #
  # The capsule names its own quarantine (NOTES item 20): whatever a capsule is
  # called is what its refs and its quarantine are called, so there is no second
  # identity to pass around and nothing to keep in step.
  #
  # `…Of` takes the shell expression holding a name, because **one program reads
  # two capsules' quarantines**: `capsule-brief` puts capsule `a`'s collected
  # state into capsule `b` (NOTES item 35), so the source is an argument and the
  # destination is `$capsule`. The bare forms are that function at `$capsule`,
  # which is what every other consumer means — one definition, not a second
  # careful one.
  repoOf = name: ''"$state/collect/${name}.git"'';
  repo = repoOf "$capsule";

  # Under which ref a collected half lands. Host-authored, always: the guest
  # chooses what is *in* its refs and never where they land (NOTES item 18), and
  # that stays true only while every consumer derives these from one place.
  #
  # `heads/` and `state/` are siblings rather than the second nested under the
  # first — a guest branch literally named `state` would otherwise be a
  # directory/file ref-lock collision, loud but timed by the guest (NOTES item
  # 32).
  # Named for the halves rather than for the path segments, because `state` is
  # also the shell variable `fragment` sets and one of those two readings has to
  # give way.
  codeRefsOf = name: ''refs/capsule/${name}/heads'';
  stateRefsOf = name: ''refs/capsule/${name}/state'';
  codeRefs = codeRefsOf "$capsule";
  stateRefs = stateRefsOf "$capsule";

  # An opaque identifier an operator typed, on its way to the end of a ref or of
  # a path. Bounded to `[A-Za-z0-9._-]+` — the same bound item 32 puts on an
  # assignment's unit token, for the same reason: such a name may identify an
  # instance and may never widen a perimeter. `git update-ref` would refuse a
  # malformed ref anyway, and nothing would refuse a malformed directory; both
  # are caught here, at the end that has the argument in argv and before a round
  # trip rather than after one.
  #
  # `value` is the shell expression holding it and `shown` is what the operator
  # actually typed, because the two differ once one flag carries two tokens
  # (`--state a:implementation`) and a refusal that quotes the wrong one sends
  # the reader looking in the wrong place.
  checkToken = value: shown: ''
    case ${value} in
      "" | *[!A-Za-z0-9._-]*)
        echo "''${0##*/}: ${shown} — that names one link of a capsule's chain, or" >&2
        echo "  the capsule itself, and it goes on the end of a ref and of a path." >&2
        echo "  So it is [A-Za-z0-9._-]+: no slash, no '..', nothing that could" >&2
        echo "  name a different ref or a different directory." >&2
        exit 1
        ;;
    esac
  '';
  checkStage = checkToken ''"$stage"'' "'--stage $stage'";
}
