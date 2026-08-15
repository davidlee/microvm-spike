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
# borrowing live addressing in exactly one place: the thing under test is the
# real guest image, which has net.nix baked into it. Everything the probe *adds*
# is the harness's fabric, on names and addressing `flake.nix`'s `probeFabric`
# refuses at eval to share with `capsules.nix` — which this file is the reason
# for. It said this same sentence while adding `eg-rt` at 10.101.0.1 with a route
# for 10.100.0.0/16, all three of them the live aggregator's, because the module
# copied its map from here after the shape was verified (NOTES item 38).
#
#   root ns            pr-rt      10.111.0.1/30   forwards + masquerades
#                      routes 10.110.0.0/16 and the guest via 10.111.0.2
#   probe-egress ns    pr-up      10.111.0.2/30   the aggregator: every
#                      pr-wan0    10.110.0.1/30   capsule's proxy gets out
#                      pr-wan1    10.110.1.1/30   through here, and this is
#                                                 where the drops live
#   cap-capsule ns     vm-capsule 10.99.0.1/30    <- the real tap, real /30
#                      pr-out0    10.110.0.2/30   <- the proxy's way out
#                      capsule-proxy, bound to the tap address
#                      firecracker, as you, with the real volume
#   guest              10.99.0.2, no default route, no resolver
#   probe-peer ns      pr-out1    10.110.1.2/30   a second capsule, VM-less:
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
# PREFIX, VM, PROXY_PORT, PROXY, ALLOWLIST and SEALED_ALLOWLIST are set there,
# not here.

# Deliberately no errexit: several of these tests are supposed to fail.

PROG=probe-netns-egress
NS="cap-$VM"

# The two indices this probe carves out of the harness fabric. CAP_OUT is inside
# the capsule namespace, which is what makes it the weak-host-model question
# below: a packet from the guest arriving on the tap is INPUT there, not forward.
CAP_IDX=0
PEER_IDX=1
CAP_OUT=$(eg_out "$CAP_IDX")
CAP_GW=$(eg_gw "$CAP_IDX")
PEER_OUT=$(eg_out "$PEER_IDX")

RUNNER=""
LOG=""
PROXY_STATE=""

need_root "$PROG"
human_from_sudo "$PROG"

ROOT=${CAPSULE_ROOT:-$PWD}
VMDIR="$ROOT/.vm/$VM"
ALLOW="$ROOT/$ALLOWLIST"
# The other policy's file, for stage 2b. Named in the builder like the first, so
# a probe states which policies it is asserting under and never spells a filename.
SEALED="$ROOT/$SEALED_ALLOWLIST"

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
for ns in "$NS" "$EG_NS" "$NSPEER"; do
  if ip netns list | grep -qw "$ns"; then
    echo "$PROG: namespace $ns is left over — 'ip netns del $ns'." >&2
    exit 1
  fi
done
egress_preflight "$PROG" || exit 1
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
  egress_down
  ns_down "$NS"
  ns_down "$NSPEER"
  # As netns-boot: the state directory is the real capsule's, so nothing here is
  # this probe's to remove and the logs always survive.
  release_state -- ${LOG:+"$LOG"}
  [ -n "$PROXY_STATE" ] && echo "  proxy log: $PROXY_STATE/tinyproxy.log"
  return 0
}
trap cleanup EXIT

# --------------------------------------------------------------------- set-up

echo "== namespace $NS, with $TAP created inside it =="
ns_up "$NS" "$TAP" "$HOST_ADDR" "$PREFIX" || exit 1

echo "== the aggregator, and a sibling capsule that only exists to be blocked =="
egress_up "$GUEST_ADDR" || exit 1

ip netns add "$NSPEER" || exit 1
ip -n "$NSPEER" link set lo up
ip netns exec "$NSPEER" sysctl -q -w net.ipv4.ip_forward=0

egress_attach "$NS" "$CAP_IDX" || exit 1
egress_attach "$NSPEER" "$PEER_IDX" || exit 1

# The return path that makes every denial below mean something: the aggregator
# and the host both know how to reach the guest, and the host masquerades for it.
# So a guest that cannot get out is being stopped, not merely lost. One guest, so
# it is available here and is not in `probe/two-capsules.sh`.
egress_guest_return "$GUEST_ADDR" "$CAP_IDX"

echo "   uplink $EG_WAN_IF, host ip_forward was $EG_FORWARD_SAVED"

egress_resolver "$NS"
echo "   capsule resolver: $RESOLVER"

# Two tables, two scopes, and they answer different questions — the aggregator's
# drops between capsules, and the capsule's own input drop on the tap. Both are
# the harness's, because two probes assert them.
egress_rules || exit 1
capsule_guard_rules "$NS" "$TAP" "$HOST_ADDR" || exit 1

# ------------------------------------------------------------- boot, and serve

echo "== building the runner (as $HUMAN) =="
RUNNER=$(capsule_runner "$ROOT" "$VM") || exit 1

LOG="$VMDIR/netns-egress.log"
PROXY_STATE="$VMDIR/netns-egress-proxy"
as_human mkdir -p "$PROXY_STATE" || exit 1

echo "== booting $VM inside $NS =="
capsule_boot "$NS" "$RUNNER" "$VMDIR" "$LOG" || exit 1

echo "== capsule-proxy, joined to $NS =="
proxy_up "$NS" "$ROOT" "$PROXY_STATE" "$ALLOW"

# ------------------------------------------------------------------- the guest
#
# Every question below is asked *of the guest*, over ssh, because the guest is
# the confined party — a ping from the capsule namespace answers a different
# question and would answer it green. `guest_connect` and `is_200` are the
# harness's, since `probe/two-capsules.sh` asks the same question of two guests
# at once; the bare TCP connect is this probe's, because only this one gives the
# guest a default route to try it with.
guest_sh() {
  in_ns_as_human "$NS" timeout 20 ssh "${SSH_OPTS[@]}" "root@$GUEST_ADDR" "$@"
}

# A bare TCP connect: what the guest can do for itself, with no proxy in it.
guest_tcp() { guest_sh "exec 3<>/dev/tcp/$1/$2"; }

ALLOWED_HOST=$(first_allowed "$ALLOW")
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
  allowed_line=$(guest_connect "$NS" "$GUEST_ADDR" "$ALLOWED_HOST")
  check "the guest reaches an allowlisted host through the proxy" ok \
    is_200 "$allowed_line"
  RESULTS+=("NOTE  allowlisted host $ALLOWED_HOST: $allowed_line")
else
  RESULTS+=("NOTE  no plain hostname in $ALLOW — the allowed-host check was skipped")
fi
denied_line=$(guest_connect "$NS" "$GUEST_ADDR" "$DENIED_HOST")
check "a host off the allowlist is refused" deny is_200 "$denied_line"
# Which refusal it is, is a finding rather than the claim: tinyproxy filtering
# the name gives a 403, and resolving it first would give something else. The
# claim is that the guest does not get there.
RESULTS+=("NOTE  off-allowlist host: $denied_line")

echo "== stage 2b: the same guest, under the other policy =="
#
# What a policy being *selected* rather than shared has to mean at the wire: the
# same guest, the same host, a different declared allowlist, and the answer
# changes. Both directions, which is this file's rule — a denial after a restart
# could be a proxy that simply stopped working, so the round only counts if the
# same host is allowed again when the policy is put back.
#
# What it does **not** prove, and the gap is worth naming rather than implying:
# two capsules differing *at the same time*. That needs two guests, which is
# `probe/two-capsules.sh`'s shape and not this one's. This proves the selection
# reaches the wire; it does not prove two selections coexist.
if [ -n "$ALLOWED_HOST" ]; then
  check "the proxy can be stopped" ok proxy_down "$NS" "$PROXY_STATE"
  check "and comes back under the sealed policy" ok proxy_up "$NS" "$ROOT" "$PROXY_STATE" "$SEALED"
  sealed_line=$(guest_connect "$NS" "$GUEST_ADDR" "$ALLOWED_HOST")
  check "a host the build policy allows is refused under sealed" deny \
    is_200 "$sealed_line"
  RESULTS+=("NOTE  under sealed, $ALLOWED_HOST: $sealed_line")

  check "the proxy can be stopped again" ok proxy_down "$NS" "$PROXY_STATE"
  check "and comes back under the build policy" ok proxy_up "$NS" "$ROOT" "$PROXY_STATE" "$ALLOW"
  restored_line=$(guest_connect "$NS" "$GUEST_ADDR" "$ALLOWED_HOST")
  check "and the same host is allowed once the policy is put back" ok \
    is_200 "$restored_line"
  RESULTS+=("NOTE  build again, $ALLOWED_HOST: $restored_line")
else
  RESULTS+=("NOTE  no plain hostname in $ALLOW — the two-policy round was skipped")
fi

echo "== stage 3: and cannot get out any other way =="

# The adversary is guest root, which is the design's own assumption, so give it
# what guest root can give itself: a default route. Without one every denial
# below would pass for the wrong reason — the trap probe/netns.sh paid for
# twice. It stays until stage 4 is done with it.
# And something to aim at that answers when it is reached: a connect to a port
# nothing listens on fails whatever the namespace does, which is the same
# passing-for-the-wrong-reason in a different disguise.
helper "$EG_NS" socat "TCP-LISTEN:443,bind=$CAP_GW,reuseaddr,fork" /dev/null
wait_listen "$EG_NS" "$CAP_GW" 443

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
capsule_guard_down "$NS"
check "control: without the input drop, the guest reaches it" ok \
  guest_tcp "$CAP_OUT" 443
capsule_guard_rules "$NS" "$TAP" "$HOST_ADDR"
check "control: with the drop back, it cannot" deny guest_tcp "$CAP_OUT" 443

guest_sh "ip route del default via $HOST_ADDR" >/dev/null 2>&1

echo "== stage 5: one capsule, one sibling, one shared aggregator =="

check "a capsule cannot reach its sibling through the aggregator" deny \
  nsping "$NS" "$PEER_OUT"
check "a capsule cannot reach the host's own networks either" deny \
  nsping "$NS" "$EG_PEER_ADDR"
egress_rules_down
check "control: without the aggregator's drops, the sibling is reachable" ok \
  nsping "$NS" "$PEER_OUT"
check "control: and so is the host" ok nsping "$NS" "$EG_PEER_ADDR"
egress_rules
check "control: with the drops back, the sibling is gone again" deny \
  nsping "$NS" "$PEER_OUT"

echo "== stage 6: and nothing outside can reach the guest =="

check "the root namespace cannot reach the guest" deny \
  ping -c1 -W2 -n "$GUEST_ADDR"
# The aggregator holds a route to the guest and the host masquerades for it.
# Still nothing: the capsule namespace refuses to carry it either way.
check "the aggregator holds a route to the guest and still cannot reach it" deny \
  nsping "$EG_NS" "$GUEST_ADDR"
check "the sibling capsule cannot reach it" deny nsping "$NSPEER" "$GUEST_ADDR"

# ---------------------------------------------------------------------- report

report || exit 1
