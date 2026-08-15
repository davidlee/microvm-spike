#!/usr/bin/env bash
#
# Probe: can two capsules run at once, are they actually independent, and what
# does the second one cost? (doctrine IMP-426 P1b, REQ-454.)
#
# REQ-454 wants a candidate verified in a *separate* fresh capsule from the one
# that produced it, which is why `red-team.md` RT-1 asks for it and why CPT-002
# ranks it highest in the round: a verifier sharing a capsule with the worker it
# checks is not a verifier. So the question is not "does a second VM boot" — it
# is whether two capsules are independent in the four ways that would let one
# stand in judgement on the other, and what the pair costs.
#
# The four, each asserted rather than argued:
#
#   1. **Addressing.** Both guests are the same image at the same address in
#      their own namespace. The test is a marker file: the address that would
#      name your sibling names *you*. Under identical addressing a capsule has
#      no way to spell its sibling, which is stronger than a dropped route.
#   2. **Storage.** Two volumes, and neither guest can see the other's marker.
#   3. **History.** The two are provisioned from *different* base commits from
#      one image — the transport inversion's whole premise (NOTES item 17: the
#      base commit had to leave the closure, or N capsules means N images).
#   4. **Lifecycle.** Halting one leaves the other answering. This is the
#      assertion that forced `probe/harness.sh` to stop identifying a VMM by
#      name: with two capsules on one image, `pkill -f microvm@capsule` is a
#      power cut for the sibling and reads as a clean teardown while doing it.
#
# It also collects from both, because attribution is half of REQ-454: a verdict
# that cannot be tied to the capsule that produced it is not evidence. The two
# quarantines land under this probe's own state, not the operator's.
#
# Judgement calls, as in probe/freshness.sh:
#
#   1. **Real capsules, real size.** Two guests at target.nix's declared RAM.
#      A shrunken second capsule would measure a capsule nobody runs, and the
#      cost is the point of the exercise.
#   2. **Its own state, never `.vm/capsule`.** Two state directories under
#      `.vm/pair-*`, removed afterwards (CAPSULE_KEEP=1 to keep them).
#   3. **One runner, deliberately.** Both capsules boot the same store path,
#      because that is the shape being priced. It is also what makes the
#      identity problem real instead of hypothetical — and what this probe found:
#      the host programs were built per socket, so a second capsule had no way
#      in. One set of them now, `--capsule <name>` per call.
#
# Run: sudo probe-two-capsules [REF_A] [REF_B]
#
# The refs default to the target repo's HEAD and its parent — any two commit-ish
# will do, they only have to differ. Not the guest's branch: the target declares
# no branch any more, and `$WORK_BRANCH` is the other thing called one here.
#
# `probe/harness.sh` is concatenated ahead of this by flake.nix along with the
# values it takes from net.nix and target.nix, and it carries the boot fixture
# these two capsules share.

# Deliberately no errexit: several of these tests are supposed to fail.

PROG=probe-two-capsules
NS_A="cap-$NAME_A"
NS_B="cap-$NAME_B"
RUNNER=""
# Two base commits, from the *target repo*, defaulting to its HEAD and its
# parent: the target declares no branch any more, and the guest's
# `$WORK_BRANCH` — what both capsules land on and what their collected refs are
# named after below — is the other thing called a branch here.
REF_A=${1:-HEAD}
REF_B=${2:-"HEAD~1"}

need_root "$PROG"
human_from_sudo "$PROG"

ROOT=${CAPSULE_ROOT:-$PWD}
DIR_A="$ROOT/.vm/$NAME_A"
DIR_B="$ROOT/.vm/$NAME_B"
LOG_A="$DIR_A/two-capsules.log"
LOG_B="$DIR_B/two-capsules.log"
STATE="$ROOT/.vm/pair-host"

# ------------------------------------------------------------------- refusals

human_ssh_identity "$PROG"

if ip link show "$TAP" >/dev/null 2>&1; then
  echo "$PROG: $TAP exists in the root namespace — the devshell shape is up." >&2
  echo "$PROG: 'capsule-net down' first; two links of that name is two answers." >&2
  exit 1
fi
# Host-wide, not namespace-scoped: this one is asking whether the *other* shape
# is up, and the whole point below is that a namespace-scoped question cannot
# see it.
if any_vm_running "$VM"; then
  echo "$PROG: a microvm is already running — vm-stop first." >&2
  exit 1
fi
for ns in "$NS_A" "$NS_B"; do
  if ip netns list | grep -qw "$ns"; then
    echo "$PROG: namespace $ns is left over — 'ip netns del $ns'." >&2
    exit 1
  fi
done
for ref in "$REF_A" "$REF_B"; do
  if ! as_human git -C "$TARGET_PATH" rev-parse --verify --quiet "$ref^{commit}" \
    >/dev/null 2>&1; then
    echo "$PROG: $TARGET_PATH has no commit at '$ref'." >&2
    exit 1
  fi
done
COMMIT_A=$(as_human git -C "$TARGET_PATH" rev-parse "$REF_A^{commit}")
COMMIT_B=$(as_human git -C "$TARGET_PATH" rev-parse "$REF_B^{commit}")
if [ "$COMMIT_A" = "$COMMIT_B" ]; then
  echo "$PROG: '$REF_A' and '$REF_B' are the same commit — the point is that" >&2
  echo "  two capsules can hold different history from one image." >&2
  exit 1
fi

cleanup() {
  echo
  echo "== shutting both capsules down =="
  halt_guest "$NS_A" "$GUEST_ADDR" "$VM"
  halt_guest "$NS_B" "$GUEST_ADDR" "$VM"
  kill_helpers
  ns_down "$NS_A"
  ns_down "$NS_B"
  rm -rf "$SOCKDIR_A" "$SOCKDIR_B"
  if [ -n "${CAPSULE_KEEP:-}" ]; then
    echo
    echo "kept: $DIR_A $DIR_B $STATE"
  else
    rm -rf "$DIR_A" "$DIR_B" "$STATE"
  fi
  echo
  echo "cleaned up. console logs: $LOG_A $LOG_B"
}
trap cleanup EXIT

# --------------------------------------------------------------------- set-up

echo "== two namespaces, each with its own $TAP at the same address =="
ns_up "$NS_A" "$TAP" "$HOST_ADDR" "$PREFIX" || exit 1
ns_up "$NS_B" "$TAP" "$HOST_ADDR" "$PREFIX" || exit 1

# The assertion the whole netns shape rests on, and it is free here: two links of
# the same name at the same address, both up, because they are in different
# namespaces. In one namespace this is EEXIST.
check "both namespaces hold a $TAP at $HOST_ADDR" ok \
  bash -c "ip -n $NS_A addr show $TAP | grep -q $HOST_ADDR &&
           ip -n $NS_B addr show $TAP | grep -q $HOST_ADDR"

echo "== building the runner, once (as $HUMAN) =="
RUNNER=$(capsule_runner "$ROOT" "$VM") || exit 1
RESULTS+=("NOTE  one runner, two capsules: $RUNNER")

# Host memory before anything boots, so the pair's real cost can be separated
# from its declared one. MemAvailable rather than MemFree: the kernel's own
# estimate of what a new workload can have without swapping.
mem_avail_mib() { awk '/^MemAvailable:/ { printf "%.0f", $2 / 1024 }' /proc/meminfo; }
vol_mib() {
  [ -f "$1" ] || {
    echo 0
    return
  }
  du -B1 "$1" | awk '{ printf "%.0f", $1 / 1048576 }'
}
mem_before=$(mem_avail_mib)

# ------------------------------------------------ stage 1: both, at the same time

echo "== stage 1: two capsules, booted together =="

t0=$(now)
capsule_boot "$NS_A" "$RUNNER" "$DIR_A" "$LOG_A" || exit 1
capsule_boot "$NS_B" "$RUNNER" "$DIR_B" "$LOG_B" || exit 1

check "capsule A's VMM starts" ok wait_vm "$NS_A" "$VM"
check "capsule B's VMM starts" ok wait_vm "$NS_B" "$VM"

# Two processes, not one seen twice — and the namespace is what tells them apart,
# since both are `microvm@capsule` running the same store path.
pids_a=$(vm_pids "$NS_A" "$VM" | tr '\n' ' ')
pids_b=$(vm_pids "$NS_B" "$VM" | tr '\n' ' ')
check "the two VMMs are distinct processes" deny \
  bash -c "[ '$pids_a' = '$pids_b' ]"

# The identity finding, as a number rather than an argument: the same name
# matches everything on the host and one thing per namespace. If the two figures
# are ever equal, the scoping is not doing what the teardown below depends on —
# which is why this is reported every run and not only when something fails.
measure "processes matching microvm@$VM, host-wide" \
  "$(pgrep -cf "microvm@$VM" 2>/dev/null || echo 0)"
measure "...and in each capsule's own namespace" \
  "$(vm_pids "$NS_A" "$VM" | wc -l) / $(vm_pids "$NS_B" "$VM" | wc -l)"

# Both clocks run from the same launch, so the second figure is the wall-clock a
# scheduler would actually wait for a pair — not the sum of two boots. They are
# waited on in order, so the first figure is A's boot rather than the earlier of
# the two; if B happened to be quicker, the gap between them understates it.
if wait_guest "$NS_A" "$GUEST_ADDR" "$VM"; then a_ready=1; else a_ready=0; fi
measure "capsule A answers ssh, from launch" "$(since "$t0")" s
if wait_guest "$NS_B" "$GUEST_ADDR" "$VM"; then b_ready=1; else b_ready=0; fi
measure "both capsules answer ssh, from launch" "$(since "$t0")" s

check "capsule A answers ssh" ok test "$a_ready" = 1
check "capsule B answers ssh" ok test "$b_ready" = 1
[ "$a_ready" = 1 ] && [ "$b_ready" = 1 ] || {
  RESULTS+=("NOTE  A says: $(ssh_error "$NS_A" "$GUEST_ADDR")")
  RESULTS+=("NOTE  B says: $(ssh_error "$NS_B" "$GUEST_ADDR")")
  report
  exit 1
}

mem_after=$(mem_avail_mib)
measure "declared guest RAM, per capsule" "$MEM_MIB" MiB
measure "host MemAvailable consumed by both capsules, booted and idle" \
  "$((mem_before - mem_after))" MiB

# --------------------------------------------- stage 2: are they actually apart

echo "== stage 2: identical addressing, and what it makes unaddressable =="

a() { guest_ssh "$NS_A" "$GUEST_ADDR" agent "$@"; }
b() { guest_ssh "$NS_B" "$GUEST_ADDR" agent "$@"; }

# On the volume, so the marker says something about storage as well as about
# addressing — but *outside* the checkout, because `receive.denyCurrentBranch=
# updateInstead` refuses a push into a dirty worktree, and stage 3 pushes. The
# guest's seed makes /work/tmp 1777, which is the one place on the volume the
# agent can write without assuming anything about the layout.
MARKER=$(dirname "$GUEST_PATH")/tmp/marker
check "capsule A takes a marker on its volume" ok a "echo capsule-A > $MARKER"
check "capsule B takes a marker on its volume" ok b "echo capsule-B > $MARKER"

# The load-bearing test. One address, two capsules: from inside A's namespace
# that address is A's guest, and from inside B's it is B's. A capsule cannot
# reach its sibling because it cannot *name* it — the address it would use is its
# own. That is a stronger property than a dropped route, which is a control that
# can be misconfigured; this one has nothing to configure.
marker_a=$(a "cat $MARKER" 2>/dev/null)
marker_b=$(b "cat $MARKER" 2>/dev/null)
check "the shared address reaches A's own guest from A's namespace" ok \
  test "$marker_a" = capsule-A
check "the shared address reaches B's own guest from B's namespace" ok \
  test "$marker_b" = capsule-B
check "the two volumes are not the same volume" deny \
  test "$marker_a" = "$marker_b"

check "the root namespace cannot reach that address at all" deny \
  ping -c1 -W2 -n "$GUEST_ADDR"

# Separate volumes on the host side too, which is what the markers imply and this
# states outright.
check "each capsule has its own volume image" ok \
  bash -c "[ -f '$DIR_A/capsule-work.img' ] && [ -f '$DIR_B/capsule-work.img' ]"

# ------------------------------------ stage 3: two histories, from one image

echo "== stage 3: different base commits, one guest image =="

# The socket path is the capsule's identity on the host side, and this probe is
# what proved it had to be an *argument*: `capsule-provision` used to carry its
# ProxyCommand in its store path, so two capsules needed two programs. One
# program, `--capsule <name>` twice, is what that finding bought.
mkdir -p "$SOCKDIR_A" "$SOCKDIR_B"
chmod 0755 "$SOCKDIR_A" "$SOCKDIR_B"
helper "$NS_A" socat \
  "UNIX-LISTEN:$SOCKDIR_A/ssh.sock,fork,mode=0600,user=$HUMAN" \
  "TCP:$GUEST_ADDR:22"
helper "$NS_B" socat \
  "UNIX-LISTEN:$SOCKDIR_B/ssh.sock,fork,mode=0600,user=$HUMAN" \
  "TCP:$GUEST_ADDR:22"

wait_socks() {
  for _ in $(seq 30); do
    [ -S "$SOCKDIR_A/ssh.sock" ] && [ -S "$SOCKDIR_B/ssh.sock" ] && return 0
    sleep 0.1
  done
  return 1
}
check "both relay sockets are up at their designed paths" ok wait_socks

prov_t0=$(now)
if as_human "$PROVISION" --capsule "$NAME_A" "$REF_A" >/dev/null 2>&1; then pa=1; else pa=0; fi
if as_human "$PROVISION" --capsule "$NAME_B" "$REF_B" >/dev/null 2>&1; then pb=1; else pb=0; fi
measure "both capsules provisioned, in series" "$(since "$prov_t0")" s
check "capsule A provisions over its own socket" ok test "$pa" = 1
check "capsule B provisions over its own socket" ok test "$pb" = 1

head_a=$(a "git -C $GUEST_PATH rev-parse HEAD" 2>/dev/null)
head_b=$(b "git -C $GUEST_PATH rev-parse HEAD" 2>/dev/null)
check "capsule A is at the commit it was pinned to" ok test "$head_a" = "$COMMIT_A"
check "capsule B is at the commit it was pinned to" ok test "$head_b" = "$COMMIT_B"
check "the two capsules hold different history" deny test "$head_a" = "$head_b"

measure "volume, capsule A" "$(vol_mib "$DIR_A/capsule-work.img")" MiB
measure "volume, capsule B" "$(vol_mib "$DIR_B/capsule-work.img")" MiB

# Attribution: a result has to come back naming the capsule that produced it, or
# a verifier's verdict cannot be told from the worker's claim. One program, one
# argument, both directions — the asymmetry this probe found (provision baked its
# transport, collect took a bare directory name) is what closed into `--capsule`.
#
# `COLLECT_ARGS` is the scope and the bound, named in the builder rather than
# inherited: a probe's capsules are not slots, so there is no record and no
# declared default to fill either from (NOTES item 36, item 32). Naming them is
# what the front end would have done, and a probe that had to invent a slot to
# collect would be exercising the front end instead of the program.
check "capsule A collects into its own quarantine" ok \
  as_human env "CAPSULE_STATE=$STATE" "$COLLECT" --capsule "$NAME_A" "${COLLECT_ARGS[@]}"
check "capsule B collects into its own quarantine" ok \
  as_human env "CAPSULE_STATE=$STATE" "$COLLECT" --capsule "$NAME_B" "${COLLECT_ARGS[@]}"

q_a=$(as_human git -C "$STATE/collect/$NAME_A.git" \
  rev-parse "refs/capsule/$NAME_A/$WORK_BRANCH" 2>/dev/null)
q_b=$(as_human git -C "$STATE/collect/$NAME_B.git" \
  rev-parse "refs/capsule/$NAME_B/$WORK_BRANCH" 2>/dev/null)
check "what came out of A is what went into A" ok test "$q_a" = "$COMMIT_A"
check "what came out of B is what went into B" ok test "$q_b" = "$COMMIT_B"

# ---------------------------------------- stage 4: one goes away, one does not

echo "== stage 4: halting one capsule, with the other still running =="

# The hazard this probe was written to catch. Until the harness scoped a VMM to
# its namespace, this teardown killed both — and reported success, because it
# then asked "is a microvm running?" of a host that no longer had either.
timed "teardown of one capsule, sibling up" \
  halt_guest "$NS_A" "$GUEST_ADDR" "$VM"
check "capsule A's VMM is gone" deny vm_running "$NS_A" "$VM"
check "capsule B's VMM survived it" ok vm_running "$NS_B" "$VM"
check "capsule B still answers ssh" ok \
  guest_ssh "$NS_B" "$GUEST_ADDR" agent true
check "A's tap survives its VMM" ok \
  ip netns exec "$NS_A" ip link show "$TAP"
check "and B's tap is still carrying B" ok \
  nsping "$NS_B" "$GUEST_ADDR"

RESULTS+=("NOTE  one set of host programs, --capsule per call: the transport this probe found baked is an argument now")

# ---------------------------------------------------------------------- report

report || exit 1
