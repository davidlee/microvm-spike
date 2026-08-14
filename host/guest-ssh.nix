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
# It also owns *which* capsule a program is talking to, because under netns a
# capsule's identity is the socket the transport goes through, so naming it and
# reaching it belong in one file. They are **not one fragment**, though, and
# `capsule-adopt` is why: it must know which capsule it is for and must not
# reach one, since a transport refuses when the guest is down and a finished
# capsule's exhibit is adopted in exactly that state (NOTES item 34).
#
# So `direct` and `viaSocket` return the **pair** — `{selectCapsule, transport}`
# — and `host/programs.nix` takes it as one `access` argument. One value rather
# than two, because there are three call sites building this (both paths and
# `probe-freshness`), and a second argument is a second thing each of them can
# forget: the eval caught exactly that, once, which is the same shape as the
# `observe` rebuild in CLAUDE.md. Anything built at N call sites needs one
# construction, not N careful ones.
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
    # A stopped capsule is the common case, not an exotic one, and without this
    # it is a *hang*: the relay socket is a listener, so it accepts, and ssh
    # then waits on a TCP connect to a guest that is not running. The relay
    # being up says the namespace is up, which is not the same claim. Bounds the
    # connect only, so nothing a program does after it is time-limited by this.
    "-o"
    "ConnectTimeout=10"
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
  # `--capsule <name>`, else `CAPSULE_NAME`, else a refusal.
  #
  # There is no default, and its deletion is the other half of slots being
  # abstract: `capsules.default` was defensible while a capsule was called
  # `capsule`, and once a name carries no meaning a default is a program acting
  # on a slot nobody chose — with nothing in the name to say it was the wrong
  # one. Resolving an unnamed invocation from what is running is a *front end's*
  # latitude and lives in `host/cli.nix`; a program refuses (NOTES item 20).
  #
  # The parse lives here rather than in each program's own flag loop for two
  # reasons: all four need it identically, and it strips itself out of `"$@"`
  # before that loop runs, so a program's own arguments — a ref, a payload name,
  # `--force` — cannot be confused with a capsule.
  #
  # An `--capsule=NAME` form as well as `--capsule NAME`, because `CAPSULE_NAME=x
  # prog` is not a thing every shell has (nushell wants `with-env`), so the flag
  # is the one-off form and has to be pleasant.
  selectCapsule = ''
    capsule="''${CAPSULE_NAME:-}"
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

    if [ -z "$capsule" ]; then
      echo "''${0##*/}: which capsule? '--capsule <name>', or CAPSULE_NAME in the" >&2
      echo "  environment. A slot's name carries no meaning, so there is nothing to" >&2
      echo "  guess from — or say it once, as 'capsule <name> <verb>'." >&2
      exit 1
    fi
  '';

  # The devshell path: one capsule, on a tap in the root namespace, reached
  # straight. It has nothing else to name, so a name it does not know is a
  # refusal rather than a silent success — the failure it would otherwise be is
  # "I provisioned slot `c`" while the bytes went to the only capsule there is.
  #
  # What it can check is that the name is a *declared* slot, and no longer which
  # one: every slot resolves to the same guest at the same address here, so the
  # name selects nothing but where collected refs and the quarantine land. That
  # is weaker than the refusal this had while one capsule was named `capsule`,
  # and it is the honest form — a typo still cannot invent a slot, and knowing
  # which of two declared slots you booted is `.vm/<name>`, i.e. host state,
  # which is a front end's business and not a program's.
  #
  # `socket` is here for the *second* refusal, which is not about naming: inside
  # the repo the devshell's copies shadow the module's on PATH, same name and
  # same source, carrying the other transport (CLAUDE.md). This copy reaching for
  # `net.guest` on a host whose taps are all in namespaces is unroutable, and it
  # fails as a timeout that reads as a dead guest. So a relay socket for this
  # capsule means the module path owns this host and *this* program is the wrong
  # copy — say so, and name the one that works. Refusing, not choosing: a program
  # that can try both has both baked in, which is the thing NOTES item 20
  # decided against.
  direct = {
    names,
    socket,
  }: {
    inherit selectCapsule;
    transport =
      selectCapsule
      + ''
        declared=(${lib.concatMapStringsSep " " lib.escapeShellArg names})
        known=no
        for d in "''${declared[@]}"; do
          [ "$capsule" = "$d" ] && known=yes
        done
        if [ "$known" = no ]; then
          echo "no capsule '$capsule' here: the slots this host declares are" >&2
          echo "  ''${declared[*]}, and the devshell path runs one guest between them." >&2
          echo "  More than one at a time is the module path, where the way in is a" >&2
          echo "  relay socket per capsule (README, 'The module path')." >&2
          exit 1
        fi
        sock=${socket}
        if [ -S "$sock" ]; then
          echo "capsule '$capsule' is on the module path here ($sock exists), and this" >&2
          echo "  is the devshell's copy of the program: it would ssh straight to a" >&2
          echo "  guest that is not routable from this namespace. Run the module's:" >&2
          # Bash's own suffix strip rather than basename: a refusal must not need a
          # tool in `runtimeInputs`, or the message becomes "command not found".
          echo "    /run/current-system/sw/bin/''${0##*/} --capsule $capsule ..." >&2
          echo "  or 'just' it, which picks the right copy for you." >&2
          exit 1
        fi
        ssh_cmd=(${lib.escapeShellArgs args})
      '';
  };

  # And the same again for a capsule in a namespace, where the guest is not
  # routable from the root namespace at all: the way in is the relay socket, and
  # that socket path is the capsule's identity.
  #
  # No list of declared names here, unlike `direct`: a probe's throwaway capsule
  # is not an instance and reaches its guest through exactly this fragment, so
  # the socket's existence is the whole check (docs/probes.md).
  #
  # `socket` is a *shell expression*, not a path: the path is a pure function of
  # a name this program only learns at run time, so the call site passes
  # `capsules.socketOf ''"$capsule"''` and the convention keeps exactly one
  # definition. `socat` is passed rather than assumed on PATH, because one caller
  # is a systemd unit.
  viaSocket = {
    socat,
    socket,
  }: {
    inherit selectCapsule;
    transport =
      selectCapsule
      + ''
        sock=${socket}
        if [ ! -S "$sock" ]; then
          echo "no way in to capsule '$capsule': $sock is not a socket." >&2
          echo "  systemctl status capsule-ssh-relay-$capsule" >&2
          exit 1
        fi
        ssh_cmd=(${lib.escapeShellArgs args} -o "ProxyCommand=${socat} - UNIX-CONNECT:$sock")
      '';
  };
}
