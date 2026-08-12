#!/usr/bin/env bash
#
# Probe: does the *perimeter* survive the move into a namespace?
# (docs/plan-c-multi-capsule.md, "Netns per capsule"; docs/status.md, "Egress
# under netns is unproven")
#
# The last unverified claim in the netns shape, and the only one left that is
# security-shaped. `probe/netns.sh` proved the confinement with veths and a
# simulated guest, and `probe/netns-boot.sh` proved firecracker boots with its
# tap inside a namespace — but neither has ever had a proxy in it. Both
# deliberately refuse to say anything about egress: netns-boot's namespace has
# no upstream at all, so a denial there would pass for the wrong reason, and
# netns.sh's stage 2 reached the internet with a bare `curl` rather than through
# tinyproxy and an allowlist.
#
# So this one boots the real capsule, joins the real `capsule-proxy` to its
# namespace, and asks the guest to get out — once to a host the allowlist
# permits and once to a host it does not. Everything downstream of it (the
# per-instance proxy units, `host/perimeter-check.nix` rewritten around the
# namespace's own ip_forward) is written against a live host and a fail-closed
# guard, where each iteration costs a rebuild; this costs a run.
#
# Like `probe/netns-boot.sh` and for the same reason, it breaks the rule about
# borrowing live addressing: the thing under test is the real guest image, which
# has net.nix baked into it. Everything the probe *adds* is on addressing of its
# own (10.100/16, 10.101/30), and it refuses to start on an overlap.
#
#   root ns            eg-rt      10.101.0.1/30   forwards + masquerades
#                      routes 10.100.0.0/16 and the guest via 10.101.0.2
#   cap-egress ns      eg-up      10.101.0.2/30   the aggregator: every
#                      eg-wan0    10.100.0.1/30   capsule's proxy gets out
#                      eg-wan1    10.100.1.1/30   through here, and this is
#                                                 where the drops live
#   cap-capsule ns     vm-capsule 10.99.0.1/30    <- the real tap, real /30
#                      eg-out0    10.100.0.2/30   <- the proxy's way out
#                      capsule-proxy, bound to the tap address
#                      firecracker, as you, with the real volume
#   guest              10.99.0.2, no default route, no resolver
#   cap-peer ns        eg-out1    10.100.1.2/30   a second capsule, VM-less:
#                                                 it exists to be unreachable
#
# Three claims, each with the control that makes it evidence rather than luck:
#
#   1. the guest gets out through the proxy, and only to the allowlist;
#   2. the guest cannot get out any other way — and the control proves it is the
#      namespace's ip_forward doing that, by turning it on and watching the wall
#      fall over;
#   3. a capsule cannot use the aggregator to reach its sibling or the host's own
#      networks, with the same flush-and-retry control.
#
# The upstream is given a route back to the guest and the host masquerades the
# guest's address too, both on purpose: that is the most permissive upstream
# there could be, so a "blocked" result can only mean the capsule namespace
# blocked it. Without a return path every negative passes for the wrong reason —
# the trap probe/netns.sh paid for twice.
#
# No figures: this round's bar is a proof, not a price. What would be worth
# measuring — throughput through the proxy with a forwarding hop and NAT under
# it — is a figure of the internet rather than of the shape.
#
# DNS is the one thing here that needs a host-side edit and cannot be faked. The
# host's resolver stub is on the *root* namespace's loopback, and loopback is
# per-namespace, so a capsule namespace inherits an /etc/resolv.conf naming
# 127.0.0.53 with nothing behind it. The designed fix is `DNSStubListenerExtra=`
# on the capsule-facing address plus /etc/netns/<ns>/resolv.conf; the probe
# writes the second half itself, detects whether the first half is in place, and
# falls back to a public resolver with a NOTE if it is not — a fallback that
# silently loses the host's DoT hop, which is exactly why it is recorded rather
# than defaulted to.
#
# Run: sudo probe-netns-egress    (from the repo, so $PWD/.vm is the VM's state)
#
# Takes a couple of minutes: a build, a boot, and a clean shutdown. Needs an ssh
# identity the guest authorises — `sudo` strips SSH_AUTH_SOCK, so the harness
# finds the agent itself and refuses before booting anything if there is none.
#
# `probe/harness.sh` is concatenated ahead of this by flake.nix, along with the
# values it takes from net.nix and target.nix: TAP, HOST_ADDR, GUEST_ADDR,
# PREFIX, VM, PROXY_PORT, PROXY and ALLOWLIST are set there, not here.

# Deliberately no errexit: several of these tests are supposed to fail.

PROG=probe-netns-egress
NS="cap-$VM"
NSWAN=cap-egress
NSPEER=cap-peer

# The probe's own addressing, never the capsule's. CAP_OUT is inside the capsule
# namespace, which is what makes it the weak-host-model question below: a packet
# from the guest arriving on the tap is INPUT there, not forward.
CAP_OUT=10.100.0.2
CAP_GW=10.100.0.1
PEER_OUT=10.100.1.2
PEER_GW=10.100.1.1
WAN_UP=10.101.0.2
ROOT_UP=10.101.0.1
CAP_NET=10.100.0.0/16

NFT_NAT=capeg-nat
NFT_FWD=capeg-fwd
NFT_GUARD=capeg-guard

FORWARD_SAVED=""
UPLINK=""
RESOLVER=""
RUNNER=""
LOG=""
PROXY_STATE=""

need_root "$PROG"
human_from_sudo "$PROG"

ROOT=${CAPSULE_ROOT:-$PWD}
VMDIR="$ROOT/.vm/$VM"
ALLOW="$ROOT/$ALLOWLIST"

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
for ns in "$NS" "$NSWAN" "$NSPEER"; do
  if ip netns list | grep -qw "$ns"; then
    echo "$PROG: namespace $ns is left over — 'ip netns del $ns'." >&2
    exit 1
  fi
done
# An overlapping route in the root namespace sends this probe's replies to
# whatever really owns the address, and two results come back wrong in opposite
# directions. Refuse rather than produce them.
for net in "$CAP_NET" 10.101.0.0/30; do
  if ip route show | grep -qF "${net%%/*}"; then
    echo "$PROG: the root namespace already has a route near $net:" >&2
    ip route show | grep -F "${net%%/*}" >&2
    echo "$PROG: refusing — results would be meaningless." >&2
    exit 1
  fi
done
UPLINK=$(ip -o route show default | awk '{print $5; exit}')
if [ -z "$UPLINK" ]; then
  echo "$PROG: no default route — there is no egress to prove." >&2
  exit 1
fi
if [ ! -r "$ALLOW" ]; then
  echo "$PROG: no allowlist at $ALLOW" >&2
  exit 1
fi

cleanup() {
  if vm_running "$NS" "$VM"; then
    echo
    echo "== shutting the guest down =="
    halt_guest "$NS" "$GUEST_ADDR" "$VM"
  fi
  kill_helpers
  nft delete table ip "$NFT_NAT" 2>/dev/null
  [ -n "$FORWARD_SAVED" ] && sysctl -q -w "net.ipv4.ip_forward=$FORWARD_SAVED"
  # Deleting either end of a veth takes both, and the root-side routes with it.
  ip link del eg-rt 2>/dev/null
  ns_down "$NS"
  ns_down "$NSWAN"
  ns_down "$NSPEER"
  rm -rf "/etc/netns/$NS"
  echo
  echo "cleaned up.${LOG:+ console log: $LOG}"
  [ -n "$PROXY_STATE" ] && echo "proxy log: $PROXY_STATE/tinyproxy.log"
}
trap cleanup EXIT

# --------------------------------------------------------------------- set-up

echo "== namespace $NS, with $TAP created inside it =="
ns_up "$NS" "$TAP" "$HOST_ADDR" "$PREFIX" || exit 1

echo "== the aggregator, and a sibling capsule that only exists to be blocked =="
ip netns add "$NSWAN" || exit 1
ip -n "$NSWAN" link set lo up
# It has to forward: it is the point every capsule's proxy leaves through. Which
# is exactly what makes it a capsule-to-capsule path, and why the drops below
# are not optional (probe/netns.sh found this as an observation).
ip netns exec "$NSWAN" sysctl -q -w net.ipv4.ip_forward=1

ip netns add "$NSPEER" || exit 1
ip -n "$NSPEER" link set lo up
ip netns exec "$NSPEER" sysctl -q -w net.ipv4.ip_forward=0

# capsule -> aggregator, one veth each. This is the one thing that cannot be
# identical across capsules: the aggregator has a single routing table.
ip link add eg-out0 type veth peer name eg-wan0 || exit 1
ip link set eg-out0 netns "$NS"
ip link set eg-wan0 netns "$NSWAN"
ip -n "$NS" addr add "$CAP_OUT/30" dev eg-out0
ip -n "$NSWAN" addr add "$CAP_GW/30" dev eg-wan0
ip -n "$NS" link set eg-out0 up
ip -n "$NSWAN" link set eg-wan0 up
ip netns exec "$NS" ip route add default via "$CAP_GW"

ip link add eg-out1 type veth peer name eg-wan1 || exit 1
ip link set eg-out1 netns "$NSPEER"
ip link set eg-wan1 netns "$NSWAN"
ip -n "$NSPEER" addr add "$PEER_OUT/30" dev eg-out1
ip -n "$NSWAN" addr add "$PEER_GW/30" dev eg-wan1
ip -n "$NSPEER" link set eg-out1 up
ip -n "$NSWAN" link set eg-wan1 up
ip netns exec "$NSPEER" ip route add default via "$PEER_GW"

# aggregator -> host, and the host's half of it.
ip link add eg-up type veth peer name eg-rt || exit 1
ip link set eg-up netns "$NSWAN"
ip -n "$NSWAN" addr add "$WAN_UP/30" dev eg-up
ip -n "$NSWAN" link set eg-up up
ip addr add "$ROOT_UP/30" dev eg-rt
ip link set eg-rt up
ip netns exec "$NSWAN" ip route add default via "$ROOT_UP"

FORWARD_SAVED=$(cat /proc/sys/net/ipv4/ip_forward)
sysctl -q -w net.ipv4.ip_forward=1
ip route add "$CAP_NET" via "$WAN_UP" dev eg-rt
# The return path that makes every denial below mean something: the aggregator
# and the host both know how to reach the guest, and the host will masquerade
# for it. So a guest that cannot get out is being stopped, not merely lost.
ip route add "$GUEST_ADDR/32" via "$WAN_UP" dev eg-rt
ip netns exec "$NSWAN" ip route add "$GUEST_ADDR/32" via "$CAP_OUT"

nft -f - <<EOF
table ip $NFT_NAT {
  chain post {
    type nat hook postrouting priority srcnat;
    ip saddr { $CAP_NET, $GUEST_ADDR } oifname "$UPLINK" masquerade
  }
}
EOF
echo "   uplink $UPLINK, host ip_forward was $FORWARD_SAVED"

# ------------------------------------------------------------------------ DNS
#
# Loopback is per-namespace, so the host's stub on 127.0.0.53 is not in here.
# The designed answer keeps the host's resolver chain (resolved -> stubby ->
# ControlD) rather than dropping to a public resolver: an extra stub address on
# the capsule-facing link, and an /etc/netns/<ns>/resolv.conf naming it. The
# second half is the probe's to write; the first half is a host-config edit, so
# detect it rather than assume it.
mkdir -p "/etc/netns/$NS"
# Asked from where the consumer is — the capsule namespace — and before the
# drops go in, so what it detects is the host, not this probe's own rules.
if ip netns exec "$NS" timeout 5 dig +short +tries=1 "@$ROOT_UP" example.com \
  >/dev/null 2>&1; then
  RESOLVER=$ROOT_UP
  RESULTS+=("NOTE  the host's own resolver answers on $ROOT_UP — the capsule keeps its DoT chain")
else
  RESOLVER=1.1.1.1
  RESULTS+=("NOTE  no host resolver on $ROOT_UP — fell back to $RESOLVER, which LOSES the host's DoT hop.")
  RESULTS+=("NOTE  the shipped shape wants two lines in ~/flakes: DNSStubListenerExtra on the")
  RESULTS+=("NOTE  capsule-facing address, and an input allow for port 53 on that link — the")
  RESULTS+=("NOTE  host firewall covers every interface, including one this repo created.")
fi
echo "nameserver $RESOLVER" >"/etc/netns/$NS/resolv.conf"
echo "   capsule resolver: $RESOLVER"

# --------------------------------------------------------- the drops, and only
#
# Two tables, two scopes, and they answer different questions.
#
# In the aggregator: capsules must not reach each other through the thing that
# aggregates them, and must not reach the host's own networks either. The
# interface-pair rule is a clean wildcard — it matches links, not addresses, so
# it enumerates nothing and a new capsule needs no edit. The resolver is the one
# RFC1918 destination a capsule may have, and it is allowed narrowly (port 53,
# by address) ahead of the broad drop, which is what makes the pair testable:
# DNS works, a ping to the same address does not.
wan_rules() {
  ip netns exec "$NSWAN" nft -f - <<EOF
table ip $NFT_FWD {
  chain forward {
    type filter hook forward priority filter; policy accept;
    ip daddr $RESOLVER udp dport 53 accept
    ip daddr $RESOLVER tcp dport 53 accept
    iifname "eg-wan*" oifname "eg-wan*" drop
    ip saddr $CAP_NET ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } drop
  }
}
EOF
}

# In the capsule namespace: the proxy's way out is a *local* address there, so a
# packet from the guest to it is INPUT and no amount of ip_forward=0 touches it
# (probe/netns.sh, cost 1). Services bind the tap address; anything else
# arriving on the tap is not for the guest.
guard_rules() {
  ip netns exec "$NS" nft -f - <<EOF
table ip $NFT_GUARD {
  chain input {
    type filter hook input priority filter; policy accept;
    iifname "$TAP" ip daddr != $HOST_ADDR drop
  }
}
EOF
}

wan_rules || exit 1
guard_rules || exit 1

# ------------------------------------------------------------- boot, and serve

echo "== building the runner (as $HUMAN) =="
RUNNER=$(capsule_runner "$ROOT" "$VM") || exit 1

LOG="$VMDIR/netns-egress.log"
PROXY_STATE="$VMDIR/netns-egress-proxy"
as_human mkdir -p "$PROXY_STATE" || exit 1

echo "== booting $VM inside $NS =="
capsule_boot "$NS" "$RUNNER" "$VMDIR" "$LOG" || exit 1

# The real program, in the namespace, as the human — the same binary
# host/services.nix runs as a unit and `capsule-host` runs as a child. Its state
# goes beside the console log rather than in .vm/host, so a probe run cannot
# leave the devshell path pointing at a config it did not write.
echo "== capsule-proxy, joined to $NS =="
helper_as_human "$NS" \
  "CAPSULE_ROOT=$ROOT" \
  "CAPSULE_PROXY_STATE=$PROXY_STATE" \
  "CAPSULE_ALLOWLIST=$ALLOW" \
  "$PROXY"

# ------------------------------------------------------------------- the guest
#
# Every question below is asked *of the guest*, over ssh, because the guest is
# the confined party — a ping from the capsule namespace answers a different
# question and would answer it green. bash and /dev/tcp rather than curl or
# ping: the guest's tool set comes from the target's flake and this probe may
# not assume what is in it. Only bash is guaranteed, and /dev/tcp also gives
# tinyproxy's status line verbatim, which is the difference between "refused"
# and "could not resolve" — two outcomes an exit status cannot tell apart.
guest_sh() {
  in_ns_as_human "$NS" timeout 20 ssh "${SSH_OPTS[@]}" "root@$GUEST_ADDR" "$@"
}

# CONNECT, as any HTTPS client through the proxy would.
guest_connect() {
  local target=$1
  guest_sh "exec 3<>/dev/tcp/$HOST_ADDR/$PROXY_PORT; printf 'CONNECT %s:443 HTTP/1.1\r\nHost: %s:443\r\n\r\n' '$target' '$target' >&3; head -1 <&3"
}

# A bare TCP connect: what the guest can do for itself, with no proxy in it.
guest_tcp() { guest_sh "exec 3<>/dev/tcp/$1/$2"; }

is_200() { case $1 in *" 200 "*) return 0 ;; *) return 1 ;; esac; }

# One host the allowlist permits, taken from the allowlist itself — the probe
# does not get to spell a hostname, for the same reason nothing else here does:
# which hosts a target may reach is that target's policy. Anchored plain names
# only; a genuine regex entry is skipped rather than guessed at.
first_allowed() {
  sed -n '/^\^[A-Za-z0-9.\\-]*\$$/{s/[^A-Za-z0-9.-]//g;p;}' "$ALLOW" | head -1
}
ALLOWED_HOST=$(first_allowed)
# Reserved by RFC 2606: it cannot resolve, so a refusal is the filter's doing
# and nothing leaves the host either way.
DENIED_HOST=not-on-the-allowlist.invalid

# ---------------------------------------------------------------------- tests

echo "== stage 1: the capsule comes up, and so does its proxy =="

check "the VMM starts with its tap inside the namespace" ok wait_vm "$NS" "$VM"
if wait_guest "$NS" "$GUEST_ADDR" "$VM"; then ssh_ready=1; else ssh_ready=0; fi
check "the guest boots and answers ssh from inside the namespace" ok \
  test "$ssh_ready" = 1
[ "$ssh_ready" = 1 ] || RESULTS+=("NOTE  ssh says: $(ssh_error "$NS" "$GUEST_ADDR")")
check "capsule-proxy binds the tap address inside the namespace" ok \
  wait_listen "$NS" "$HOST_ADDR" "$PROXY_PORT"
check "the proxy's namespace reaches the internet" ok nstcp "$NS" 1.1.1.1 443
check "and resolves, through the resolver it was given" ok \
  ip netns exec "$NS" timeout 5 dig +short +tries=1 example.com
# The trap this shape has to be designed around rather than discover: the host's
# stub is on the root namespace's loopback and there is no loopback in common.
check "the host's resolver stub is NOT reachable from the namespace" deny \
  ip netns exec "$NS" timeout 5 dig +short +tries=1 @127.0.0.53 example.com

echo "== stage 2: the guest gets out, and only where the allowlist says =="

if [ -n "$ALLOWED_HOST" ]; then
  allowed_line=$(guest_connect "$ALLOWED_HOST" 2>&1 | tr -d '\r' | tail -1)
  check "the guest reaches an allowlisted host through the proxy" ok \
    is_200 "$allowed_line"
  RESULTS+=("NOTE  allowlisted host $ALLOWED_HOST: $allowed_line")
else
  RESULTS+=("NOTE  no plain hostname in $ALLOW — the allowed-host check was skipped")
fi
denied_line=$(guest_connect "$DENIED_HOST" 2>&1 | tr -d '\r' | tail -1)
check "a host off the allowlist is refused" deny is_200 "$denied_line"
# Which refusal it is, is a finding rather than the claim: tinyproxy filtering
# the name gives a 403, and resolving it first would give something else. The
# claim is that the guest does not get there.
RESULTS+=("NOTE  off-allowlist host: $denied_line")

echo "== stage 3: and cannot get out any other way =="

# The adversary is guest root, which is the design's own assumption, so give it
# what guest root can give itself: a default route. Without one every denial
# below would pass for the wrong reason — the trap probe/netns.sh paid for
# twice. It stays until stage 4 is done with it.
# And something to aim at that answers when it is reached: a connect to a port
# nothing listens on fails whatever the namespace does, which is the same
# passing-for-the-wrong-reason in a different disguise.
helper "$NSWAN" socat "TCP-LISTEN:443,bind=$CAP_GW,reuseaddr,fork" /dev/null
wait_listen "$NSWAN" "$CAP_GW" 443

guest_sh "ip route add default via $HOST_ADDR" >/dev/null 2>&1
# `ip route show` exits 0 with nothing to show, so assert on the output.
check "guest root can add the route the design says it can" ok \
  guest_sh "ip route show default | grep -q ."
check "and still cannot reach the internet with it" deny guest_tcp 1.1.1.1 443
check "nor the aggregator its own proxy leaves through" deny \
  guest_tcp "$CAP_GW" 443

# The control: the sysctl is what does the work, not luck, not a missing route
# and not a dead port. If this pair does not flip, nothing above is evidence of
# anything.
ip netns exec "$NS" sysctl -q -w net.ipv4.ip_forward=1
check "control: with ip_forward=1 in the capsule ns, the guest DOES get out" ok \
  guest_tcp 1.1.1.1 443
check "control: and reaches the aggregator's listener" ok guest_tcp "$CAP_GW" 443
ip netns exec "$NS" sysctl -q -w net.ipv4.ip_forward=0
check "control: back to 0, blocked again" deny guest_tcp 1.1.1.1 443
check "control: and the aggregator is gone again" deny guest_tcp "$CAP_GW" 443

echo "== stage 4: the weak host model, one scope down =="

# Forwarding is not involved here and that is the point: the proxy's way out is
# a *local* address of the capsule namespace, so a packet from the guest to it
# is INPUT there. Something listens on it, so a refusal is a refusal rather than
# a closed port.
helper "$NS" socat "TCP-LISTEN:443,bind=$CAP_OUT,reuseaddr,fork" /dev/null
wait_listen "$NS" "$CAP_OUT" 443

check "the guest cannot reach its own capsule's egress address" deny \
  guest_tcp "$CAP_OUT" 443
check "the guest still reaches the proxy on the tap address" ok \
  guest_tcp "$HOST_ADDR" "$PROXY_PORT"
ip netns exec "$NS" nft delete table ip "$NFT_GUARD" 2>/dev/null
check "control: without the input drop, the guest reaches it" ok \
  guest_tcp "$CAP_OUT" 443
guard_rules
check "control: with the drop back, it cannot" deny guest_tcp "$CAP_OUT" 443

guest_sh "ip route del default via $HOST_ADDR" >/dev/null 2>&1

echo "== stage 5: one capsule, one sibling, one shared aggregator =="

check "a capsule cannot reach its sibling through the aggregator" deny \
  nsping "$NS" "$PEER_OUT"
check "a capsule cannot reach the host's own networks either" deny \
  nsping "$NS" "$ROOT_UP"
ip netns exec "$NSWAN" nft delete table ip "$NFT_FWD" 2>/dev/null
check "control: without the aggregator's drops, the sibling is reachable" ok \
  nsping "$NS" "$PEER_OUT"
check "control: and so is the host" ok nsping "$NS" "$ROOT_UP"
wan_rules
check "control: with the drops back, the sibling is gone again" deny \
  nsping "$NS" "$PEER_OUT"

echo "== stage 6: and nothing outside can reach the guest =="

check "the root namespace cannot reach the guest" deny \
  ping -c1 -W2 -n "$GUEST_ADDR"
# The aggregator holds a route to the guest and the host masquerades for it.
# Still nothing: the capsule namespace refuses to carry it either way.
check "the aggregator holds a route to the guest and still cannot reach it" deny \
  nsping "$NSWAN" "$GUEST_ADDR"
check "the sibling capsule cannot reach it" deny nsping "$NSPEER" "$GUEST_ADDR"

# ---------------------------------------------------------------------- report

report || exit 1
