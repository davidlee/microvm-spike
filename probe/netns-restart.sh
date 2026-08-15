#!/usr/bin/env bash
#
# Probe: does a capsule's namespace survive being torn down and rebuilt?
# (NOTES item 37)
#
# The instrument item 37 owed. A `systemctl restart capsule-netns-b` used to
# fail because `down` deleted the namespace and left the veth peer in the
# aggregator to the kernel's asynchronous reaper — so an `up` that beat the
# reaper died on `An interface with the same name exists in the target netns`,
# and the aborted `up` stranded a peer in the *root* namespace plus a
# half-built namespace that `systemctl stop` could not clear, because a unit
# that fails in ExecStart never runs ExecStop. The fix gave both netns programs
# one `undo_up`, used as `down` and as `up`'s own EXIT rollback.
#
# **It runs the real `capsule-netns`, not a copy of it.** The program takes
# every per-capsule value from its unit's `Environment=` — deliberately, so
# that `systemctl cat` shows a boundary's addressing rather than a store path —
# and that is the seam a probe can drive it through. Same shape as
# `host/guard.nix`'s `tools` and `host/git-channel.nix`'s `transport`: the one
# thing tying the program to this host is an argument, so a test substitutes it
# instead of reimplementing the program (CLAUDE.md, "the third kind of check").
# Here that is a whole capsule's worth of addressing, and this probe supplies
# its own.
#
#   cprb-egress ns   cprb-a       10.102.0.1/30   stands in for the aggregator:
#                                                 where the peer lives, and the
#                                                 namespace `up` must move it to
#   cprb-a ns        up-cprb-a    10.102.0.2/30   the capsule's way out
#                                 (cprb-tap 10.102.1.1/30 is declared and never
#                                  created — microvm.nix makes the tap later)
#
# **The peer's name is the capsule namespace's name**, both `cprb-a`, because
# that is production's shape: `capLink` prefixes both, so `cap-b` is a namespace
# *and* an interface. That ambiguity is why the original error message read as
# it did, and a probe that quietly renamed one of them would be testing a
# friendlier system than the one that ships.
#
# No VM, no tap, no guest, no root-namespace addressing, and nothing outside
# this probe's own namespaces — so it is seconds and it cannot disturb a fleet.
# It does write `/etc/netns/cprb-a/resolv.conf`, because the program does; that
# is one of the things the rollback is asserted to remove.
#
# The names are `cprb-`-prefixed and nothing declared shares them. That is not
# cosmetic: `probe/netns-egress.sh` sets `NSWAN=cap-egress`, the same string
# `capsules.nix` declares for the live aggregator, and on a module-path host its
# "left over, delete it" refusal names a production namespace and instructs you
# to delete it. Doing so cost a guard failure and a recovery. A probe may borrow
# the live tap and volume on purpose; it may not borrow a live *name*.
#
# Run: sudo probe-netns-restart
#
# `probe/harness.sh` is concatenated ahead of this by flake.nix.

# Deliberately no errexit: several rounds here are supposed to fail.

NS=cprb-a
EGRESS_NS=cprb-egress
DEV=up-cprb-a
PEER=$NS # production's shape, see the header
ETC=/etc/netns/$NS

need_root probe-netns-restart

# The program under test, from the prelude — the same file `host/services.nix`
# builds its ExecStart from, so a fix landing in one lands in both.
PROG=${CAPSULE_NETNS:?}

has_ns() { ip netns list | grep -qw "$1"; }
link_in() { ip -n "$1" link show "$2"; }
link_here() { ip link show "$1"; }
forwarding_off() { [ "$(ip netns exec "$1" sysctl -n net.ipv4.ip_forward)" = 0 ]; }

# Every value the unit would carry. Spelled here rather than read out of
# `capsules.nix`, so this probe tests the program against addressing that is
# nobody's capsule.
netns() {
  env \
    NS="$NS" EGRESS_NS="$EGRESS_NS" \
    TAP=cprb-tap TAP_ADDR=10.102.1.1 PREFIX=30 \
    DEV="$DEV" PEER="$PEER" \
    ADDR=10.102.0.2 GW=10.102.0.1 UPLINK_PREFIX=30 \
    RESOLVER=10.102.0.1 \
    "$PROG" "$@"
}

# Refuse rather than half-run: a leftover from an interrupted run would make the
# first round's "it comes up" pass or fail for reasons that are not the program's.
for ns in "$NS" "$EGRESS_NS"; do
  if has_ns "$ns"; then
    echo "probe-netns-restart: namespace $ns is left over from an earlier run." >&2
    echo "  sudo ip netns del $ns" >&2
    exit 1
  fi
done
if link_here "$PEER" >/dev/null 2>&1; then
  echo "probe-netns-restart: a link named $PEER is in the root namespace —" >&2
  echo "  that is what an aborted 'up' strands. sudo ip link del $PEER" >&2
  exit 1
fi

cleanup() {
  ip -n "$EGRESS_NS" link del "$PEER" 2>/dev/null
  ip -n "$EGRESS_NS" link del cprb-plant 2>/dev/null
  ip link del "$PEER" 2>/dev/null
  ip netns del "$NS" 2>/dev/null
  ip netns del "$EGRESS_NS" 2>/dev/null
  rm -rf "$ETC"
  echo
  echo "cleaned up."
}
trap cleanup EXIT

# The aggregator, by hand: the capsule program only needs somewhere to move its
# peer to, and building it with `capsule-egress-ns` would put a veth and a route
# in the root namespace to test a claim that is not this one.
echo "== an aggregator namespace for the peer to land in =="
ip netns add "$EGRESS_NS" || exit 1
ip -n "$EGRESS_NS" link set lo up

# ------------------------------------------------------------------- round 1
#
# What `up` builds. Asserted before anything is torn down, so a later "it is
# gone" cannot pass because it was never there.

echo "== round 1: up =="

check "up succeeds" ok netns up
check "the capsule namespace exists" ok has_ns "$NS"
check "its uplink is inside it" ok link_in "$NS" "$DEV"
check "the peer is in the aggregator" ok link_in "$EGRESS_NS" "$PEER"
check "the peer is not in the root namespace" deny link_here "$PEER"
check "the namespace does not forward" ok forwarding_off "$NS"
check "it has a resolver of its own" ok test -f "$ETC/resolv.conf"

# ------------------------------------------------------------------- round 2
#
# What `down` must have taken with it. Nothing sleeps between the teardown and
# the question.
#
# **The peer round here is weak, and the mutation run is what said so.** It
# passes against a `down` that deletes only the namespace, because deleting the
# namespace kills the uplink, deleting either end of a veth takes both, and on
# this host the kernel's reaper is usually quick enough to have finished by the
# time the next line runs. So it can pass for the wrong reason — which is the
# one failure a probe exists to prevent. It is kept because the property is
# still worth stating; what *pins* it is round 3's strand and round 5's orphan,
# neither of which is a race.

echo "== round 2: down, and what it must have taken with it =="

check "down succeeds" ok netns down
check "the capsule namespace is gone" deny has_ns "$NS"
check "the peer is gone from the aggregator, with no wait" deny \
  link_in "$EGRESS_NS" "$PEER"
check "nothing was left in the root namespace" deny link_here "$PEER"
check "the resolver went with it" deny test -e "$ETC"

# ------------------------------------------------------------------- round 3
#
# **The inverted direction, and it is what makes round 2 mean anything.** A
# leftover peer has to actually break `up` — otherwise "down removes the peer"
# is a claim about tidiness rather than about the failure it prevents.
#
# Planted rather than raced. The kernel's reaper is what made this intermittent
# on a live host, and a probe that waits for a race to go its way is a probe
# people learn to re-run until it passes. A link wearing the peer's name is the
# same collision, on demand: `up` reaches `ip link set "$peer" netns
# "$egress_ns"` and finds the name taken, which is exactly what the restart
# used to find.
#
# A veth rather than a dummy, because `dummy` is a module a host need not have
# loaded and this probe would then fail at its own set-up while reporting
# nothing about the program. veth is the one link type `capsule-netns` cannot
# run without.

echo "== round 3: a leftover peer must break 'up', and 'up' must roll back =="

# **Delete, then plant, and never `|| exit 1`** — three attempts at this line,
# and each failure taught the same lesson from a different side:
#
#   - `|| exit 1` aborted the whole probe when the name was already taken by a
#     broken teardown's residue. Silent at exactly the moment the thing under
#     test is broken.
#   - Tolerating the failed add left the *residue* standing in for the plant.
#     Residue is a link on its way out: it satisfied "the name is taken" and was
#     reaped before `up` ran, so the control passed for the wrong reason and
#     three later rounds failed downstream of it.
#
# So the round owns its own collision. The delete clears whatever was there, the
# add puts a link of ours in its place, and the assertion is on the state rather
# than on either command. **A probe's set-up must produce the state it needs,
# not inherit something that resembles it.**
ip -n "$EGRESS_NS" link del "$PEER" 2>/dev/null
ip -n "$EGRESS_NS" link add "$PEER" type veth peer name cprb-plant 2>/dev/null
check "the peer's name is taken in the aggregator" ok link_in "$EGRESS_NS" "$PEER"
check "control: 'up' fails when the peer's name is already taken" deny netns up

# The half-built namespace and the strand — the two things `systemctl stop`
# could not reach, because a unit that fails in ExecStart never runs ExecStop.
check "the aborted 'up' left no namespace behind" deny has_ns "$NS"
check "the aborted 'up' stranded no peer in the root namespace" deny \
  link_here "$PEER"
check "the aborted 'up' left no resolver behind" deny test -e "$ETC"

# The rollback also removed the plant, since it wears the name `undo_up` is told
# to delete — and deleting either end of a veth takes both, so `cprb-plant` went
# with it. Correct rather than over-eager: in production that name is the
# capsule's own, and there is nothing else it could be. Recorded as a finding
# because it is the one thing here the fix does that nobody asked it to.
observe "the planted peer after the rollback" link_in "$EGRESS_NS" "$PEER"

# Back to a known state before the next round, because **a round must not
# inherit the previous round's wreckage** — against a program that leaves any,
# every later red names the wrong round. This is a teardown of the probe's own
# making and deliberately not `undo_up`'s: asking the program under test to
# clean up after its own failure is how round 4 came to fail at `cycle 1: up`
# for something round 3 had done.
ip -n "$EGRESS_NS" link del "$PEER" 2>/dev/null
ip link del "$PEER" 2>/dev/null
ip netns del "$NS" 2>/dev/null
rm -rf "$ETC"

# ------------------------------------------------------------------- round 4
#
# The empirical claim, which is what a human saw by hand: restarts back to back,
# with nothing between them.
#
# **This round does not discriminate, and that is worth knowing rather than
# hiding.** Under the pre-fix program all five cycles pass — the reaper wins
# every time at this speed, which is also why the bug was intermittent enough to
# survive into production. What still fails there is the leak check below: the
# *last* cycle's peer had not been reaped when it was asked about. So the cycles
# are a smoke test and the leak check is the assertion.

echo "== round 4: five up/down cycles with nothing between them =="

t0=$(now)
for i in 1 2 3 4 5; do
  check "cycle $i: up" ok netns up
  check "cycle $i: down" ok netns down
done
measure "five up/down cycles" "$(since "$t0")" s

# And the state after all of it, because a cycle that succeeds while leaking is
# a cycle that fails on the sixth host to run it.
check "no namespace survives the cycles" deny has_ns "$NS"
check "no peer survives the cycles" deny link_in "$EGRESS_NS" "$PEER"
check "no strand survives the cycles" deny link_here "$PEER"

# ------------------------------------------------------------------- round 5
#
# The residue case, and the second thing the fix is needed for rather than
# merely tidy about: a peer that no namespace accounts for. That is what an
# aborted `up` leaves and what a human cleared by hand — and `down` calls
# `undo_up` unconditionally, not only when the namespace is present, for exactly
# this state.
#
# Deterministic, unlike round 2: there is no namespace here whose deletion could
# reap the peer as a side effect, so nothing but the program can remove it.

echo "== round 5: down must clear a peer that no namespace accounts for =="

ip -n "$EGRESS_NS" link del "$PEER" 2>/dev/null
ip -n "$EGRESS_NS" link add "$PEER" type veth peer name cprb-plant 2>/dev/null
check "the orphan is there to begin with" ok link_in "$EGRESS_NS" "$PEER"
check "down succeeds against no namespace at all" ok netns down
check "the orphaned peer is gone" deny link_in "$EGRESS_NS" "$PEER"

report || exit 1
