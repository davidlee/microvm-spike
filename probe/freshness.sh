#!/usr/bin/env bash
#
# Probe: what does a *fresh* capsule cost, and which of REQ-450's five freshness
# axes does this mechanism actually satisfy? (doctrine IMP-426 P1a.)
#
# The bar for this round is a price, not a proof: every figure below is meant to
# answer "costs about this much, here's the shape, here's what it breaks". Hence
# `measure` alongside `check` — the numbers are the point, and they travel with
# the assertions that say what state produced them.
#
# Three judgement calls are baked in, and they decide what the numbers mean:
#
#   1. **"Usable" means provisioned.** A capsule that boots and answers ssh but
#      holds an empty repository is not one a worker can be given. So
#      time-to-usable is boot + provision, and the two are also reported apart,
#      because only the second scales with the target repo.
#
#   2. **It never touches the operator's volume.** Freshness means creating and
#      destroying volumes; a probe that did that to `.vm/$VM` would be a probe
#      you could run exactly once. This one boots the same guest image against
#      its own state directory and deletes it afterwards (CAPSULE_KEEP=1 to
#      keep it). That is also what makes the warm figure honest: the warm boot
#      is this probe's own cold volume, one halt later.
#
#   3. **The cold *build* is not measured, and cannot be here.** The namespace
#      has no upstream at all, so nothing in the guest can fetch a crate — the
#      first `cargo build` on a fresh volume is the largest cost freshness
#      actually imposes, and measuring it needs the proxy joined to the
#      namespace, i.e. the host module. Recorded as not-measured rather than
#      estimated. The discarded cache is asserted here; its price is not.
#
# Run: sudo probe-freshness [REF]     (REF defaults to the target's branch)
#
# Takes several minutes: two boots, a 32 MiB provision and two shutdowns. It
# needs an ssh identity the guest authorises, for the same reason and with the
# same escape hatches as probe-netns-boot.
#
# `probe/harness.sh` is concatenated ahead of this by flake.nix, along with the
# values it takes from net.nix and target.nix. The boot sequence is the harness's
# too — this probe and probe/netns-boot.sh measure and assert the same shape.

# Deliberately no errexit: several of these tests are supposed to fail.

PROG=probe-freshness
NS="cap-$VM"
SOCKDIR="/run/capsule/$VM"
RUNNER=""
LOG=""
REF=${1:-$DEFAULT_BRANCH}

need_root "$PROG"
human_from_sudo "$PROG"

ROOT=${CAPSULE_ROOT:-$PWD}
# Its own state, never `.vm/$VM`. See judgement call 2.
VMDIR="$ROOT/.vm/$VM-freshness"
VOLUME="$VMDIR/capsule-work.img"
WORK=$(dirname "$GUEST_PATH")

# ------------------------------------------------------------------- refusals

human_ssh_identity "$PROG"

if ip link show "$TAP" >/dev/null 2>&1; then
  echo "$PROG: $TAP exists in the root namespace — the devshell shape is up." >&2
  echo "$PROG: 'capsule-net down' first; two links of that name is two answers." >&2
  exit 1
fi
if vm_running "$VM"; then
  echo "$PROG: a microvm is already running — vm-stop first." >&2
  exit 1
fi
if ip netns list | grep -qw "$NS"; then
  echo "$PROG: namespace $NS is left over — 'ip netns del $NS'." >&2
  exit 1
fi
if ! as_human git -C "$TARGET_PATH" rev-parse --verify --quiet "$REF^{commit}" \
  >/dev/null 2>&1; then
  echo "$PROG: $TARGET_PATH has no commit at '$REF'." >&2
  exit 1
fi

cleanup() {
  if vm_running "$VM"; then
    echo
    echo "== shutting the guest down =="
    halt_guest "$NS" "$GUEST_ADDR" "$VM"
  fi
  kill_helpers
  ns_down "$NS"
  rm -rf "$SOCKDIR"
  if [ -n "${CAPSULE_KEEP:-}" ]; then
    echo
    echo "kept: $VMDIR"
  else
    rm -rf "$VMDIR"
  fi
  echo
  echo "cleaned up.${LOG:+ console log: $LOG}"
}
trap cleanup EXIT

# --------------------------------------------------------------------- set-up

echo "== namespace $NS, with $TAP created inside it =="
ns_up "$NS" "$TAP" "$HOST_ADDR" "$PREFIX" || exit 1

echo "== building the runner (as $HUMAN) =="
RUNNER=$(capsule_runner "$ROOT" "$VM") || exit 1
LOG="$VMDIR/freshness.log"

# The deciding cost of the whole N-capsule question (NOTES item 17): if the
# per-instance values are out of the closure, N capsules pay one image and N
# small runners rather than N blobs. Under netns the guest is bit-identical, so
# this figure is *the* image, once, however many capsules run.
closure_mib() {
  local out
  out=$(as_human nix path-info -S "$1" 2>/dev/null) || return 1
  echo "$out" | awk '{ printf "%.0f", $NF / 1048576 }'
}
if image_mib=$(closure_mib "$RUNNER"); then
  measure "guest image closure, shared by every capsule" "$image_mib" MiB
else
  RESULTS+=("NOTE  guest image closure: nix path-info failed")
fi

# Actual blocks, not the sparse apparent size: the volume is declared 32 GiB and
# that number is meaningless as a per-instance disk cost.
vol_mib() {
  [ -f "$VOLUME" ] || {
    echo 0
    return
  }
  du -B1 "$VOLUME" | awk '{ printf "%.0f", $1 / 1048576 }'
}

# ---------------------------------------------------- stage 1: the cold boot

echo "== stage 1: a capsule from nothing =="

check "no volume exists before the first boot" deny test -f "$VOLUME"

capsule_boot "$NS" "$RUNNER" "$VMDIR" "$LOG" || exit 1
check "the VMM starts" ok wait_vm "$VM"

# One call, timed and asserted on the same result: a figure for a boot that did
# not happen is worse than no figure.
if timed "cold boot to ssh (volume created, mkfs, seed)" \
  wait_guest "$NS" "$GUEST_ADDR" "$VM"; then
  boot_cold=$LAST_SECONDS
  cold_ready=1
else
  boot_cold=$LAST_SECONDS
  cold_ready=0
fi
check "the guest answers ssh" ok test "$cold_ready" = 1
[ "$cold_ready" = 1 ] || {
  RESULTS+=("NOTE  ssh says: $(ssh_error "$NS" "$GUEST_ADDR")")
  report
  exit 1
}

measure "volume after boot, before provision" "$(vol_mib)" MiB

# ------------------------------------------ stage 2: the five freshness axes

echo "== stage 2: which of the five axes hold, on a capsule nothing has used =="

g() { guest_ssh "$NS" "$GUEST_ADDR" agent "$@"; }
g_root() { guest_ssh "$NS" "$GUEST_ADDR" root "$@"; }

# Checkout. The seed makes an empty repository and nothing else: unborn HEAD, no
# files. This is the axis the inversion bought — the base commit is an argument
# to a host command, so a fresh capsule has no history until one is pushed.
check "checkout: the repository exists" ok g test -d "$GUEST_PATH/.git"
check "checkout: HEAD is unborn" deny g git -C "$GUEST_PATH" rev-parse --verify HEAD
check "checkout: the worktree is empty" deny \
  g "find $GUEST_PATH -mindepth 1 -maxdepth 1 ! -name .git | grep -q ."

# Repository. Nothing points anywhere: no remote to fetch from, and no alternates
# pointing at a shared object store — which is REQ-448's "no writable shared
# object store" holding by absence rather than by permission.
check "repository: the guest has no remote" deny \
  g "git -C $GUEST_PATH remote | grep -q ."
check "repository: no alternates to a shared object store" deny \
  g test -e "$GUEST_PATH/.git/objects/info/alternates"

# Runtime. No previous boot survives in the journal — and the interesting half
# is *why*: the guest's root is tmpfs, so the journal is in guest RAM and cannot
# carry a previous capsule's boots whatever the volume holds. Satisfied by the
# mechanism, not by the freshness discipline.
#
# Asked as a pair against `-b -1`, not as a line count. Run 1 counted the lines
# of `journalctl --list-boots` and expected 1; it reported a red on a property
# that almost certainly held, because that listing prints a header. Parsing a
# human-readable table to establish a security-adjacent property is the defect,
# not the off-by-one — and a bare "no previous boot" would pass just as well
# against a journalctl that cannot run at all, hence the `ok` half. The raw
# count rides along as a figure so the next run explains the last one.
check "runtime: the current boot has a journal" ok \
  g_root "journalctl -b 0 -n 1 --no-pager"
check "runtime: no previous boot survives in it" deny \
  g_root "journalctl -b -1 -n 1 --no-pager"
measure "runtime: journalctl --list-boots lines (header included)" \
  "$(g_root 'journalctl --list-boots --no-pager | wc -l' 2>/dev/null || echo '?')"

# Temporary state, and the caches are the load-bearing part: they live on the
# volume deliberately, so a fresh volume discards the build cache. That is
# freshness holding — and it is the cost, not the benefit. See judgement call 3.
check "temporary: /work/tmp is empty" deny \
  g "find $WORK/tmp -mindepth 1 | grep -q ."
for cache in $CACHES; do
  check "temporary: $cache is empty on a fresh volume" deny \
    g "find $WORK/$cache -mindepth 1 | grep -q ."
done

# Process is the fifth axis and it is deliberately *not* a row here. A capsule is
# a separate kernel, so a previous capsule's processes cannot appear in this
# process table under any state of the volume: there is no delta that could
# falsify the reading, and a permanently green row is misleading evidence rather
# than extra assurance (doctrine DEC-189). Recorded, not asserted.
RESULTS+=("NOTE  process: no falsifying delta under a hypervisor — see DEC-189")

# ------------------------------------------- stage 3: provisioning, and usable

echo "== stage 3: what makes it usable — history, over the socket =="

# The designed path rather than a mktemp: the socket path is the capsule's
# identity under netns (docs/plan-c-multi-capsule.md, "Plumbing"), and
# `capsule-provision` is built with a ProxyCommand against exactly this one, so
# this is the real program on the real seam and not an approximation of it.
mkdir -p "$SOCKDIR"
chmod 0755 "$SOCKDIR"
helper "$NS" socat \
  "UNIX-LISTEN:$SOCKDIR/ssh.sock,fork,mode=0600,user=$HUMAN" \
  "TCP:$GUEST_ADDR:22"

wait_sock() {
  for _ in $(seq 30); do
    [ -S "$SOCKDIR/ssh.sock" ] && return 0
    sleep 0.1
  done
  return 1
}
check "the relay's socket is up at the designed path" ok wait_sock

# As the human: capsule-provision is the one thing that reads the real repo, and
# it always runs as them.
if timed "provision (full history, first push)" as_human "$PROVISION" "$REF"; then
  provisioned=1
else
  provisioned=0
fi
provision_s=$LAST_SECONDS
check "provision lands" ok test "$provisioned" = 1

# `updateInstead` only checks out a push to the branch HEAD names, so a provision
# can land history and leave the worktree untouched — silently. Assert the files,
# not the ref.
check "the worktree is populated at the pinned commit" ok \
  g "test -n \"\$(ls -A $GUEST_PATH | grep -v '^\.git$')\""
check "the checkout is clean" ok \
  g "test -z \"\$(git -C $GUEST_PATH status --porcelain)\""

measure "volume after provision" "$(vol_mib)" MiB
measure "time to a usable fresh capsule (boot + provision)" \
  "$(awk -v a="$boot_cold" -v b="$provision_s" 'BEGIN { printf "%.2f", a + b }')" s

# ------------------------------------------ stage 4: teardown, and the warm cost

echo "== stage 4: does it actually go away, and what did freshness cost =="

# The sharp edge this whole stage exists for: firecracker does not exit when the
# guest powers off — it halts the vCPU and keeps the tap, and the next boot dies
# with EBUSY on TUNSETIFF. A freshness claim that does not tear down is measuring
# the wrong thing.
#
# Run 1's 22.68 s here was the harness waiting out a VMM exit that this
# hypervisor never produces, not a teardown cost. `halt_guest` now waits on the
# guest going quiet; discard the earlier figure rather than comparing to it.
timed "teardown (guest halts, then the VMM is terminated)" \
  halt_guest "$NS" "$GUEST_ADDR" "$VM"
check "no VMM process remains" deny vm_running "$VM"
check "the tap survives its VMM" ok ip netns exec "$NS" ip link show "$TAP"

# The assertion that means something: the tap was *released*, not merely present.
# A second attach is the only way to tell, and it is also the warm figure.
capsule_boot "$NS" "$RUNNER" "$VMDIR" "$LOG" || exit 1
check "a second capsule attaches the same tap (no EBUSY)" ok wait_vm "$VM"
if timed "warm boot to ssh (volume already made and provisioned)" \
  wait_guest "$NS" "$GUEST_ADDR" "$VM"; then
  warm_ready=1
else
  warm_ready=0
fi
check "the warm guest answers ssh" ok test "$warm_ready" = 1

if [ "$warm_ready" = 1 ]; then
  measure "the price of freshness, per capsule (cold boot - warm boot)" \
    "$(awk -v a="$boot_cold" -v b="$LAST_SECONDS" 'BEGIN { printf "%.2f", a - b }')" s
  # And the other half of the price, stated as a finding: what a reused volume
  # keeps is exactly what a fresh one throws away.
  check "warm: the checkout survived the halt — a reused volume is not fresh" ok \
    g "test -n \"\$(ls -A $GUEST_PATH | grep -v '^\.git$')\""
fi

RESULTS+=("NOTE  not measured: the first build on a fresh volume — no upstream in this namespace")

# ---------------------------------------------------------------------- report

report || exit 1
