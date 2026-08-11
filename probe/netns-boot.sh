#!/usr/bin/env bash
#
# Probe: does firecracker come up with its tap inside a network namespace?
# (PLAN_C.md, "The one thing still unverified")
#
# It is the last unknown in the netns shape, and everything downstream of it —
# one guest image (REQ-450's freshness, REQ-454's two concurrent capsules), the
# forward drop becoming ours instead of the host's — is waiting on the answer.
# `probe/netns.sh` established the namespace behaviour with veths and a
# simulated guest; this one boots the *real* capsule, because reading
# firecracker's source is not running it.
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
# `probe/harness.sh` is concatenated ahead of this by flake.nix, along with the
# values it takes from net.nix and target.nix — TAP, HOST_ADDR, GUEST_ADDR,
# PREFIX, VM and GUEST_REPO are set there, not here.

# Deliberately no errexit: several of these tests are supposed to fail.

PROG=probe-netns-boot
NS="cap-$VM"
SOCKDIR=""
RUNNER=""
LOG=""

need_root "$PROG"

# The VMM must be *your* uid: /dev/kvm by group, the tap by owner, ~/.ssh for
# the guest, and the volume in .vm/ that the devshell path also writes. A probe
# that booted the capsule as root would leave state you cannot use afterwards.
HUMAN=${SUDO_USER:-}
[ -n "$HUMAN" ] || {
  echo "$PROG: run it as 'sudo $PROG' from your own shell — the VMM runs as you" >&2
  exit 1
}
HOME_DIR=$(getent passwd "$HUMAN" | cut -d: -f6)
ROOT=${CAPSULE_ROOT:-$PWD}
VMDIR="$ROOT/.vm/$VM"

# Enter the namespace first, then drop privilege: `ip netns exec` needs
# CAP_SYS_ADMIN and the whole point is that nothing after it does.
human_env=(env "PATH=$PATH" "HOME=$HOME_DIR")
as_human() { runuser -u "$HUMAN" -- "${human_env[@]}" "$@"; }
in_ns_as_human() { ip netns exec "$NS" runuser -u "$HUMAN" -- "${human_env[@]}" "$@"; }

# The same relaxation flake.nix's `guestSsh` makes, for the same reason: the
# guest's host keys live on its volume. Under netns the socket path is the
# identity and this stops being needed — which is one of the things below.
SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o BatchMode=yes
  -o ConnectTimeout=5
)

vm_running() { pgrep -f "microvm@$VM" >/dev/null; }

# ------------------------------------------------------------------- refusals

if ip link show "$TAP" >/dev/null 2>&1; then
  echo "$PROG: $TAP exists in the root namespace — the devshell shape is up." >&2
  echo "$PROG: 'capsule-net down' first; two links of that name is two answers." >&2
  exit 1
fi
if vm_running; then
  echo "$PROG: a microvm is already running — vm-stop first." >&2
  exit 1
fi
if ip netns list | grep -qw "$NS"; then
  echo "$PROG: namespace $NS is left over — 'ip netns del $NS'." >&2
  exit 1
fi

cleanup() {
  if vm_running; then
    echo
    echo "== shutting the guest down =="
    # Clean unmount before anything is killed: the volume holds real work, and
    # firecracker does not exit when the guest halts (CLAUDE.md), so the poweroff
    # and the terminate are two separate steps in that order.
    in_ns_as_human ssh "${SSH_OPTS[@]}" "root@$GUEST_ADDR" \
      'systemctl --no-block poweroff' >/dev/null 2>&1 \
      || echo "   ssh poweroff failed; terminating the VMM instead" >&2
    for _ in $(seq 20); do
      vm_running || break
      sleep 1
    done
    if vm_running; then
      pkill -f -- "microvm@$VM"
      sleep 2
      vm_running && pkill -9 -f -- "microvm@$VM"
    fi
  fi
  kill_helpers
  # Deleting the namespace takes the tap with it — but only once the VMM is
  # gone, or firecracker is left holding a dead fd.
  ip netns del "$NS" 2>/dev/null
  [ -n "$SOCKDIR" ] && rm -rf "$SOCKDIR"
  echo
  echo "cleaned up.${LOG:+ console log: $LOG}"
}
trap cleanup EXIT

# --------------------------------------------------------------------- set-up

echo "== namespace $NS, with $TAP created inside it =="
ip netns add "$NS" || exit 1
ip -n "$NS" link set lo up

# The control the whole shape rests on. Global ip_forward is docker's and
# tailscale's too, which is why the current perimeter has to read it back out of
# the kernel; this one is nobody else's.
ip netns exec "$NS" sysctl -q -w net.ipv4.ip_forward=0
ip netns exec "$NS" sysctl -q -w net.ipv4.conf.all.forwarding=0

# Created in the namespace rather than moved into it: `tap-up` is
# namespace-agnostic, so the host module can put the namespace on that unit too
# and no tap ever moves (PLAN_C, "Plumbing"). Owned by the human because
# firecracker cannot create its own.
ip netns exec "$NS" ip tuntap add dev "$TAP" mode tap user "$HUMAN" || exit 1
# Before the link is up, as capsule-net does it, so the tap never emits a router
# solicitation. Absent entirely if the kernel has no IPv6, hence the tolerance.
ip netns exec "$NS" sysctl -q -w "net.ipv6.conf.$TAP.disable_ipv6=1" 2>/dev/null
ip -n "$NS" addr add "$HOST_ADDR/$PREFIX" dev "$TAP"
ip -n "$NS" link set "$TAP" up

echo "== building the runner (as $HUMAN) =="
RUNNER=$(as_human nix build --no-link --print-out-paths "$ROOT#$VM") || exit 1

as_human mkdir -p "$VMDIR" || exit 1
cd "$VMDIR" || exit 1
LOG="$VMDIR/netns-boot.log"
# Created as the human, so the console log of a probe run is theirs to read and
# delete without sudo.
as_human touch "$LOG"

echo "== booting $VM inside $NS =="
in_ns_as_human "$RUNNER/bin/microvm-run" >"$LOG" 2>&1 &

# ---------------------------------------------------------------------- tests

wait_vm() {
  for _ in $(seq 60); do
    vm_running && return 0
    sleep 0.5
  done
  return 1
}

# ssh, not ping: a guest that answers ICMP has a NIC, a guest that answers ssh
# has booted. Gives up early if the VMM died rather than waiting out the poll.
wait_guest() {
  for _ in $(seq 120); do
    in_ns_as_human ssh "${SSH_OPTS[@]}" "root@$GUEST_ADDR" true >/dev/null 2>&1 \
      && return 0
    vm_running || return 1
    sleep 1
  done
  return 1
}

echo "== stage 1: the boot itself =="

check "the VMM starts with its tap inside the namespace" ok wait_vm
check "the guest boots and answers ssh from inside the namespace" ok wait_guest
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
# ProxyCommand rather than a sudo (PLAN_C, "Plumbing").
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
