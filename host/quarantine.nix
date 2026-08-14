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
{
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
  repo = ''"$state/collect/$capsule.git"'';

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
  codeRefs = ''refs/capsule/$capsule/heads'';
  stateRefs = ''refs/capsule/$capsule/state'';

  # A stage name goes on the end of a ref, so it is bounded to what a ref may
  # hold — and bounded the same way item 32 bounds an assignment's unit token,
  # for the same reason: an opaque identifier may name an instance and may never
  # widen a perimeter. `git update-ref` would refuse a malformed name anyway;
  # refusing here says *which* argument was wrong, at the end that has it in
  # argv, and before a round trip rather than after one.
  checkStage = ''
    case "$stage" in
      "" | *[!A-Za-z0-9._-]*)
        echo "''${0##*/}: '--stage $stage' — a stage names one link of a capsule's" >&2
        echo "  chain and goes on the end of a ref, so it is [A-Za-z0-9._-]+:" >&2
        echo "  no slash, no '..', nothing that could name a different ref." >&2
        exit 1
        ;;
    esac
  '';
}
