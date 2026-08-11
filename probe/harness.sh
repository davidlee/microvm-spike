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

# Nonzero if anything failed, so a probe ends `report || exit 1`.
report() {
  echo
  echo "== results =="
  printf '%s\n' "${RESULTS[@]}"
  echo
  echo "$PASSED passed, $FAILED failed"
  [ "$FAILED" = 0 ]
}
