# Shared by every probe. Concatenated ahead of one by flake.nix rather than
# sourced: `writeShellApplication` builds a single script, so shellcheck sees
# the probe and its harness as one file, and a probe has no path to a sibling
# at run time anyway.
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
halt_guest() {
  local ns=$1 addr=$2 vm=$3
  vm_running "$ns" "$vm" || return 0
  guest_ssh "$ns" "$addr" root 'systemctl --no-block poweroff' >/dev/null 2>&1 \
    || echo "   ssh poweroff failed; terminating the VMM instead" >&2
  for _ in $(seq 100); do
    nsping "$ns" "$addr" >/dev/null 2>&1 || break
    sleep 0.2
  done
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

# Nonzero if anything failed, so a probe ends `report || exit 1`.
report() {
  echo
  echo "== results =="
  printf '%s\n' "${RESULTS[@]}"
  echo
  echo "$PASSED passed, $FAILED failed"
  [ "$FAILED" = 0 ]
}
