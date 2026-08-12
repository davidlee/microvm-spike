# How the host talks to a guest, and the one relaxation that makes it work.
#
# The guest's host keys live on its volume, so a *fresh* capsule has fresh keys
# at the same address — and freshness is the goal, not an accident (NOTES item
# 17). Since the git channel rides ssh, a changed key no longer merely annoys
# `just ssh`: it blocks provisioning. `accept-new` does not help, because it
# accepts *unknown* hosts and this is a *changed* one.
#
# So: no host-key check at all, and no record of one. That is sound only because
# of what this link is — a /30 this host created itself, with exactly one peer,
# and no third party on it to be in the middle. It stops being sound the moment
# the transport is a bridge, a LAN or another machine, and it must change in the
# same commit that does that. `/dev/null` rather than a capsule-scoped file on
# purpose: a file would accumulate one stale key per capsule and quietly
# reintroduce the failure. LogLevel=ERROR because otherwise every invocation
# announces the key it just accepted.
#
# The interactive paths — `just ssh`, `just admin` — deliberately do *not* use
# this. A human present to read the warning is the case where the strict default
# is still worth having.
#
# Its own file because both paths need it and neither may spell it twice: the
# devshell's programs get it from `flake.nix`, the units get it from
# `host/services.nix`, and a relaxation of a security default that exists in two
# copies is one copy nobody edits.
#
# It also owns *which* capsule a program is talking to, because that question and
# this one have the same answer: under netns a capsule's identity is the socket
# the transport goes through, so naming it and reaching it are one decision and
# belong in one fragment. `direct` and `viaSocket` below are what the two paths
# inject into `host/programs.nix`.
{lib}: rec {
  # As argv, because `capsule-inject` runs ssh itself and the netns form carries
  # a ProxyCommand with spaces in it — a string would have to be re-split by a
  # shell that cannot know where the quoting was meant to go.
  args = [
    "ssh"
    "-o"
    "StrictHostKeyChecking=no"
    "-o"
    "UserKnownHostsFile=/dev/null"
    "-o"
    "LogLevel=ERROR"
  ];

  # The same thing for consumers that want a command line: git parses
  # `GIT_SSH_COMMAND` shell-style.
  command = lib.escapeShellArgs args;

  # ------------------------------------------------- which capsule, and how in
  #
  # A program cannot be built per capsule. Every capsule runs the same guest from
  # the same store path at the same address, so the only thing that differs
  # between two of them is a socket path — and building N programs over that is N
  # store paths differing in one string, which is what left `capsule-provision`
  # able to reach exactly one capsule. So the name is a *run-time* value:
  # `--capsule <name>`, else `CAPSULE_NAME`, else the default.
  #
  # The parse lives here rather than in each program's own flag loop for two
  # reasons: all four need it identically, and it strips itself out of `"$@"`
  # before that loop runs, so a program's own arguments — a ref, a payload name,
  # `--force` — cannot be confused with a capsule.
  #
  # An `--capsule=NAME` form as well as `--capsule NAME`, because `CAPSULE_NAME=x
  # prog` is not a thing every shell has (nushell wants `with-env`), so the flag
  # is the one-off form and has to be pleasant.
  selectCapsule = default: ''
    capsule="''${CAPSULE_NAME:-${default}}"
    unnamed=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --capsule)
          shift
          [ "$#" -gt 0 ] || {
            echo "--capsule needs the name of a capsule" >&2
            exit 1
          }
          capsule="$1"
          ;;
        --capsule=*) capsule="''${1#--capsule=}" ;;
        *) unnamed+=("$1") ;;
      esac
      shift
    done
    set -- ''${unnamed[@]+"''${unnamed[@]}"}
  '';

  # The devshell path: one capsule, on a tap in the root namespace, reached
  # straight. It has nothing else to name, so a second name is a refusal rather
  # than a silent success — the failure it would otherwise be is "I provisioned
  # `edge`" while the bytes went to the only capsule there is.
  direct = {default}:
    selectCapsule default
    + ''
      if [ "$capsule" != ${lib.escapeShellArg default} ]; then
        echo "no capsule '$capsule' here: the devshell path runs one, named ${default}." >&2
        echo "  More than one is the module path, where the way in is a relay socket" >&2
        echo "  per capsule (README, 'The module path')." >&2
        exit 1
      fi
      ssh_cmd=(${lib.escapeShellArgs args})
    '';

  # And the same again for a capsule in a namespace, where the guest is not
  # routable from the root namespace at all: the way in is the relay socket, and
  # that socket path is the capsule's identity.
  #
  # `socket` is a *shell expression*, not a path: the path is a pure function of
  # a name this program only learns at run time, so the call site passes
  # `capsules.socketOf ''"$capsule"''` and the convention keeps exactly one
  # definition. `socat` is passed rather than assumed on PATH, because one caller
  # is a systemd unit.
  viaSocket = {
    default,
    socat,
    socket,
  }:
    selectCapsule default
    + ''
      sock=${socket}
      if [ ! -S "$sock" ]; then
        echo "no way in to capsule '$capsule': $sock is not a socket." >&2
        echo "  systemctl status capsule-ssh-relay-$capsule" >&2
        exit 1
      fi
      ssh_cmd=(${lib.escapeShellArgs args} -o "ProxyCommand=${socat} - UNIX-CONNECT:$sock")
    '';
}
