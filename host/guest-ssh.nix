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

  # And the same again for a capsule in a namespace, where the guest is not
  # routable from the root namespace at all: the way in is the relay socket, and
  # that socket path is the capsule's identity. Argv again, so nothing has to
  # guess where the quoting in a ProxyCommand was meant to go. `socat` is passed
  # rather than assumed on PATH, because one caller is a systemd unit.
  viaSocket = {
    socat,
    socket,
  }:
    args ++ ["-o" "ProxyCommand=${socat} - UNIX-CONNECT:${socket}"];
}
