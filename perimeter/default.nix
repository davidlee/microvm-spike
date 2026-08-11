# The perimeter: an allowlist egress proxy and a git mirror whose update hook
# confines pushes to refs/heads/capsule/*. This is where nearly all of the
# policy value lives, and none of it knows what kind of jail is on the other
# end of the link — see PLAN_B.md.
#
# INVARIANT: nothing hypervisor-, tap- or platform-specific belongs in here.
# A caller may inject exactly two shell fragments — `preflight`, for whatever
# has to exist before the two services can bind (on firecracker: the tap
# address), and `watch`, for perimeter state this process does not own and so
# must keep checking (on Linux: the FORWARD drop on the tap). If you find
# yourself reaching for `ip`, `nft`, a hypervisor name or a Linux-only tool
# below, it belongs at the call site instead.
#
# Four programs rather than one, because the two services want separate uids
# and separate systemd units (host/services.nix) while the foreground
# `capsule-host` composition stays the portable path for a host with no
# systemd at all:
#
#   sync   create/refresh the mirror, install the ref guard. Runs as the human:
#          it is the only part that reads the real repo.
#   proxy  render the tinyproxy config and exec it.
#   gitd   exec git daemon over the mirror.
#   host   preflight, then all three plus the injected watch, in the
#          foreground, unprivileged.
#
# Runtime configuration is environment, not nix, so the allowlist stays an
# ordinary editable file rather than a store path behind a rebuild. Defaults
# below are relative to CAPSULE_ROOT unless absolute:
#
#   CAPSULE_ROOT         $PWD                        repo root
#   CAPSULE_STATE        .vm/host                    mirror
#   CAPSULE_PROXY_STATE  $CAPSULE_STATE              proxy conf, log, pid
#   CAPSULE_ALLOWLIST    perimeter/egress-allow.txt  proxy hostname allowlist
#   CAPSULE_REPO         $HOME/dev/doctrine          repo to mirror
{
  pkgs,
  # Address the two services listen on, and the single client permitted to use
  # the proxy. On firecracker these are the two ends of the p2p link; under
  # seatbelt both are loopback.
  bind,
  client,
  proxyPort,
  gitPort,
  # Shell fragment run before anything binds. Fail-closed: `exit 1`.
  preflight ? "",
  # Shell fragment supervised alongside the two services, for perimeter state
  # this process does not own and cannot hold: it must exit nonzero once the
  # platform's perimeter is no longer intact, which tears the services down
  # with it. Guest egress stops rather than continuing past a control that
  # has gone missing. Same rule as `preflight`: nothing platform-shaped in
  # here, it is injected. Forked after `preflight` has run in this shell, so
  # it inherits whatever that defined — the two are expected to share their
  # checks rather than restate them.
  watch ? "",
  # Tools the injected `preflight` / `watch` need.
  extraRuntimeInputs ? [],
}: let
  inherit (pkgs) lib;

  # One definition of where everything is, since four programs have to agree —
  # but each asks for only the variables it uses, because shellcheck runs at
  # build time and an unused one fails it. Emitted in dependency order, so a
  # program that asks for `mirror` must also ask for `state` and `src`;
  # forgetting one is a build error (SC2154), not a runtime surprise.
  #
  # `${HOME:-}` because a systemd unit has no HOME and `set -u` is on; the
  # units pass CAPSULE_REPO explicitly, which is what the mirror's name is
  # derived from.
  pathDefs = [
    {
      name = "root";
      text = ''root="''${CAPSULE_ROOT:-''${MICROVM_SPIKE_ROOT:-$PWD}}"'';
    }
    {
      name = "state";
      text = ''state="''${CAPSULE_STATE:-$root/.vm/host}"'';
    }
    {
      name = "proxyState";
      text = ''proxyState="''${CAPSULE_PROXY_STATE:-$state}"'';
    }
    {
      name = "allow";
      text = ''allow="''${CAPSULE_ALLOWLIST:-$root/perimeter/egress-allow.txt}"'';
    }
    {
      name = "src";
      text = ''src="''${CAPSULE_REPO:-''${HOME:-}/dev/doctrine}"'';
    }
    {
      name = "mirror";
      text = ''mirror="$state/$(basename "$src").git"'';
    }
  ];

  paths = wanted:
    lib.concatMapStringsSep "\n" (d: d.text)
    (lib.filter (d: lib.elem d.name wanted) pathDefs);

  # Guests may only push to refs/heads/capsule/* — the mirror's own history is
  # not theirs to rewrite. Server-side, so it holds regardless of what the
  # client is or what it believes about itself.
  pushGuard = pkgs.writeShellScript "capsule-push-guard" ''
    case "$1" in
      refs/heads/capsule/*) exit 0 ;;
    esac
    echo "capsule: pushes are restricted to refs/heads/capsule/*" >&2
    exit 1
  '';

  # @ALLOW@ / @STATE@ are filled in at run time, so the allowlist stays an
  # ordinary editable file rather than a store path behind a rebuild.
  proxyConf = pkgs.writeText "capsule-tinyproxy.conf" ''
    Port ${toString proxyPort}
    Listen ${bind}
    Timeout 600
    MaxClients 32
    Allow ${client}
    ConnectPort 443
    Filter "@ALLOW@"
    FilterDefaultDeny Yes
    # `ere`, not `extended` — tinyproxy takes bre|ere|fnmatch and refuses to
    # start on anything else. (`FilterExtended Yes` is the deprecated spelling.)
    FilterType ere
    FilterCaseSensitive No
    LogLevel Info
    LogFile "@STATE@/tinyproxy.log"
    PidFile "@STATE@/tinyproxy.pid"
  '';

  # The only program that touches the real repo, and the only one that has to
  # run as the human who owns it — which is the point: the daemon uid serving
  # the mirror never gets read access to the tree the mirror came from.
  sync = pkgs.writeShellApplication {
    name = "capsule-sync";
    runtimeInputs = [pkgs.git pkgs.coreutils];
    text = ''
      ${paths ["root" "state" "src" "mirror"]}

      # The mirror is group-owned by the daemon's uid under systemd, so it can
      # accept the guest's pushes while staying readable to whoever fetches
      # them out. Harmless on the foreground path, where both are you.
      umask 002
      mkdir -p "$state"

      if [ ! -d "$mirror" ]; then
        echo "capsule-sync: mirroring $src"
        # sharedRepository=group so git itself keeps the mirror
        # group-writable, rather than leaving it to umask on every path that
        # creates a file. Under systemd that group is the daemon's; on the
        # foreground path it is yours, where it changes nothing.
        git clone --mirror --config core.sharedRepository=group "$src" "$mirror"
      fi

      # Explicit refspec, never `git remote update`: a mirror's default fetch
      # is force+prune and would delete whatever the guest has pushed.
      git -C "$mirror" fetch origin \
        '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'
      install -m755 ${pushGuard} "$mirror/hooks/update"
      # Two independent guards on what the daemon will serve, since it is
      # unauthenticated and `receive-pack` is enabled: the per-repo marker
      # (which replaces --export-all) and the explicit whitelist in gitd.
      touch "$mirror/git-daemon-export-ok"
      echo "capsule-sync: $mirror"
    '';
  };

  proxy = pkgs.writeShellApplication {
    name = "capsule-proxy";
    runtimeInputs = [pkgs.tinyproxy pkgs.gnused pkgs.coreutils];
    text = ''
      ${paths ["root" "state" "proxyState" "allow"]}

      mkdir -p "$proxyState"
      sed -e "s|@ALLOW@|$allow|" -e "s|@STATE@|$proxyState|" \
        ${proxyConf} > "$proxyState/tinyproxy.conf"

      echo "capsule-proxy: ${bind}:${toString proxyPort} (allowlist: $allow)"
      # -d: foreground, so systemd and the foreground composition can both
      # supervise it directly.
      exec tinyproxy -d -c "$proxyState/tinyproxy.conf"
    '';
  };

  gitd = pkgs.writeShellApplication {
    name = "capsule-gitd";
    runtimeInputs = [pkgs.git];
    text = ''
      ${paths ["root" "state" "src" "mirror"]}

      if [ ! -d "$mirror" ]; then
        echo "capsule-gitd: no mirror at $mirror — run capsule-sync first" >&2
        exit 1
      fi

      echo "capsule-gitd: ${bind}:${toString gitPort} serving $mirror"
      # --strict-paths + an explicit repo whitelist: the client may reach
      # exactly this one path, spelled exactly, and no sibling under $state
      # that happens to look like a repo.
      exec git daemon \
        --base-path="$state" --strict-paths --enable=receive-pack \
        --listen=${bind} --port=${toString gitPort} \
        --reuseaddr --verbose "$mirror"
    '';
  };

  host = pkgs.writeShellApplication {
    name = "capsule-host";
    runtimeInputs =
      [sync proxy gitd pkgs.coreutils pkgs.gnugrep pkgs.procps]
      ++ extraRuntimeInputs;
    text = ''
      ${preflight}

      # Nothing here wants privilege, and running it as root would leave the
      # mirror root-owned.
      if [ "$(id -u)" = 0 ]; then
        echo "capsule-host: do not run as root" >&2
        exit 1
      fi

      ${paths ["root" "state" "proxyState"]}

      # Is something already accepting connections there? A connect probe
      # rather than `ss` or `lsof`, because bash's /dev/tcp is the one
      # mechanism that behaves identically on Linux and macOS. Local
      # addresses refuse instantly, so there is nothing to time out.
      port_in_use() {
        (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null
      }

      # git daemon outlives the SIGINT that kills tinyproxy, so a Ctrl-C and
      # restart would otherwise hit a port it still holds. Match on this
      # capsule's own paths: strays from *this* capsule and nothing else.
      # Patterns must not start with a dash: pkill would read them as options.
      for pattern in "tinyproxy -d -c $proxyState/tinyproxy.conf" "base-path=$state"; do
        if pkill -f -- "$pattern"; then
          echo "capsule-host: reaped a stray ($pattern)"
        fi
      done

      for port in ${toString proxyPort} ${toString gitPort}; do
        for _ in 1 2 3 4 5; do
          port_in_use "${bind}" "$port" || break
          sleep 0.2
        done
        if port_in_use "${bind}" "$port"; then
          echo "capsule-host: ${bind}:$port is bound by something else" >&2
          if command -v ss >/dev/null 2>&1; then
            ss -lntp "sport = :$port" >&2 || true
          elif command -v lsof >/dev/null 2>&1; then
            lsof -nP -iTCP:"$port" -sTCP:LISTEN >&2 || true
          fi
          exit 1
        fi
      done

      capsule-sync

      capsule-proxy &
      children=("$!")
      capsule-gitd &
      children+=("$!")
      ${lib.optionalString (watch != "") ''
        (
          ${watch}
        ) &
        children+=("$!")
      ''}
      # INT/TERM as well as EXIT, and `wait -n` so that any child dying tears
      # the others down instead of leaving one holding a port — or, for the
      # watch, serving egress past a perimeter that has gone.
      trap 'kill "''${children[@]}" 2>/dev/null' EXIT INT TERM
      wait -n || true
      echo "capsule-host: a service exited — shutting down" >&2
      exit 1
    '';
  };
in {
  inherit host sync proxy gitd pushGuard proxyConf;
}
