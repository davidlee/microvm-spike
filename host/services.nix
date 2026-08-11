# The host half of the perimeter, under its own uid and its own resource
# ceilings. NixOS-only by nature, hence here and not in `perimeter/` — it takes
# the proxy `capsule-host` composes and gives it a unit, plus the guard that is
# this path's version of `preflight` and `watch`.
#
# It used to run two services. The other was a git daemon serving a mirror the
# guest pushed to, and it needed a system uid, a shared group, a setgid state
# directory and a `safe.directory` exception to work at all — all of which
# existed to confine a `receive-pack` the host had to run. The host now
# initiates git in both directions instead (`host/git-channel.nix`), so the
# service, the uid, the group, the mirror and the exception are gone rather than
# hardened. NOTES item 18.
#
# What this buys over `capsule-host` (which is kept: it needs no root, no
# rebuild, and is the portable path):
#
#   - tinyproxy is C parsing guest-authored HTTP; as `capsule-host` it runs as
#     you, with ambient access to ~/.ssh, ~/.claude and every repo. Here it gets
#     a system uid holding nothing, plus ProtectHome and a namespace.
#   - it loses the LAN and loopback, keeping only the guest and the resolver.
#   - cgroup ceilings, which nothing had before (NOTES open item 12).
#
# Not here: the nftables drop and the interface-scoped port. Those are the
# host's own config (README "Host requirements") and this module deliberately
# does not restate them — it verifies them, in the guard unit below.
{
  net,
  target,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.capsule-perimeter;

  # Same perimeter, built with the host's pkgs. No preflight/watch: those are
  # for the foreground composition, and the guard unit is this path's version
  # of them. The allowlist comes from the options rather than from `target.nix`,
  # so a host that sets it differently gets what it asked for.
  perimeter = import ../perimeter {
    inherit pkgs;
    bind = net.host;
    client = net.guest;
    inherit (net) proxyPort;
    allowlistFile = target.allowlist;
  };

  # The same two programs the devshell has. Installed system-wide because they
  # are the human's, not any unit's — nothing here runs them, and nothing
  # listens.
  gitChannel = import ./git-channel.nix {
    inherit pkgs target;
    guestRepo = "ssh://agent@${net.guest}${target.guestPath}";
  };

  proxyState = "/var/lib/capsule-proxy";

  # Wrapped, not bare: their defaults are relative to `CAPSULE_ROOT`, which is
  # right for the foreground path and wrong for a program on `$PATH` — run from
  # anywhere, `capsule-collect` would quarantine into `$PWD/.vm/host` instead of
  # this host's state directory. The devshell's copies come first on PATH inside
  # the repo, so that path is unaffected and each keeps its own state. (The same
  # trap `capsule-sync` fell into; NOTES item 11.)
  wrap = name: program:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        export CAPSULE_STATE=${cfg.stateDir}
        export CAPSULE_REPO=${cfg.repo}
        exec ${lib.getExe program} "$@"
      '';
    };

  guard = pkgs.writeShellApplication {
    name = "capsule-perimeter-guard";
    runtimeInputs = [pkgs.iproute2 pkgs.gnugrep pkgs.coreutils];
    text = ''
      ${import ./perimeter-check.nix {
        inherit net;
        # Root here, so no sudo rule is involved on this path.
        nft = lib.getExe pkgs.nftables;
      }}

      case "$(perimeter_state)" in
        dropped) echo "capsule-perimeter-guard: FORWARD drop on ${net.tap} verified" ;;
        latent)
          echo "capsule-perimeter-guard: warning — net.ipv4.ip_forward is 0, so" >&2
          echo "  nothing forwards today, but" >&2
          perimeter_advice
          ;;
        open)
          echo "capsule-perimeter-guard: refusing — net.ipv4.ip_forward is on and" >&2
          perimeter_advice
          exit 1
          ;;
      esac

      tap_up || echo "capsule-perimeter-guard: ${net.tap} has no address yet — the" \
        "proxy will not bind until 'capsule-net up' (or the VM) creates it"

      # BindsTo on the proxy, so exiting takes its egress with it. A preflight
      # alone would only prove the perimeter held at start.
      while sleep 10; do
        forwarding_off && continue
        if ! forward_dropped; then
          echo "capsule-perimeter-guard: net.ipv4.ip_forward went live and" >&2
          perimeter_advice
          echo "  Tearing down egress." >&2
          exit 1
        fi
      done
    '';
  };
in {
  options.services.capsule-perimeter = {
    enable = lib.mkEnableOption "the capsule's host-side egress proxy, under a dedicated uid";

    owner = lib.mkOption {
      type = lib.types.str;
      description = ''
        The human who owns the source repo and runs the git channel. Added to
        the `capsule-proxy` group so the egress log is readable. Never runs the
        service.
      '';
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.owner}/dev/${target.name}";
      defaultText = "/home/\${owner}/dev/\${target.name}";
      description = ''
        Repo `capsule-provision` pushes from, as `owner`. Defaults under
        `owner`'s home rather than to `target.path`, so the module stays right
        on a host whose human is not this one.
      '';
    };

    allowlist = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.owner}/dev/microvm-spike/${target.allowlist}";
      defaultText = "/home/\${owner}/dev/microvm-spike/\${target.allowlist}";
      description = ''
        Proxy hostname allowlist. Deliberately a plain file rather than a store
        path, so changing it needs a service restart and not a rebuild — it is
        bind-mounted read-only into the proxy's namespace.
      '';
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/capsule";
      description = ''
        Holds the quarantine repositories `capsule-collect` fetches into. Owned
        by `owner`: no service touches it, and nothing else has a reason to.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.capsule-proxy = {
      isSystemUser = true;
      group = "capsule-proxy";
      description = "capsule egress proxy";
    };
    # Read-only by ownership: the state directory is 0750 and everything in it
    # 0644, so this buys `owner` the egress log — the record of every attempt,
    # and the first thing you read when the guest cannot reach something — and
    # no write anywhere. `just proxy-log` needing sudo made the record the one
    # part of the perimeter you could not casually look at.
    users.groups.capsule-proxy.members = [cfg.owner];

    # Plain and owner-owned. It was setgid and group-shared when a daemon uid
    # had to write into the same repositories the human read; nothing shares a
    # repository any more, which is the point of item 18.
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.owner} users -"
    ];

    environment.systemPackages = [
      (wrap "capsule-provision" gitChannel.provision)
      (wrap "capsule-collect" gitChannel.collect)
    ];

    # Rotated rather than truncated: it is the record of every egress attempt
    # (NOTES open item 15). copytruncate, so tinyproxy needs no signal.
    services.logrotate.settings.capsule-proxy = {
      files = "${proxyState}/tinyproxy.log";
      frequency = "weekly";
      rotate = 8;
      compress = true;
      copytruncate = true;
      missingok = true;
      notifempty = true;
      # The log's directory is not root-owned, which logrotate declines to
      # rotate blind.
      su = "capsule-proxy capsule-proxy";
    };

    systemd.services = {
      # Root, because reading the nftables ruleset needs CAP_NET_ADMIN. Holds
      # nothing else: no writable path, no network of its own.
      capsule-perimeter-guard = {
        description = "Verify and hold the capsule's host-side perimeter";
        serviceConfig = {
          Type = "simple";
          ExecStart = lib.getExe guard;
          # A refusal must stay a refusal: restarting would flap between
          # tearing egress down and putting it straight back.
          Restart = "no";
          CapabilityBoundingSet = ["CAP_NET_ADMIN"];
          NoNewPrivileges = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          PrivateTmp = true;
          RestrictAddressFamilies = ["AF_NETLINK" "AF_UNIX"];
          IPAddressDeny = "any";
          SystemCallArchitectures = "native";
          MemoryMax = "64M";
          TasksMax = 16;
        };
      };

      capsule-proxy = {
        description = "capsule egress proxy (allowlist)";
        bindsTo = ["capsule-perimeter-guard.service"];
        after = ["capsule-perimeter-guard.service" "network.target" "nss-lookup.target"];
        # The bind address exists only while the tap does. Skipped rather than
        # failed when it doesn't.
        unitConfig.ConditionPathExists = "/sys/class/net/${net.tap}";
        environment = {
          CAPSULE_PROXY_STATE = proxyState;
          CAPSULE_ALLOWLIST = cfg.allowlist;
        };
        # Neither privilege, a device, a namespace nor a second architecture's
        # syscalls. Ceilings rather than working limits: the point is that it
        # cannot take the host down.
        serviceConfig = {
          ExecStart = lib.getExe perimeter.proxy;
          User = "capsule-proxy";
          Group = "capsule-proxy";
          StateDirectory = "capsule-proxy";
          StateDirectoryMode = "0750";
          # tmpfs rather than `true`, so the one file it does need can be
          # bound back in and nothing else in $HOME is visible at all.
          ProtectHome = "tmpfs";
          BindReadOnlyPaths = [cfg.allowlist];
          NoNewPrivileges = true;
          CapabilityBoundingSet = [""];
          AmbientCapabilities = [""];
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectProc = "invisible";
          ProcSubset = "pid";
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectHostname = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = ["@system-service" "~@privileged"];
          MemoryMax = "256M";
          TasksMax = 64;
          CPUQuota = "100%";
          IOWeight = 50;
          Restart = "on-failure";
          RestartSec = "3s";
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
          # It is the egress point, so it cannot be denied by default — but
          # it has no business anywhere private. Most specific match wins, so
          # the guest (and the resolver) survive the denials.
          IPAddressAllow = ["${net.guest}/32" "127.0.0.53/32"];
          IPAddressDeny = [
            "localhost"
            "link-local"
            "multicast"
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "fc00::/7"
          ];
        };
      };
    };
  };
}
