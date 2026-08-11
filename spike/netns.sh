#!/usr/bin/env bash
#
# Spike: does "a netns per capsule" hold? (PLAN_C.md, "Netns per capsule")
#
# Models two capsules with *identical* addressing, each in its own network
# namespace, plus a simulated guest that already has root and is trying to get
# out. No VM and no firecracker: the claim under test is about the namespace, so
# a veth pair stands in for the tap.
#
#   capspk-g<i>   "guest"    spk-gst<i>  10.98.0.2/30  02:00:00:00:99:02
#         |                      (identical in both capsules — that is the point)
#   capspk-cap<i> "capsule"  spk-tap<i>  10.98.0.1/30     <- stands in for the tap
#                            spk-out<i>  10.100.<i>.2/30  <- the proxy's way out
#   capspk-wan    "upstream" spk-wan<i>  10.100.<i>.1/30
#                            spk-up      10.101.0.2/30    <- stage 2 only
#   root ns                  spk-rt      10.101.0.1/30    <- stage 2 only
#
# Stage 1 lives entirely in its own namespaces — the root namespace has no
# interface, no route and no sysctl in it — and answers the whole question.
# Stage 2 (--internet) hangs the upstream namespace off the host with forwarding
# and a masquerade rule, both restored on exit, to prove real egress works and
# to find what it costs.
#
# Two deliberate choices, both learned the hard way:
#
#   - The guest link is 10.98.0.0/30, *not* the live capsule's 10.99.0.0/30.
#     Reusing it meant the root namespace held a connected route to the real
#     guest, so replies to the simulated one went to the running VM instead and
#     two results were wrong in opposite directions. The preflight below refuses
#     to start if anything collides.
#   - The upstream namespace is given a route back to capsule 0's guest. That is
#     the most permissive upstream there could be, on purpose: with a return
#     path available, a "blocked" result can only mean the capsule namespace
#     blocked it. Without one, every negative passes for the wrong reason.
#
# Throwaway: delete this and its flake entry once PLAN_C settles the question.
#
# Run: sudo spike-netns [--internet]

# Deliberately no errexit: half these tests are supposed to fail.

WANT_INTERNET=0
[ "${1:-}" = "--internet" ] && WANT_INTERNET=1

NSCAP=(capspk-cap0 capspk-cap1)
NSGST=(capspk-g0 capspk-g1)
NSWAN=capspk-wan
NFT_TABLE=capspk-nat
GUEST_NET=10.98.0.0/30
FORWARD_SAVED=""
UPLINK=""

[ "$(id -u)" = 0 ] || {
  echo "spike-netns: needs root (ip netns)" >&2
  exit 1
}

# Refuse rather than produce wrong answers: an overlapping route in the root
# namespace silently redirects this spike's replies to whatever really owns the
# address — which, with a capsule running, is a live guest.
for net in "$GUEST_NET" 10.100.0.0/16 10.101.0.0/30; do
  if ip route show | grep -qF "${net%%/*}"; then
    echo "spike-netns: the root namespace already has a route near $net:" >&2
    ip route show | grep -F "${net%%/*}" >&2
    echo "spike-netns: refusing — results would be meaningless." >&2
    exit 1
  fi
done

cleanup() {
  local ns
  for ns in "${NSCAP[@]}" "${NSGST[@]}" "$NSWAN"; do
    ip netns del "$ns" 2>/dev/null
  done
  ip link del spk-rt 2>/dev/null
  nft delete table ip "$NFT_TABLE" 2>/dev/null
  [ -n "$FORWARD_SAVED" ] && sysctl -q -w "net.ipv4.ip_forward=$FORWARD_SAVED"
  echo
  echo "cleaned up."
}
trap cleanup EXIT

# ---------------------------------------------------------------- test harness

PASSED=0
FAILED=0
RESULTS=()

# check <name> <ok|deny> <cmd...>  — "deny" means the command must fail
check() {
  local name=$1 expect=$2 got
  shift 2
  if "$@" >/dev/null 2>&1; then got=ok; else got=deny; fi
  if [ "$got" = "$expect" ]; then
    RESULTS+=("PASS  $name")
    PASSED=$((PASSED + 1))
  else
    RESULTS+=("FAIL  $name — expected $expect, got $got")
    FAILED=$((FAILED + 1))
  fi
}

# Findings, not pass/fail: they record which way the world turns out to be.
observe() {
  local name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    RESULTS+=("NOTE  $name: reachable")
  else
    RESULTS+=("NOTE  $name: blocked")
  fi
}

nsping() { ip netns exec "$1" ping -c1 -W2 -n "$2"; }
nstcp() { ip netns exec "$1" timeout 5 bash -c "exec 3<>/dev/tcp/$2/$3"; }

# --------------------------------------------------------------------- set-up

echo "== building two capsules with identical addressing =="
ip netns add "$NSWAN" || exit 1
ip -n "$NSWAN" link set lo up
# The upstream does not forward either, so cross-capsule traffic has to be
# blocked by something we can point at rather than by an accident of routing.
ip netns exec "$NSWAN" sysctl -q -w net.ipv4.ip_forward=0

for i in 0 1; do
  cap=${NSCAP[$i]}
  gst=${NSGST[$i]}
  ip netns add "$cap" || exit 1
  ip netns add "$gst" || exit 1
  ip -n "$cap" link set lo up
  ip -n "$gst" link set lo up

  # The namespace's own forwarding switch. This is the control the whole shape
  # rests on, and unlike the host's global one it is nobody else's.
  ip netns exec "$cap" sysctl -q -w net.ipv4.ip_forward=0
  ip netns exec "$cap" sysctl -q -w net.ipv4.conf.all.forwarding=0

  # Stand-in for the tap: capsule <-> guest.
  ip link add "spk-tap$i" type veth peer name "spk-gst$i" || exit 1
  ip link set "spk-tap$i" netns "$cap"
  ip link set "spk-gst$i" netns "$gst"
  # Identical address *and* identical MAC in both capsules. If this errors, the
  # one-image argument dies right here.
  ip -n "$cap" addr add 10.98.0.1/30 dev "spk-tap$i"
  ip -n "$gst" link set "spk-gst$i" address 02:00:00:00:99:02
  ip -n "$gst" addr add 10.98.0.2/30 dev "spk-gst$i"
  ip -n "$cap" link set "spk-tap$i" up
  ip -n "$gst" link set "spk-gst$i" up

  # The proxy's way out. Per-capsule, because it is the one thing that cannot be
  # identical: the upstream has a single routing table.
  ip link add "spk-out$i" type veth peer name "spk-wan$i" || exit 1
  ip link set "spk-out$i" netns "$cap"
  ip link set "spk-wan$i" netns "$NSWAN"
  ip -n "$cap" addr add "10.100.$i.2/30" dev "spk-out$i"
  ip -n "$NSWAN" addr add "10.100.$i.1/30" dev "spk-wan$i"
  ip -n "$cap" link set "spk-out$i" up
  ip -n "$NSWAN" link set "spk-wan$i" up
  ip netns exec "$cap" ip route add default via "10.100.$i.1"

  # The guest already has root and has added the route the design says it can.
  # Every "blocked" below is against an adversary that has done this.
  ip netns exec "$gst" ip route add default via 10.98.0.1
done

# The return path that makes the negatives mean something. Capsule 0 only —
# identical guest addressing means the upstream could not hold a second one
# anyway, which is itself the point: nothing upstream can name a guest.
ip netns exec "$NSWAN" ip route add "$GUEST_NET" via 10.100.0.2
echo "   two namespaces, both holding 10.98.0.1/30, both guests at 10.98.0.2"
echo "   upstream holds a route back to capsule 0's guest"

# --------------------------------------------------------------- stage 1 tests

echo "== stage 1: the namespaces only; the root ns has nothing in it =="

check "guest reaches its own capsule's tap address" ok \
  nsping capspk-g0 10.98.0.1
check "capsule-local process reaches its upstream" ok \
  nsping capspk-cap0 10.100.0.1
check "guest with a default route cannot reach the upstream" deny \
  nsping capspk-g0 10.100.0.1
check "upstream with a route to the guest still cannot reach it" deny \
  ip netns exec "$NSWAN" ping -c1 -W2 -n 10.98.0.2
check "guest cannot reach the other capsule's upstream link" deny \
  nsping capspk-g0 10.100.1.1
check "guest cannot reach the other capsule's inside address" deny \
  nsping capspk-g0 10.100.1.2

# Weak host model, one scope down: 10.100.0.2 is a local address of the capsule
# namespace, so a packet arriving on the tap is INPUT there, not forward. Same
# class as the host-side mistake PLAN_C now documents — if this is reachable,
# services in the namespace must bind explicitly and the namespace wants an
# input drop on its own egress veth.
observe "guest -> its own capsule's *egress* address (10.100.0.2)" \
  nsping capspk-g0 10.100.0.2

# The control: the sysctl is what is doing the work, not luck or a missing
# route. If this pair does not flip, nothing above is evidence of anything.
ip netns exec capspk-cap0 sysctl -q -w net.ipv4.ip_forward=1
check "control: with ip_forward=1 in the capsule ns, the guest DOES get out" ok \
  nsping capspk-g0 10.100.0.1
ip netns exec capspk-cap0 sysctl -q -w net.ipv4.ip_forward=0
check "control: back to 0, blocked again" deny \
  nsping capspk-g0 10.100.0.1

# (DNS is a stage 2 question: with nothing routing in stage 1, a resolver
# failure would prove nothing.)

# --------------------------------------------------------------- stage 2 tests

if [ "$WANT_INTERNET" = 1 ]; then
  echo "== stage 2: real egress (mutates host forwarding + nft, restored on exit) =="
  UPLINK=$(ip -o route show default | awk '{print $5; exit}')
  [ -n "$UPLINK" ] || {
    echo "spike-netns: no default route; skipping stage 2" >&2
    exit 1
  }

  ip link add spk-up type veth peer name spk-rt || exit 1
  ip link set spk-up netns "$NSWAN"
  ip -n "$NSWAN" addr add 10.101.0.2/30 dev spk-up
  ip -n "$NSWAN" link set spk-up up
  ip addr add 10.101.0.1/30 dev spk-rt
  ip link set spk-rt up
  ip netns exec "$NSWAN" ip route add default via 10.101.0.1
  # The upstream now has to forward: it is the aggregation point for every
  # capsule's proxy. Note what that re-enables — see the last observation.
  ip netns exec "$NSWAN" sysctl -q -w net.ipv4.ip_forward=1
  # Reply routing, and the host firewall's reverse-path check, both need this.
  ip route add 10.100.0.0/16 via 10.101.0.2 dev spk-rt

  FORWARD_SAVED=$(cat /proc/sys/net/ipv4/ip_forward)
  sysctl -q -w net.ipv4.ip_forward=1
  nft -f - <<EOF
table ip $NFT_TABLE {
  chain post {
    type nat hook postrouting priority srcnat;
    ip saddr 10.100.0.0/16 oifname "$UPLINK" masquerade
  }
}
EOF
  echo "   uplink $UPLINK, host ip_forward was $FORWARD_SAVED"

  check "proxy-side process reaches the internet" ok \
    nstcp capspk-cap0 1.1.1.1 80
  check "guest still cannot, with everything upstream forwarding" deny \
    nstcp capspk-g0 1.1.1.1 80
  check "capsule ns resolves against an explicit reachable resolver" ok \
    ip netns exec capspk-cap0 timeout 5 dig +short @1.1.1.1 example.com

  # The host's resolver stub lives on the *root* namespace's loopback, and
  # loopback is per-namespace — so a capsule namespace inherits an
  # /etc/resolv.conf naming 127.0.0.53 with nothing behind it. tinyproxy does
  # its own DNS, and the design's claim is that guest lookups inherit the host's
  # resolver chain (resolved -> stubby -> ControlD). This is where that claim
  # either survives the move or needs /etc/netns/<ns>/resolv.conf.
  observe "capsule ns resolves via the host's own /etc/resolv.conf" \
    ip netns exec capspk-cap0 timeout 5 dig +short example.com

  # Whatever aggregates the capsules' egress is a shared segment, and a shared
  # segment that forwards is a capsule-to-capsule path. Not guest-to-guest —
  # this is proxy-to-proxy — but it is the netns shape's version of the
  # cross-capsule problem, and it wants an explicit drop between the upstream's
  # capsule-facing links.
  observe "capsule 0 -> capsule 1's inside address, via the shared upstream" \
    nsping capspk-cap0 10.100.1.2
fi

# ---------------------------------------------------------------------- report

echo
echo "== results =="
printf '%s\n' "${RESULTS[@]}"
echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" = 0 ] || exit 1
