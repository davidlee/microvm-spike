# Shared by every probe. Concatenated with one by flake.nix rather than sourced:
# `writeShellApplication` builds a single script, so shellcheck sees the probe
# and its harness as one file, and a probe has no path to a sibling at run time
# anyway.
#
# The order is harness, then flake.nix's `prelude`, then the probe. The harness
# comes first so that it can declare an empty default for every value a prelude
# may inject and the prelude's own assignment still wins — which is what lets the
# egress fabric below name nothing without every probe that never builds one
# tripping shellcheck's SC2154.
#
# The rule these exist to serve (CLAUDE.md): a probe asserts *both* directions,
# because a denial-only test passes for the wrong reason. Hence `check` taking
# the expectation rather than a bare command, and `observe` for the findings
# that record how the world turns out to be rather than pass or fail.

PASSED=0
FAILED=0
RESULTS=()
HELPERS=()
LAST_SECONDS=0

need_root() {
  [ "$(id -u)" = 0 ] || {
    echo "$1: needs root (ip netns)" >&2
    exit 1
  }
}

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

# The third thing a probe can say. `check` gives a verdict and `observe` gives a
# finding; a round whose bar is a price rather than a proof needs a number, and
# a number recorded beside the verdicts travels with the run that produced it
# instead of ending up in someone's notes.
measure() {
  local name=$1 value=$2 unit=${3:-}
  RESULTS+=("MEAS  $name: $value${unit:+ $unit}")
}

# A stopwatch, for the figures `timed` cannot express: two marks off one start,
# which is what a concurrent boot needs — first capsule ready and both capsules
# ready are the same clock read twice.
now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$(now)" 'BEGIN { printf "%.2f", b - a }'; }

# Wall-clock a command and record it. This *times*, it does not test — pair it
# with a `check` on the same thing, or the figure is of an unknown outcome.
# Leaves the elapsed seconds in LAST_SECONDS and returns the command's status.
timed() {
  local name=$1 t0 rc
  shift
  t0=$(now)
  "$@" >/dev/null 2>&1
  rc=$?
  LAST_SECONDS=$(since "$t0")
  measure "$name" "$LAST_SECONDS" s
  return "$rc"
}

nsping() { ip netns exec "$1" ping -c1 -W2 -n "$2"; }
nstcp() { ip netns exec "$1" timeout 5 bash -c "exec 3<>/dev/tcp/$2/$3"; }

# A background helper in a namespace, remembered so cleanup can kill it.
helper() {
  local ns=$1
  shift
  # Quiet: these get SIGTERMed at cleanup and socat announces it, which reads
  # like a failure at the end of an all-green run. A wait_* poll is what
  # actually proves the helper came up.
  ip netns exec "$ns" "$@" >/dev/null 2>&1 &
  HELPERS+=("$!")
}

# The same, for a helper that must not run as root: `capsule-proxy` writes its
# state as whoever starts it, and a probe that left it root-owned would leave
# the devshell path unable to clean up after a run. Extra `VAR=value` arguments
# ahead of the command go to `env`, which is what `human_env` already is.
helper_as_human() {
  local ns=$1
  shift
  ip netns exec "$ns" runuser -u "$HUMAN" -- "${human_env[@]}" "$@" \
    >/dev/null 2>&1 &
  HELPERS+=("$!")
}

kill_helpers() {
  local pid
  for pid in "${HELPERS[@]}"; do
    kill "$pid" 2>/dev/null
  done
}

# Listeners take a moment; poll rather than sleep and hope.
wait_listen() {
  local ns=$1 addr=$2 port=$3
  for _ in $(seq 20); do
    if ip netns exec "$ns" ss -lnt 2>/dev/null | grep -qF "$addr:$port"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# ------------------------------------------- a real capsule, in a namespace
#
# `probe/netns-boot.sh` established this shape and `probe/freshness.sh` measures
# it, so it lives here rather than in either: two copies of a boot sequence are
# two answers the first time one of them is edited.
#
# The VMM must run as the *human*, not as root — /dev/kvm by group, the tap by
# owner, the ssh identity the guest authorises, and the volume in `.vm/` the
# devshell path also writes. A probe that booted the capsule as root would leave
# state its operator cannot use afterwards.

HUMAN=""
HOME_DIR=""
human_env=()

# `sudo` is how a probe gets root; SUDO_USER is how it gets back out again.
human_from_sudo() {
  HUMAN=${SUDO_USER:-}
  [ -n "$HUMAN" ] || {
    echo "$1: run it as 'sudo $1' from your own shell — the VMM runs as you" >&2
    exit 1
  }
  HOME_DIR=$(getent passwd "$HUMAN" | cut -d: -f6)
  human_env=(env "PATH=$PATH" "HOME=$HOME_DIR")
}

as_human() { runuser -u "$HUMAN" -- "${human_env[@]}" "$@"; }

# Enter the namespace first, then drop privilege: `ip netns exec` needs
# CAP_SYS_ADMIN and the whole point is that nothing after it does.
in_ns_as_human() {
  local ns=$1
  shift
  ip netns exec "$ns" runuser -u "$HUMAN" -- "${human_env[@]}" "$@"
}

# The same relaxation flake.nix's `guestSsh` makes, for the same reason: the
# guest's host keys live on its volume, so a *fresh* capsule has fresh keys at
# the same address — and under freshness that fires on every capsule rather than
# occasionally. Under netns the socket path is the identity and this stops being
# needed, which is one of the things these probes are here to establish.
SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o BatchMode=yes
  -o ConnectTimeout=5
)

# An ssh identity, found *before* anything boots. `sudo` strips SSH_AUTH_SOCK,
# and the key a capsule authorises need not have a default filename — on this
# host it is `~/.ssh/id`, which ssh only ever finds through the agent. Without
# one, ssh offers the wrong key, every check that is not a ping fails, and the
# teardown cannot ask the guest to power off either. Cost one probe run.
human_ssh_identity() {
  local prog=$1 sock uid
  uid=$(id -u "$HUMAN")
  if [ -n "${CAPSULE_SSH_KEY:-}" ]; then
    SSH_OPTS+=(-o IdentitiesOnly=yes -i "$CAPSULE_SSH_KEY")
    return 0
  fi
  # Whatever agent this host runs — gcr, gnome-keyring, 1Password, plain
  # ssh-agent. A socket is not namespaced, so it works from inside the capsule
  # namespace unchanged. `ssh-add -l` rather than a bare -S test: an agent
  # holding nothing is the same failure one step later.
  for sock in \
    "${SSH_AUTH_SOCK:-}" \
    "/run/user/$uid/gcr/ssh" \
    "/run/user/$uid/keyring/ssh" \
    "/run/user/$uid/ssh-agent.socket" \
    "$HOME_DIR/.1password/agent.sock"; do
    [ -n "$sock" ] && [ -S "$sock" ] || continue
    as_human env "SSH_AUTH_SOCK=$sock" ssh-add -l >/dev/null 2>&1 || continue
    human_env+=("SSH_AUTH_SOCK=$sock")
    echo "== ssh identity: agent at $sock =="
    return 0
  done
  echo "$prog: no ssh agent with keys, and no CAPSULE_SSH_KEY." >&2
  echo "  sudo strips SSH_AUTH_SOCK, and ~/.ssh/id is not a name ssh tries." >&2
  echo "  sudo --preserve-env=SSH_AUTH_SOCK $prog" >&2
  echo "  sudo CAPSULE_SSH_KEY=\$HOME/.ssh/id $prog" >&2
  exit 1
}

# A capsule namespace. Forwarding off, and this switch is *ours* — the global
# sysctl the current perimeter has to read back out of the kernel is docker's
# and tailscale's too. The tap is created inside rather than moved in, because
# `tap-up` is namespace-agnostic: the host module can put the namespace on that
# unit and then no tap ever moves (docs/plan-c-multi-capsule.md, "Plumbing").
ns_up() {
  local ns=$1 tap=$2 addr=$3 prefix=$4
  ip netns add "$ns" || return 1
  ip -n "$ns" link set lo up
  ip netns exec "$ns" sysctl -q -w net.ipv4.ip_forward=0
  ip netns exec "$ns" sysctl -q -w net.ipv4.conf.all.forwarding=0
  # Owned by the human, because firecracker cannot create its own.
  ip netns exec "$ns" ip tuntap add dev "$tap" mode tap user "$HUMAN" || return 1
  # Before the link is up, as capsule-net does it, so the tap never emits a
  # router solicitation. Absent entirely if the kernel has no IPv6.
  ip netns exec "$ns" sysctl -q -w "net.ipv6.conf.$tap.disable_ipv6=1" 2>/dev/null
  ip -n "$ns" addr add "$addr/$prefix" dev "$tap"
  ip -n "$ns" link set "$tap" up
}

# Takes the tap with it — but only once the VMM is gone, or firecracker is left
# holding a dead fd.
ns_down() { ip netns del "$1" 2>/dev/null; }

# ---------------------------------------------- which VM, and *whose* capsule
#
# Two questions that look like one, and `pgrep -f microvm@capsule` only answers
# the first:
#
#   * is a VM of this name running **anywhere on the host**? A refusal — the
#     devshell shape and a probe's shape must never be up at once.
#   * is **this capsule's** VM running? Every wait, and every teardown.
#
# The second cannot be asked by name, and that is a consequence of the design
# rather than an oversight: the one-image lever means N capsules run the same
# runner from the same store path, so every one of them is `microvm@capsule` in
# the process table. A `pkill -f` on that name is a power cut for the siblings.
#
# The namespace is the identity instead. `ip netns pids` scopes the match to one
# capsule, it costs nothing because the VMM was started in there, and it needs no
# naming scheme, no pidfile and no registry — the thing that isolates the capsule
# is the same thing that names it.
any_vm_running() { pgrep -f "microvm@$1" >/dev/null; }

vm_pids() {
  local ns=$1 vm=$2 pid cmd
  for pid in $(ip netns pids "$ns" 2>/dev/null); do
    # NUL-separated, so it needs translating before a glob can see it.
    cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null) || continue
    case $cmd in
      *"microvm@$vm"*) echo "$pid" ;;
    esac
  done
}

vm_running() { [ -n "$(vm_pids "$1" "$2")" ]; }

wait_vm() {
  local ns=$1 vm=$2
  for _ in $(seq 60); do
    vm_running "$ns" "$vm" && return 0
    sleep 0.5
  done
  return 1
}

# ssh, not ping: a guest that answers ICMP has a NIC, a guest that answers ssh
# has booted. Gives up early if the VMM died rather than waiting out the poll.
wait_guest() {
  local ns=$1 addr=$2 vm=$3
  for _ in $(seq 180); do
    in_ns_as_human "$ns" ssh "${SSH_OPTS[@]}" "root@$addr" true >/dev/null 2>&1 \
      && return 0
    vm_running "$ns" "$vm" || return 1
    sleep 1
  done
  return 1
}

guest_ssh() {
  local ns=$1 addr=$2 user=$3
  shift 3
  in_ns_as_human "$ns" ssh "${SSH_OPTS[@]}" "$user@$addr" "$@"
}

# Why the last attempt failed, when it did. A silent `deny` on ssh is
# unreadable — auth, no route and no sshd all look identical from `check`.
ssh_error() { guest_ssh "$1" "$2" root true 2>&1 | tail -1; }

# Built as the human so the store path and `.vm/` are theirs, not root's.
capsule_runner() { as_human nix build --no-link --print-out-paths "$1#$2"; }

# The runner keeps its mutable state in $PWD, which is why this cds in a
# subshell rather than moving the probe: the probe's own cwd is what
# CAPSULE_ROOT falls back to for the git channel.
capsule_boot() {
  local ns=$1 runner=$2 dir=$3 log=$4
  as_human mkdir -p "$dir" || return 1
  # Created as the human, so a probe run's console log is theirs to read and
  # delete without sudo.
  as_human touch "$log" || return 1
  (cd "$dir" && in_ns_as_human "$ns" "$runner/bin/microvm-run" >"$log" 2>&1 &)
}

# Poweroff over ssh, *then* terminate. The volume holds real work, so the
# unmount has to be clean before anything is killed.
#
# It waits on the **guest**, not on the VMM, and that distinction is the whole
# of it: firecracker does not exit when the guest powers off (CLAUDE.md) — it
# halts the vCPU and keeps the tap. An earlier version polled `vm_running` for
# twenty seconds first, i.e. waited for the one event this hypervisor is
# documented never to produce, and then reported the timeout as the teardown
# cost: 22.68 s, of which 22 was the poll. A figure that measures its own
# patience is worse than no figure.
#
# The guest stops answering when it halts, which is the thing that actually has
# to finish before terminating is safe. Nonzero if the VMM outlives SIGKILL.
#
# Everything here is scoped to one namespace, including the signals. The earlier
# `pkill -f microvm@capsule` was correct only while exactly one capsule could
# exist: with a sibling up it tears that one down too, and it looks like a clean
# teardown while doing it.
# A reboot, not a poweroff, and then a wait for the *VMM* rather than for the
# guest to stop answering. This guest has no power button, so a poweroff halts
# the vCPU and leaves the VMM holding the tap, while `reboot=k` turns the guest's
# reset into a clean VMM exit; and the guest stops answering long before it
# finishes unmounting, so killing on silence is the power cut a stop exists to
# avoid. `host/halt.nix` is where that decision lives (NOTES item 11) — it cannot
# be called from here, since entering the namespace is the caller's job and this
# is the caller.
halt_guest() {
  local ns=$1 addr=$2 vm=$3 requested=0
  vm_running "$ns" "$vm" || return 0
  if guest_ssh "$ns" "$addr" root 'systemctl --no-block reboot' >/dev/null 2>&1; then
    requested=1
  else
    echo "   ssh reboot failed; terminating the VMM instead" >&2
  fi
  if [ "$requested" = 1 ]; then
    for _ in $(seq 300); do
      vm_running "$ns" "$vm" || return 0
      sleep 0.2
    done
    echo "   the guest took a reboot but its VMM outlived it" >&2
  fi
  kill_vm "$ns" "$vm" -TERM && return 0
  kill_vm "$ns" "$vm" -KILL
}

# Signal this capsule's VMM and wait for it to go. Zero if nothing is left.
kill_vm() {
  local ns=$1 vm=$2 sig=$3 pids
  mapfile -t pids < <(vm_pids "$ns" "$vm")
  [ "${#pids[@]}" -gt 0 ] || return 0
  kill "$sig" "${pids[@]}" 2>/dev/null
  for _ in $(seq 50); do
    vm_running "$ns" "$vm" || return 0
    sleep 0.1
  done
  return 1
}

# --------------------------------- the fabric a capsule's proxy leaves through
#
# `probe/netns-egress.sh` established this and `probe/two-capsules.sh` asserts
# two policies through it at the same moment, so it lives here rather than in
# either — two copies of an egress fabric are two answers the first time one is
# edited, which is the reason the capsule boot above is here too.
#
# **None of it is the live fabric's, and that is a correction rather than a
# precaution.** `capsules.nix`'s map was copied *from* `netns-egress.sh` once the
# probe had verified the shape, which is how a probe that predated the module
# became a borrower of live addressing without a line of it changing: on a
# module-path host `eg-rt` is the production aggregator's uplink to the root
# namespace and `10.100.0.0/16` is the route to every capsule, so the teardown's
# `ip link del eg-rt` was a fleet-wide egress cut fired from a cleanup trap.
# Three refusals happened to fire ahead of it, so what the fault actually cost
# was a human following one of them (CLAUDE.md, NOTES item 38). Every name, link
# and network here comes from `flake.nix`'s `probeFabric`, which refuses at eval
# to spell anything `capsules.nix` declares — so a future copy in either
# direction is a build failure rather than an incident.
#
#   root ns      $EG_PEER            $EG_PEER_ADDR/30    forwards + masquerades
#   $EG_NS       $EG_DEV             $EG_ADDR/30         the aggregator: every
#                $EG_WAN_PREFIX<i>   <base>.<i>.1/30     capsule's proxy leaves
#                                                        through here, and the
#                                                        drops live here
#   capsule ns   $EG_OUT_PREFIX<i>   <base>.<i>.2/30     that capsule's way out
#
# Empty here and injected by the prelude, per the ordering note at the top: a
# probe that builds no fabric still carries these lines, and an unassigned
# variable referenced by a function is SC2154 whether the function runs or not.
EG_NS=""
EG_DEV=""
EG_PEER=""
EG_ADDR=""
EG_PEER_ADDR=""
EG_NET=""
EG_NET_BASE=""
EG_UPLINK_NET=""
EG_OUT_PREFIX=""
EG_WAN_PREFIX=""

# The same, for the three values a proxy round needs that are nobody's fabric:
# two from net.nix and the program itself. Declared rather than threaded through
# `proxy_up` and `guest_connect` as four more positional arguments — a capsule's
# tap address and the perimeter's port are one host's, not one call's.
HOST_ADDR=""
PROXY_PORT=""
PROXY=""

# Table names, which are the harness's own: the module's are `capsule-egress`
# and `capsule-guard`, and these have never collided with them. Kept here rather
# than injected because nothing in `capsules.nix` declares an nft table, so there
# is no live value for `probeFabric` to assert against.
EG_NFT_NAT=capeg-nat
EG_NFT_FWD=capeg-fwd
EG_NFT_GUARD=capeg-guard

EG_WAN_IF=""
EG_FORWARD_SAVED=""
EG_RESOLV=()
RESOLVER=""

# A capsule's /30 within EG_NET, by index. This is the one thing that cannot be
# identical across capsules — the aggregator has a single routing table — which
# is also why the /16 differing from `capsules.uplinkNet` is what keeps every
# derived address off the live fabric without asserting each one.
eg_gw() { echo "$EG_NET_BASE.$1.1"; }
eg_out() { echo "$EG_NET_BASE.$1.2"; }

# Before anything is created, so a refusal leaves nothing behind. An overlapping
# route in the root namespace sends this fabric's replies to whatever really owns
# the address and two results come back wrong in opposite directions; an existing
# link of the fabric's own name is the same statement one layer down, and the one
# a probe must never "clean up" — that link is how something else gets out.
egress_preflight() {
  local prog=$1 net
  for net in "$EG_NET" "$EG_UPLINK_NET"; do
    if ip route show | grep -qF "${net%%/*}"; then
      echo "$prog: the root namespace already has a route near $net:" >&2
      ip route show | grep -F "${net%%/*}" >&2
      echo "$prog: refusing — results would be meaningless." >&2
      return 1
    fi
  done
  if ip link show "$EG_PEER" >/dev/null 2>&1; then
    echo "$prog: $EG_PEER already exists in the root namespace." >&2
    echo "$prog: refusing. Do NOT delete it to get past this — this probe's" >&2
    echo "  teardown deletes that name, and a link you did not create is" >&2
    echo "  something else's way out." >&2
    return 1
  fi
  EG_WAN_IF=$(ip -o route show default | awk '{print $5; exit}')
  [ -n "$EG_WAN_IF" ] || {
    echo "$prog: no default route — there is no egress to prove." >&2
    return 1
  }
}

# The aggregator, and the host's half of the link to it. Takes the guest address
# because the NAT covers it as well as the fabric: that is the most permissive
# upstream there could be, which is what makes every denial downstream mean the
# capsule namespace stopped it rather than that nothing knew the way back.
egress_up() {
  local guest=$1
  ip netns add "$EG_NS" || return 1
  ip -n "$EG_NS" link set lo up
  # It has to forward: it is the point every capsule's proxy leaves through.
  # Which is exactly what makes it a capsule-to-capsule path, and why the drops
  # in `egress_rules` are not optional (probe/netns.sh found this as an
  # observation).
  ip netns exec "$EG_NS" sysctl -q -w net.ipv4.ip_forward=1

  ip link add "$EG_DEV" type veth peer name "$EG_PEER" || return 1
  ip link set "$EG_DEV" netns "$EG_NS"
  ip -n "$EG_NS" addr add "$EG_ADDR/30" dev "$EG_DEV"
  ip -n "$EG_NS" link set "$EG_DEV" up
  ip addr add "$EG_PEER_ADDR/30" dev "$EG_PEER"
  ip link set "$EG_PEER" up
  ip netns exec "$EG_NS" ip route add default via "$EG_PEER_ADDR"

  EG_FORWARD_SAVED=$(cat /proc/sys/net/ipv4/ip_forward)
  sysctl -q -w net.ipv4.ip_forward=1
  ip route add "$EG_NET" via "$EG_ADDR" dev "$EG_PEER"

  nft -f - <<EOF
table ip $EG_NFT_NAT {
  chain post {
    type nat hook postrouting priority srcnat;
    ip saddr { $EG_NET, $guest } oifname "$EG_WAN_IF" masquerade
  }
}
EOF
}

# One capsule onto the aggregator, on the /30 its index carves out.
egress_attach() {
  local ns=$1 i=$2 out="$EG_OUT_PREFIX$2" wan="$EG_WAN_PREFIX$2" gw addr
  gw=$(eg_gw "$i")
  addr=$(eg_out "$i")
  ip link add "$out" type veth peer name "$wan" || return 1
  ip link set "$out" netns "$ns"
  ip link set "$wan" netns "$EG_NS"
  ip -n "$ns" addr add "$addr/30" dev "$out"
  ip -n "$EG_NS" addr add "$gw/30" dev "$wan"
  ip -n "$ns" link set "$out" up
  ip -n "$EG_NS" link set "$wan" up
  ip netns exec "$ns" ip route add default via "$gw"
}

# A route back to a guest, from the aggregator and from the host, plus the NAT
# `egress_up` already installed for it: the most permissive upstream there could
# be, so a guest that cannot get out is being stopped rather than merely lost.
#
# **One capsule at a time, and that is the design rather than a limit.** Every
# guest is at the same address in its own namespace, so a return path can only
# ever name one of them — which is the same identical addressing that makes a
# sibling unaddressable in `probe/two-capsules.sh`. A probe with two guests up
# has no return path to either, and its denials are correspondingly weaker.
egress_guest_return() {
  local guest=$1 i=$2
  ip route add "$guest/32" via "$EG_ADDR" dev "$EG_PEER"
  ip netns exec "$EG_NS" ip route add "$guest/32" via "$(eg_out "$i")"
}

# Loopback is per-namespace, so the host's stub on 127.0.0.53 is not in here. The
# designed answer keeps the host's resolver chain (resolved -> stubby -> ControlD)
# rather than dropping to a public resolver: an extra stub address on the
# capsule-facing link, and an /etc/netns/<ns>/resolv.conf naming it. The second
# half is the probe's to write; the first half is a host-config edit, so detect
# it rather than assume it — from where the consumer is, and before any drop goes
# in, so what it detects is the host rather than the probe's own rules.
#
# Detected once and written per namespace: a second capsule must not re-ask a
# question whose answer is the host's, and two capsules disagreeing about their
# resolver would be a difference nobody declared.
egress_resolver() {
  local ns=$1
  if [ -z "$RESOLVER" ]; then
    if ip netns exec "$ns" timeout 5 dig +short +tries=1 "@$EG_PEER_ADDR" \
      example.com >/dev/null 2>&1; then
      RESOLVER=$EG_PEER_ADDR
      RESULTS+=("NOTE  the host's own resolver answers on $EG_PEER_ADDR — the capsule keeps its DoT chain")
    else
      RESOLVER=1.1.1.1
      RESULTS+=("NOTE  no host resolver on $EG_PEER_ADDR — fell back to $RESOLVER, which LOSES the host's DoT hop.")
      RESULTS+=("NOTE  the shipped shape wants two lines in ~/flakes: DNSStubListenerExtra on the")
      RESULTS+=("NOTE  capsule-facing address, and an input allow for port 53 on that link — the")
      RESULTS+=("NOTE  host firewall covers every interface, including one this repo created.")
    fi
  fi
  mkdir -p "/etc/netns/$ns"
  echo "nameserver $RESOLVER" >"/etc/netns/$ns/resolv.conf"
  EG_RESOLV+=("$ns")
}

# In the aggregator: capsules must not reach each other through the thing that
# aggregates them, and must not reach the host's own networks either. The
# interface-pair rule is a clean wildcard — it matches links, not addresses, so
# it enumerates nothing and a new capsule needs no edit. The resolver is the one
# RFC1918 destination a capsule may have, and it is allowed narrowly (port 53, by
# address) ahead of the broad drop, which is what makes the pair testable: DNS
# works, a ping to the same address does not.
egress_rules() {
  ip netns exec "$EG_NS" nft -f - <<EOF
table ip $EG_NFT_FWD {
  chain forward {
    type filter hook forward priority filter; policy accept;
    ip daddr $RESOLVER udp dport 53 accept
    ip daddr $RESOLVER tcp dport 53 accept
    iifname "$EG_WAN_PREFIX*" oifname "$EG_WAN_PREFIX*" drop
    ip saddr $EG_NET ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } drop
  }
}
EOF
}

egress_rules_down() {
  ip netns exec "$EG_NS" nft delete table ip "$EG_NFT_FWD" 2>/dev/null
}

# In a capsule's namespace: the proxy's way out is a *local* address there, so a
# packet from the guest to it is INPUT and no amount of ip_forward=0 touches it
# (probe/netns.sh, cost 1). Services bind the tap address; anything else arriving
# on the tap is not for the guest.
capsule_guard_rules() {
  local ns=$1 tap=$2 addr=$3
  ip netns exec "$ns" nft -f - <<EOF
table ip $EG_NFT_GUARD {
  chain input {
    type filter hook input priority filter; policy accept;
    iifname "$tap" ip daddr != $addr drop
  }
}
EOF
}

capsule_guard_down() {
  ip netns exec "$1" nft delete table ip "$EG_NFT_GUARD" 2>/dev/null
}

# Everything the fabric put in the root namespace, and the aggregator with it.
# Deleting either end of a veth takes both, and the root-side routes with it.
egress_down() {
  local ns
  nft delete table ip "$EG_NFT_NAT" 2>/dev/null
  [ -n "$EG_FORWARD_SAVED" ] && sysctl -q -w "net.ipv4.ip_forward=$EG_FORWARD_SAVED"
  [ -n "$EG_PEER" ] && ip link del "$EG_PEER" 2>/dev/null
  for ns in "${EG_RESOLV[@]}"; do rm -rf "/etc/netns/$ns"; done
  [ -n "$EG_NS" ] && ns_down "$EG_NS"
  return 0
}

# The real `capsule-proxy` — the same binary host/services.nix runs as a unit and
# `capsule-host` runs as a child — joined to a capsule's namespace, under a named
# policy's allowlist. Its state goes wherever the caller says rather than in
# `.vm/host`, so a probe run cannot leave the devshell path pointing at a config
# it did not write.
#
# Started and stopped by policy rather than once, because a policy is *selected*
# and the perimeter follows the selection (NOTES item 36): the proxy renders its
# config at start, so a restart is what a policy change costs a running capsule.
# This is the mechanism the `policy` verb uses and not a probe-only shortcut.
proxy_up() {
  local ns=$1 root=$2 state=$3 allow=$4
  helper_as_human "$ns" \
    "CAPSULE_ROOT=$root" \
    "CAPSULE_PROXY_STATE=$state" \
    "CAPSULE_ALLOWLIST=$allow" \
    "$PROXY"
  wait_listen "$ns" "$HOST_ADDR" "$PROXY_PORT"
}

# `pkill -f` on the rendered config path, which is `capsule-host`'s own reaper and
# safe here for the reason it is safe there: that path is this run's, under the
# caller's own state directory, so it cannot match anything else on the host.
# (The CLAUDE.md warning about `pkill -f` is about the VMM, whose name every
# capsule shares.)
proxy_down() {
  local ns=$1 state=$2
  pkill -f -- "tinyproxy -d -c $state/tinyproxy.conf" || true
  for _ in $(seq 20); do
    ip netns exec "$ns" ss -lnt 2>/dev/null \
      | grep -qF "$HOST_ADDR:$PROXY_PORT" || return 0
    sleep 0.1
  done
  return 1
}

# CONNECT through the proxy, from inside the guest, as any HTTPS client would.
# Asked *of the guest* because the guest is the confined party — the same request
# from the capsule namespace answers a different question and would answer it
# green. bash and /dev/tcp rather than curl: the guest's tool set comes from the
# target's flake and a probe may not assume what is in it. Only bash is
# guaranteed, and /dev/tcp also gives tinyproxy's status line verbatim, which is
# the difference between "refused" and "could not resolve" — two outcomes an exit
# status cannot tell apart.
#
# `timeout` outside ssh rather than ConnectTimeout, which a CONNECT that hangs
# has already got past.
guest_connect() {
  local ns=$1 addr=$2 target=$3
  in_ns_as_human "$ns" timeout 20 ssh "${SSH_OPTS[@]}" "root@$addr" \
    "exec 3<>/dev/tcp/$HOST_ADDR/$PROXY_PORT; printf 'CONNECT %s:443 HTTP/1.1\r\nHost: %s:443\r\n\r\n' '$target' '$target' >&3; head -1 <&3" \
    2>&1 | tr -d '\r' | tail -1
}

is_200() { case $1 in *" 200 "*) return 0 ;; *) return 1 ;; esac; }

# A refusal that came from a proxy rather than from a dead one. The claim a
# policy round makes is that the perimeter answered and said no; a connection
# error says nothing about the allowlist, and reads identically from `check`.
is_http() { case $1 in HTTP/*) return 0 ;; *) return 1 ;; esac; }

# One host the allowlist permits, taken from the allowlist itself — a probe does
# not get to spell a hostname, for the same reason nothing else here does: which
# hosts a target may reach is that target's policy. Anchored plain names only; a
# genuine regex entry is skipped rather than guessed at, which is why a round
# built on this has to report its own count (docs/probes.md).
first_allowed() {
  sed -n '/^\^[A-Za-z0-9.\\-]*\$$/{s/[^A-Za-z0-9.-]//g;p;}' "$1" | head -1
}

# Nonzero if anything failed, so a probe ends `report || exit 1`.
report() {
  echo
  echo "== results =="
  printf '%s\n' "${RESULTS[@]}"
  echo
  echo "$PASSED passed, $FAILED failed"
  [ "$FAILED" = 0 ]
}
