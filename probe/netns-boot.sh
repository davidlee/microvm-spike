#!/usr/bin/env bash
#
# Probe: does firecracker come up with its tap inside a network namespace?
# (docs/plan-c-multi-capsule.md, "The last unknown — run, and it holds")
#
# It was the last unknown in the netns shape, and everything downstream of it —
# one guest image (REQ-450's freshness, REQ-454's two concurrent capsules), the
# forward drop becoming ours instead of the host's — was waiting on the answer.
# `probe/netns.sh` established the namespace behaviour with veths and a
# simulated guest; this one boots the *real* capsule, because reading
# firecracker's source is not running it. Run 2026-08-11: 9 assertions, green
# (doctrine EVD-018). It is kept runnable because it is that evidence.
#
# So, unlike every other probe here, this one deliberately breaks the rule about
# not borrowing live addressing: it uses the real tap name, the real /30 and the
# real volume, because the thing under test is the real guest image, which has
# net.nix baked into it. That is why it refuses to start while the devshell tap
# exists or a VM is running — the two shapes must not be up at once.
#
#   root ns          nothing: no tap, no route to the guest, no way in but the
#                    unix socket below
#   cap-capsule ns   vm-capsule  10.99.0.1/30   <- created *inside* the ns
#                    firecracker, as you, with its tap resolved in here
#                    a socat relay on $SOCKDIR/ssh.sock -> 10.99.0.2:22
#   guest            10.99.0.2, bit-identical to what the tap shape boots
#
# What it does *not* test, on purpose: egress. There is no upstream in the
# namespace at all, so "the guest cannot reach the internet" would pass for the
# wrong reason — the trap probe/netns.sh already paid for twice. Egress under
# netns is stage 2 of that probe plus a proxy joined to the namespace, and it
# belongs with the host module that creates the namespace for real.
#
# The pair that does mean something is here instead: the guest is reachable
# *inside* the namespace and unreachable *outside* it, both asserted, plus the
# unix socket as the only way across.
#
# Boots the real capsule against its real volume, so it shuts the guest down
# over ssh before it kills anything (a killed VMM is a power cut; CLAUDE.md).
#
# Run: sudo probe-netns-boot     (from the repo, so $PWD/.vm is the VM's state)
#
# Takes a couple of minutes: a build, a boot, and a clean shutdown. It needs an
# ssh identity the guest authorises and finds your agent itself — see
# `human_ssh_identity` in the harness, which is there because `sudo` strips
# SSH_AUTH_SOCK and the first run of this probe failed three checks for exactly
# that reason.
#
# `probe/harness.sh` is concatenated ahead of this by flake.nix, along with the
# values it takes from net.nix and target.nix — TAP, HOST_ADDR, GUEST_ADDR,
# PREFIX, VM and GUEST_REPO are set there, not here. The boot sequence itself
# also lives in the harness now, because probe/freshness.sh measures the same
# shape and two copies of it would be two answers.

# Deliberately no errexit: several of these tests are supposed to fail.

PROG=probe-netns-boot
NS="cap-$VM"
SOCKDIR=""
RUNNER=""
LOG=""

need_root "$PROG"
human_from_sudo "$PROG"

ROOT=${CAPSULE_ROOT:-$PWD}
VMDIR="$ROOT/.vm/$VM"

# ------------------------------------------------------------------- refusals

human_ssh_identity "$PROG"

if ip link show "$TAP" >/dev/null 2>&1; then
  echo "$PROG: $TAP exists in the root namespace — the devshell shape is up." >&2
  echo "$PROG: 'capsule-net down' first; two links of that name is two answers." >&2
  exit 1
fi
if any_vm_running "$VM"; then
  echo "$PROG: a microvm is already running — vm-stop first." >&2
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
    halt_guest "$NS" "$GUEST_ADDR" "$VM"
  fi
  kill_helpers
  ns_down "$NS"
  [ -n "$SOCKDIR" ] && rm -rf "$SOCKDIR"
  echo
  echo "cleaned up.${LOG:+ console log: $LOG}"
}
trap cleanup EXIT

# --------------------------------------------------------------------- set-up

echo "== namespace $NS, with $TAP created inside it =="
ns_up "$NS" "$TAP" "$HOST_ADDR" "$PREFIX" || exit 1

echo "== building the runner (as $HUMAN) =="
RUNNER=$(capsule_runner "$ROOT" "$VM") || exit 1

LOG="$VMDIR/netns-boot.log"

echo "== booting $VM inside $NS =="
capsule_boot "$NS" "$RUNNER" "$VMDIR" "$LOG" || exit 1

# ---------------------------------------------------------------------- tests

echo "== stage 1: the boot itself (up to two minutes) =="

check "the VMM starts with its tap inside the namespace" ok wait_vm "$NS" "$VM"
# Run once, assert on the result, and say what went wrong if it did.
if wait_guest "$NS" "$GUEST_ADDR" "$VM"; then ssh_ready=1; else ssh_ready=0; fi
check "the guest boots and answers ssh from inside the namespace" ok \
  test "$ssh_ready" = 1
[ "$ssh_ready" = 1 ] || RESULTS+=("NOTE  ssh says: $(ssh_error "$NS" "$GUEST_ADDR")")
check "the guest's NIC is live on the namespaced tap" ok nsping "$NS" "$GUEST_ADDR"

echo "== stage 2: and is unreachable from outside it =="

check "the root namespace cannot see the tap" deny ip link show "$TAP"
check "the root namespace cannot reach the guest" deny \
  ping -c1 -W2 -n "$GUEST_ADDR"
check "the root namespace cannot reach the guest's ssh port" deny \
  timeout 3 bash -c "exec 3<>/dev/tcp/$GUEST_ADDR/22"

echo "== stage 3: the way in — a unix socket, no privilege =="

# The filesystem is not namespaced, which is what makes this work: the relay
# lives in the namespace, the socket does not, and `just ssh` becomes a
# ProxyCommand rather than a sudo (docs/plan-c-multi-capsule.md, "Plumbing").
SOCKDIR=$(mktemp -d)
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

PROXY_CMD="socat - UNIX-CONNECT:$SOCKDIR/ssh.sock"

# Not `ssh true`: a session that opens and carries nothing would pass while the
# relay dropped every byte. `cat /etc/hostname` rather than `hostname`, which is
# not guaranteed to be in the guest's closure.
sock_hostname() {
  [ "$(as_human ssh "${SSH_OPTS[@]}" -o "ProxyCommand=$PROXY_CMD" \
    "root@$GUEST_ADDR" 'cat /etc/hostname')" = "$VM" ]
}

# The transport the git channel rides, over the socket rather than the tap —
# NOTES item 18 lists exactly this as unmeasured. `ls-remote --symref` is also
# the check `capsule-provision` makes before it pushes, so this is that call and
# not an approximation of it. An unprovisioned guest advertises no symref and
# still exits 0: the claim here is the transport, not the contents.
sock_git() {
  as_human env \
    GIT_SSH_COMMAND="ssh ${SSH_OPTS[*]} -o ProxyCommand='$PROXY_CMD'" \
    git ls-remote --symref "$GUEST_REPO" HEAD
}

check "the relay's socket appears in the root namespace" ok wait_sock
check "ssh crosses it as the human, unprivileged" ok sock_hostname
check "git speaks over the same socket" ok sock_git

# ---------------------------------------------------------------------- report

report || exit 1
