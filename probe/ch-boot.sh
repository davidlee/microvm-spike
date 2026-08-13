#!/usr/bin/env bash
#
# Probe: does the capsule's own image boot under cloud-hypervisor, and how does
# it stop? (docs/spike-cloud-hypervisor.md, Phase 1)
#
# Phase 0 settled by eval that `capsule` and `capsule-ch` are the *same* store
# disk and differ only in their runner. Identical bytes are not a boot, though,
# and the whole reason to run this is that the two claims come apart in exactly
# one place: firecracker's stop is an ssh reboot turned into a VMM exit by
# `reboot=k`, and cloud-hypervisor's runner sets `reboot=t` and offers a real
# ACPI power button instead (NOTES item 14). What a guest `reboot` does to a CH
# VMM — exit, or reset in place and boot again — decides whether `capsule-halt`
# may be pointed at a CH slot at all, and no amount of source-reading is running
# it.
#
# So stage 3 is the point of the probe and it is deliberately *not* all
# assertions: the reboot's outcome is unknown ahead of time, which makes it an
# observation. What is asserted is the thing that must be true either way —
# **some** request makes the VMM exit, and the guest unmounts before it does.
#
#   root ns          nothing: no tap, no route to the guest
#   cap-capsule ns   vm-capsule  10.99.0.1/30   <- created *inside* the ns
#                    cloud-hypervisor, as you, with its tap resolved in here
#   guest            10.99.0.2, the same image every firecracker slot runs
#
# **This probe does not refuse while a module-path slot is running**, and that
# is the one way it differs from `probe/netns-boot.sh`. That probe's
# `any_vm_running` is `pgrep -f microvm@capsule`, which matches every slot on
# the host because one image means one process name — so it reads as "a VM is
# running" when what it means is "this host has capsules". The refusals that
# carry the actual invariant are the other two: the devshell shape is up (a tap
# of that name in the root namespace) and a previous run of this probe is left
# over (the namespace, and any VMM inside it). Both are asked below. Everything
# else here is namespace-scoped — `vm_pids`, `wait_vm`, `kill_vm` — and the
# guard cannot see this VMM at all, since both of its limbs are keyed on
# *declared* slots (host/guard.nix). A running slot is untouched by this.
#
# Run: sudo probe-ch-boot        (from the repo, so $PWD/.vm is the VM's state)
#
# Needs an ssh identity the guest authorises, found before anything boots — see
# `human_ssh_identity` in the harness. `sudo` strips SSH_AUTH_SOCK.

# Deliberately no errexit: several of these tests are supposed to fail.

PROG=probe-ch-boot
# The flake attribute is not the VM: `capsule-ch` builds a cloud-hypervisor
# runner for the guest whose hostname — and therefore whose process name, and
# therefore whose namespace-scoped identity — is still `capsule`.
ATTR="capsule-ch"
NS="cap-$VM"
RUNNER=""
LOG=""

need_root "$PROG"
human_from_sudo "$PROG"

ROOT=${CAPSULE_ROOT:-$PWD}
VMDIR="$ROOT/.vm/$VM"
# The hypervisor's control socket, relative to the runner's cwd, which is what
# `capsule_boot` cds into.
API="$VMDIR/$VM.sock"

# ------------------------------------------------------------------- refusals

human_ssh_identity "$PROG"

if ip link show "$TAP" >/dev/null 2>&1; then
  echo "$PROG: $TAP exists in the root namespace — the devshell shape is up." >&2
  echo "$PROG: 'capsule-net down' first; two links of that name is two answers." >&2
  exit 1
fi
if ip netns list | grep -qw "$NS"; then
  echo "$PROG: namespace $NS is left over — 'ip netns del $NS'." >&2
  exit 1
fi

cleanup() {
  if vm_running "$NS" "$VM"; then
    echo
    echo "== shutting the guest down =="
    # Whatever stage 3 found, this is the teardown that works for firecracker
    # and it degrades to a kill. A CH VMM that ignores an ssh reboot is left to
    # SIGTERM, which is a power cut on a volume holding nothing but a probe's
    # boot — acceptable here and nowhere near a slot.
    halt_guest "$NS" "$GUEST_ADDR" "$VM"
  fi
  kill_helpers
  ns_down "$NS"
  echo
  echo "cleaned up.${LOG:+ console log: $LOG}"
}
trap cleanup EXIT

# --------------------------------------------------------------------- set-up

echo "== namespace $NS, with $TAP created inside it =="
# `multi_queue`, which is the first thing this probe found: cloud-hypervisor
# opens the tap with one queue per vCPU and a single-queue tap fails the boot
# outright. Run 1 died here (docs/spike-cloud-hypervisor.md).
ns_up "$NS" "$TAP" "$HOST_ADDR" "$PREFIX" multi_queue || exit 1

echo "== building the $ATTR runner (as $HUMAN) =="
RUNNER=$(capsule_runner "$ROOT" "$ATTR") || exit 1
observe_runner() { case "$RUNNER" in *cloud-hypervisor*) return 0 ;; *) return 1 ;; esac; }

LOG="$VMDIR/ch-boot.log"

echo "== booting $VM inside $NS =="
BOOT_T0=$(now)
capsule_boot "$NS" "$RUNNER" "$VMDIR" "$LOG" || exit 1

# ---------------------------------------------------------------------- tests

echo "== stage 1: the same image, a different VMM (up to two minutes) =="

# A runner named after the other hypervisor would make every result below true
# of firecracker, which is the one way this probe could pass for the wrong
# reason.
check "the runner built is a cloud-hypervisor runner" ok observe_runner
check "the VMM starts with its tap inside the namespace" ok wait_vm "$NS" "$VM"
if wait_guest "$NS" "$GUEST_ADDR" "$VM"; then ssh_ready=1; else ssh_ready=0; fi
check "the guest boots and answers ssh from inside the namespace" ok \
  test "$ssh_ready" = 1
[ "$ssh_ready" = 1 ] || RESULTS+=("NOTE  ssh says: $(ssh_error "$NS" "$GUEST_ADDR")")
check "the guest's NIC is live on the namespaced tap" ok nsping "$NS" "$GUEST_ADDR"
# A figure only if it is a figure *of* something: run 1 recorded "boot to ssh:
# 38.56 s" for a VMM that died in three milliseconds, which is the wait's own
# patience wearing a boot's name — the same mistake probe/freshness.sh's
# teardown made once (harness `halt_guest`). Not a figure to quote against
# firecracker's either: one boot, and the comparable number is a cold baseline
# (docs/probes.md).
if [ "$ssh_ready" = 1 ]; then
  measure "boot to ssh" "$(since "$BOOT_T0")" s
else
  RESULTS+=("NOTE  boot to ssh: never answered — $(since "$BOOT_T0") s is the wait, not a boot")
fi

echo "== stage 2: and is unreachable from outside it =="

check "the root namespace cannot see the tap" deny ip link show "$TAP"
check "the root namespace cannot reach the guest" deny \
  ping -c1 -W2 -n "$GUEST_ADDR"
check "the root namespace cannot reach the guest's ssh port" deny \
  timeout 3 bash -c "exec 3<>/dev/tcp/$GUEST_ADDR/22"

echo "== stage 3: how it stops — the reason this probe exists =="

check "the hypervisor's control socket exists" ok test -S "$API"

# **Nothing below means anything without a live VMM**, and run 1 proved that the
# hard way: with the boot dead, `vmm_gone` answered "gone" instantly, so the
# power-button check passed, the reboot observation reported an exit, and three
# figures timed an absence — a stage that agreed with whatever it was asked
# because there was nothing there to disagree. One honest failure instead, and
# the rest of the stage skipped: a probe that cannot ask its question says so
# (CLAUDE.md — a denial-only test passes for the wrong reason).
check "a VMM is running to ask a stop of" ok vm_running "$NS" "$VM"
if ! vm_running "$NS" "$VM"; then
  RESULTS+=("NOTE  stage 3 skipped — the stop question needs a guest to ask it of")
  report
  exit 1
fi

# How long to wait for a VMM to exit before calling it survived. Generous: a
# clean shutdown unmounts a volume first, and the firecracker path takes a
# couple of seconds.
vmm_gone() {
  local n=$1
  for _ in $(seq "$n"); do
    vm_running "$NS" "$VM" || return 0
    sleep 0.5
  done
  return 1
}

# ---- request 1: a guest reboot, which is what capsule-halt asks for
#
# Unknown outcome, so it is recorded rather than asserted. `reboot=t` is a
# triple fault; whether cloud-hypervisor treats that as an exit or as a reset it
# should honour by booting again is the question.
REBOOT_T0=$(now)
guest_ssh "$NS" "$GUEST_ADDR" root 'systemctl --no-block reboot' >/dev/null 2>&1
if vmm_gone 60; then
  reboot_exits=1
  measure "VMM exit after a guest reboot" "$(since "$REBOOT_T0")" s
  RESULTS+=("NOTE  a guest reboot exits the VMM — capsule-halt's request ports as-is")
else
  reboot_exits=0
  RESULTS+=("NOTE  a guest reboot does NOT exit the VMM — capsule-halt is firecracker-shaped")
  if wait_guest "$NS" "$GUEST_ADDR" "$VM"; then
    RESULTS+=("NOTE  the guest reset in place and answers ssh again")
  else
    RESULTS+=("NOTE  the VMM survived and the guest does not answer — neither shape")
  fi
fi

# The evidence that a stop was clean rather than a power cut, and it is the same
# thing a human reads off the console: the guest unmounting before it goes.
check "the guest unmounted its volume on the way down" ok \
  grep -qi "unmounting\|unmounted" "$LOG"

# ---- request 2: the ACPI power button, which is what microvm.nix would send
#
# Independent of the first, so it needs a live VMM: if the reboot exited, boot
# again. This is the mechanism a CH slot's `ExecStop` would use
# (`lib/runners/cloud-hypervisor.nix`), so it is asserted rather than observed.
if [ "$reboot_exits" = 1 ]; then
  echo "== rebooting for the power-button test =="
  BOOT_T0=$(now)
  capsule_boot "$NS" "$RUNNER" "$VMDIR" "$LOG" || exit 1
  wait_vm "$NS" "$VM"
  if wait_guest "$NS" "$GUEST_ADDR" "$VM"; then
    measure "second boot to ssh" "$(since "$BOOT_T0")" s
  else
    RESULTS+=("NOTE  second boot never answered — the power button below is asked of a guest that is not up")
  fi
  # Same rule as the gate above: the second boot is a precondition of the test
  # after it, so it is asserted rather than assumed.
  check "the second boot left a VMM to power off" ok vm_running "$NS" "$VM"
fi

power_button() {
  curl -s --unix-socket "$API" -X PUT http://localhost/api/v1/vm.power-button
}

PB_T0=$(now)
check "the API socket accepts a power button" ok power_button
check "the VMM exits on an ACPI power button" ok vmm_gone 60
measure "VMM exit after a power button" "$(since "$PB_T0")" s
check "the guest unmounted before that exit" ok \
  grep -qi "unmounting\|unmounted" "$LOG"

# ---------------------------------------------------------------------- report

report || exit 1
