# The perimeter: an allowlist egress proxy and a git mirror whose update hook
# confines pushes to refs/heads/capsule/*. This is where nearly all of the
# policy value lives, and none of it knows what kind of jail is on the other
# end of the link — see PLAN_B.md.
#
# INVARIANT: nothing hypervisor-, tap- or platform-specific belongs in here.
# The one thing a caller may inject is `preflight`, for checking whatever has
# to exist before the two services can bind (on firecracker: the tap address).
# If you find yourself reaching for `ip`, a hypervisor name or a Linux-only
# tool below, it belongs at the call site instead.
#
# Runtime configuration is environment, not nix, so the allowlist stays an
# ordinary editable file rather than a store path behind a rebuild. Defaults
# below are relative to CAPSULE_ROOT unless absolute:
#
#   CAPSULE_ROOT       $PWD                        repo root
#   CAPSULE_STATE      .vm/host                    mirror, conf, logs, pid
#   CAPSULE_ALLOWLIST  perimeter/egress-allow.txt  proxy hostname allowlist
#   CAPSULE_REPO       $HOME/dev/doctrine          repo to mirror
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
  # Tools the injected `preflight` needs.
  extraRuntimeInputs ? [],
}: let
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

  host = pkgs.writeShellApplication {
    name = "capsule-host";
    runtimeInputs =
      [pkgs.git pkgs.tinyproxy pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.procps]
      ++ extraRuntimeInputs;
    text = ''
      ${preflight}

      # Nothing here wants privilege, and running it as root would leave the
      # mirror root-owned.
      if [ "$(id -u)" = 0 ]; then
        echo "capsule-host: do not run as root" >&2
        exit 1
      fi

      root="''${CAPSULE_ROOT:-''${MICROVM_SPIKE_ROOT:-$PWD}}"
      state="''${CAPSULE_STATE:-$root/.vm/host}"
      allow="''${CAPSULE_ALLOWLIST:-$root/perimeter/egress-allow.txt}"
      src="''${CAPSULE_REPO:-$HOME/dev/doctrine}"

      # Is something already accepting connections there? A connect probe
      # rather than `ss` or `lsof`, because bash's /dev/tcp is the one
      # mechanism that behaves identically on Linux and macOS. Local
      # addresses refuse instantly, so there is nothing to time out.
      port_in_use() {
        (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null
      }

      # git daemon outlives the SIGINT that kills tinyproxy, so a Ctrl-C and
      # restart would otherwise hit a port it still holds. Match on this state
      # dir: strays from *this* capsule and nothing else.
      # Patterns must not start with a dash: pkill would read them as options.
      for pattern in "tinyproxy -d -c $state/tinyproxy.conf" "base-path=$state"; do
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

      mirror="$state/$(basename "$src").git"
      mkdir -p "$state"

      if [ ! -d "$mirror" ]; then
        echo "capsule-host: mirroring $src"
        git clone --mirror "$src" "$mirror"
      fi

      # Explicit refspec, never `git remote update`: a mirror's default fetch
      # is force+prune and would delete whatever the guest has pushed.
      git -C "$mirror" fetch origin \
        '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*'
      install -m755 ${pushGuard} "$mirror/hooks/update"
      # Two independent guards on what the daemon will serve, since it is
      # unauthenticated and `receive-pack` is enabled: the per-repo marker
      # (which replaces --export-all) and the explicit whitelist below.
      touch "$mirror/git-daemon-export-ok"

      sed -e "s|@ALLOW@|$allow|" -e "s|@STATE@|$state|" \
        ${proxyConf} > "$state/tinyproxy.conf"

      echo "capsule-host: proxy on ${bind}:${toString proxyPort} (allowlist: $allow)"
      echo "capsule-host: git on ${bind}:${toString gitPort} serving $mirror"
      tinyproxy -d -c "$state/tinyproxy.conf" &
      proxy=$!
      # --strict-paths + an explicit repo whitelist: the client may reach
      # exactly this one path, spelled exactly, and no sibling under $state
      # that happens to look like a repo.
      git daemon \
        --base-path="$state" --strict-paths --enable=receive-pack \
        --listen=${bind} --port=${toString gitPort} \
        --reuseaddr --verbose "$mirror" &
      daemon=$!
      # INT/TERM as well as EXIT, and `wait -n` so that either child dying
      # tears the other down instead of leaving it holding a port.
      trap 'kill $proxy $daemon 2>/dev/null' EXIT INT TERM
      wait -n
      echo "capsule-host: a service exited — shutting down" >&2
    '';
  };
in {
  inherit host pushGuard proxyConf;
}
