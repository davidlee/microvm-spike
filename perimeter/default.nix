# The perimeter: an allowlist egress proxy. This is where the policy value
# lives, and none of it knows what kind of jail is on the other end of the link
# — see PLAN_B.md.
#
# It used to be two services. The other was a git mirror served to the guest,
# with an update hook confining pushes to `refs/heads/capsule/*` — all of it
# there to confine a `receive-pack` the host had to run because the guest was
# the party that initiated. The host now initiates git in both directions over
# ssh (host/git-channel.nix), so there is no git service, no hook, no mirror and
# no second port. NOTES item 18 has the measurement and what it cost.
#
# INVARIANT: nothing hypervisor-, tap- or platform-specific belongs in here.
# A caller may inject exactly two shell fragments — `preflight`, for whatever
# has to exist before the proxy can bind (on firecracker: the tap address), and
# `watch`, for perimeter state this process does not own and so must keep
# checking (on Linux: the FORWARD drop on the tap). If you find yourself
# reaching for `ip`, `nft`, a hypervisor name or a Linux-only tool below, it
# belongs at the call site instead.
#
# Two programs rather than one, because the service wants its own uid and its
# own systemd unit (host/services.nix) while the foreground `capsule-host`
# composition stays the portable path for a host with no systemd at all:
#
#   proxy  render the tinyproxy config and exec it.
#   host   preflight, then the proxy plus the injected watch, in the
#          foreground, unprivileged.
#
# Runtime configuration is environment, not nix, so the allowlist stays an
# ordinary editable file rather than a store path behind a rebuild. Defaults
# below are relative to CAPSULE_ROOT unless absolute:
#
#   CAPSULE_ROOT         $PWD             repo root
#   CAPSULE_STATE        .vm/host         host-side state
#   CAPSULE_PROXY_STATE  $CAPSULE_STATE   proxy conf, log, pid
#   CAPSULE_ALLOWLIST    $allowlistFile   proxy hostname allowlist
#
# The allowlist comes from the caller (target.nix, via flake.nix or the module's
# options): which repo is confined is no more this file's business than which
# hypervisor is. Nothing here reads the target, and nothing here touches a git
# repository at all.
{
  pkgs,
  # Address the proxy listens on, and the single client permitted to use it. On
  # firecracker these are the two ends of the p2p link; under seatbelt both are
  # loopback.
  bind,
  client,
  proxyPort,
  # The allowlist file, relative to CAPSULE_ROOT. A value, like the addresses
  # above — the caller knows the target, this does not. Stays overridable by
  # environment.
  allowlistFile,
  # Shell fragment run before anything binds. Fail-closed: `exit 1`.
  preflight ? "",
  # Shell fragment supervised alongside the proxy, for perimeter state this
  # process does not own and cannot hold: it must exit nonzero once the
  # platform's perimeter is no longer intact, which tears the proxy down with
  # it. Guest egress stops rather than continuing past a control that has gone.
  # Same rule as `preflight`: nothing platform-shaped in here, it is injected.
  # Forked after `preflight` has run in this shell, so it inherits whatever that
  # defined — the two are expected to share their checks rather than restate
  # them.
  watch ? "",
  # Tools the injected `preflight` / `watch` need.
  extraRuntimeInputs ? [],
}: let
  inherit (pkgs) lib;

  # One definition of where everything is, since both programs have to agree —
  # but each asks for only the variables it uses, because shellcheck runs at
  # build time and an unused one fails it. Emitted in dependency order, so a
  # program that asks for `proxyState` must also ask for `state` and `root`;
  # forgetting one is a build error (SC2154), not a runtime surprise.
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
      text = ''allow="''${CAPSULE_ALLOWLIST:-$root/${allowlistFile}}"'';
    }
  ];

  paths = wanted:
    lib.concatMapStringsSep "\n" (d: d.text)
    (lib.filter (d: lib.elem d.name wanted) pathDefs);

  # @ALLOW@ / @STATE@ are filled in at run time, so the allowlist stays an
  # ordinary editable file rather than a store path behind a rebuild.
  proxyConf = pkgs.writeText "capsule-tinyproxy.conf" ''
    Port ${toString proxyPort}
    Listen ${bind}
    # A client fans out wider than MaxClients and the proxy stops accepting:
    # the kernel completes the handshakes anyway, so the client sees connected
    # sockets and waits forever on a worker that never comes. Observed as
    # `bun install` hanging mid-download with 32 connections queued on the
    # listener — bun's default --network-concurrency is 48, so it deadlocked
    # against 32 workers every time, and looked intermittent because it depends
    # on how many packages are already cached. Keep this above what any one tool
    # opens; it is a slot count, not a security control.
    #
    # Timeout is how long an idle connection holds its slot. 600 meant a
    # finished keep-alive pool occupied workers for ten minutes. Not cut
    # further: a streaming agent response can idle between tokens, and killing
    # those is a worse failure than a slow slot.
    Timeout 300
    MaxClients 128
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

  host = pkgs.writeShellApplication {
    name = "capsule-host";
    runtimeInputs =
      [proxy pkgs.coreutils pkgs.gnugrep pkgs.procps]
      ++ extraRuntimeInputs;
    text = ''
      ${preflight}

      # Nothing here wants privilege, and running it as root would leave the
      # proxy's state root-owned.
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

      # A Ctrl-C that leaves tinyproxy holding the port would make the next
      # start fail its bind. Match on this capsule's own config path: a stray
      # from *this* capsule and nothing else. Patterns must not start with a
      # dash: pkill would read them as options.
      if pkill -f -- "tinyproxy -d -c $proxyState/tinyproxy.conf"; then
        echo "capsule-host: reaped a stray tinyproxy"
      fi

      for _ in 1 2 3 4 5; do
        port_in_use "${bind}" "${toString proxyPort}" || break
        sleep 0.2
      done
      if port_in_use "${bind}" "${toString proxyPort}"; then
        echo "capsule-host: ${bind}:${toString proxyPort} is bound by something else" >&2
        if command -v ss >/dev/null 2>&1; then
          ss -lntp "sport = :${toString proxyPort}" >&2 || true
        elif command -v lsof >/dev/null 2>&1; then
          lsof -nP -iTCP:"${toString proxyPort}" -sTCP:LISTEN >&2 || true
        fi
        exit 1
      fi

      capsule-proxy &
      children=("$!")
      ${lib.optionalString (watch != "") ''
        (
          ${watch}
        ) &
        children+=("$!")
      ''}
      # INT/TERM as well as EXIT, and `wait -n` so that either child dying tears
      # the other down instead of leaving the proxy serving egress past a
      # perimeter that has gone.
      #
      # The pids are named explicitly, and that is load-bearing: bare `wait -n`
      # waits for the next job to *change state*, and a child that exited before
      # the call was already reaped and forgotten. A proxy that failed at bind
      # time therefore left this shell blocked on the watch loop, looking healthy
      # and serving nothing. With pids, bash keeps each status until waited on.
      trap 'kill "''${children[@]}" 2>/dev/null' EXIT INT TERM
      wait -n "''${children[@]}" || true
      echo "capsule-host: a child exited — shutting down" >&2
      exit 1
    '';
  };
in {
  inherit host proxy proxyConf;
}
