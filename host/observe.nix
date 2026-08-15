# The guest half of `capsule <name> status` — what is *observed*, as opposed to
# what a slot was assigned (docs/contract-assignment.md keeps those two apart,
# and this file is only ever the second one).
#
# **Pushed at each call, never baked into the guest's closure.** The same two
# reasons `host/baseline.nix` gives for its own runner: this is host-side policy
# about a measurement rather than part of what a capsule is, and a volume
# outlives any program, so a copy left on one from an older build would be drift
# nothing reports. Unlike baseline's it is not even written to the volume — it
# arrives on stdin, answers, and is gone, because a status is a question and a
# question should leave nothing behind.
#
# **No login shell, deliberately.** `capsule-baseline` needs one and pays item
# 24's price for it (`bash -l -c "bash script"`, because a `set -u` script must
# not *be* a login shell). Nothing here reads the guest's `environment.variables`
# — no proxy, no CARGO_HOME, no TMPDIR is involved in asking git for a sha — so
# there is no login shell to get wrong.
#
# **One line, tab-separated, fixed order, and this file is the only definition of
# that order.** The caller splits on tabs and never counts words. Every field has
# a `-` for "cannot say", which is what an unprovisioned volume answers with.
#
# **The three paths it reads arrive on its command line** (NOTES item 51). They
# used to be interpolated, which made a status program a function of which
# project the host confines — the same shape as a socket path in a store path
# before item 20. Usage:
#
#     <work> <record-dir> <volume>
#
# All three required: a status that guessed at a path would answer confidently
# about a directory nobody named.
{
  pkgs,
  lib,
  # The guest's checkout.
  workdir,
  # Where `capsule-baseline` writes its record. Beside the checkout, never inside
  # it, for that program's reasons.
  recordDir,
  # The volume's mount point — the fleet's binding constraint is disk
  # (docs/probes.md), so this is the one figure here that is about the slot
  # rather than about the work in it.
  volumePath,
}: let
  # Deliberately not `set -e`: every question below is allowed to have no answer,
  # and a missing checkout is a state to report rather than an error to abort on.
  # The contract with the caller is *exactly one line on stdout*, so a failure to
  # produce one reads as an unreachable guest, which is the truth in that case.
  script = pkgs.writeText "capsule-observe" ''
    set -uo pipefail

    work=''${1:-}
    rec=''${2:-}
    vol=''${3:-}
    if [ "$#" -lt 3 ]; then
      echo "capsule-observe: usage: <work> <record-dir> <volume>" >&2
      exit 2
    fi

    head=- dirty=- baseline=none stamp=- disk=-

    # `--git-dir`-free and `-C`-based, so a path that is not a repo is a silent
    # no rather than a wrong answer about the parent directory.
    # The **full** oid, not an abbreviation. The caller shortens it for a column,
    # but this is also what the assignment record pins as `base.oid` after a
    # provision (docs/contract-assignment.md), and a pin is not an abbreviation.
    # One field, two uses, rather than a second round trip for the long form.
    if oid=$(git -C "$work" rev-parse HEAD 2>/dev/null); then
      head=$oid
      # Counting rather than testing emptiness: `wc -l` of a porcelain listing is
      # one cheap number that also says how dirty, and the caller wants the
      # boolean today and the number the moment anyone asks "how dirty".
      if [ "$(git -C "$work" status --porcelain 2>/dev/null | wc -l)" -gt 0 ]; then
        dirty=yes
      else
        dirty=no
      fi
    fi

    # **The record, never an exit status** (NOTES item 24, and Plan D D5 says why
    # it stays that way now the bug is fixed): `capsule-baseline` writes this line
    # on the volume before the shell running it can lose the status, so it was
    # right throughout the period the status was wrong.
    #
    # `running` is a live pid file and outranks the last record — a run in flight
    # is the answer to "what is this slot doing", and the previous verdict is not.
    if [ -e "$rec/running" ] && kill -0 "$(cat "$rec/running" 2>/dev/null)" 2>/dev/null; then
      baseline=running
    elif last=$(tail -1 "$rec/history.tsv" 2>/dev/null) && [ -n "$last" ]; then
      # stamp status seconds commit mib_before mib_after command
      IFS=$'\t' read -r stamp st _ <<<"$last"
      if [ "$st" = 0 ]; then baseline=ok; else baseline="fail:$st"; fi
    fi

    # The stamp is **the host's** UTC, not the guest's: `capsule-baseline` names
    # each run host-side precisely so both ends agree on it. So the caller may
    # subtract it from its own clock, and the guest-is-UTC-and-this-host-is-AEST
    # trap (CLAUDE.md) cannot arise here — there is no guest clock in this line.
    disk=$(df -P "$vol" 2>/dev/null | awk 'NR==2 {print $5}')
    [ -n "$disk" ] || disk=-

    printf '%s\t%s\t%s\t%s\t%s\n' "$head" "$dirty" "$baseline" "$stamp" "$disk"
  '';
in {
  inherit script;

  # Escaped twice, because ssh joins its arguments with spaces and the guest's
  # shell parses the result again (host/guest-exec.nix).
  guestArgs = lib.escapeShellArgs (map lib.escapeShellArg [workdir recordDir volumePath]);
}
