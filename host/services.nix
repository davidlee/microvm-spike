# The host half of the perimeter, under its own uids and its own resource
# ceilings. NixOS-only by nature, hence here and not in `perimeter/` — it takes
# the same four programs that `capsule-host` composes and gives each a unit.
#
# What this buys over `capsule-host` (which is kept: it needs no root, no
# rebuild, and is the portable path):
#
#   - tinyproxy is C parsing guest-authored HTTP and git-daemon runs
#     `receive-pack`; as `capsule-host` both run as you, with ambient access to
#     ~/.ssh, ~/.claude and every repo. Here each gets a system uid holding
#     nothing, plus ProtectHome and a namespace.
#   - git-daemon gets `IPAddressDeny=any` with only the guest allowed, so a
#     compromise cannot dial out at all. The proxy must reach the internet, so
#     it instead loses the LAN and loopback.
#   - the mirror is *never* refreshed by the daemon's uid: `capsule-sync` runs
#     as you, and is the only thing that reads the target repo. The serving uid
#     has no path to the tree the mirror came from.
#   - cgroup ceilings, which nothing had before (NOTES open item 12).
#
# Not here: the nftables drop and the interface-scoped ports. Those are the
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
  # of them. Target paths come from the options rather than from `target.nix`,
  # so a host that sets them differently gets what it asked for.
  perimeter = import ../perimeter {
    inherit pkgs;
    bind = net.host;
    client = net.guest;
    inherit (net) proxyPort gitPort;
    repo = cfg.repo;
    allowlistFile = target.allowlist;
  };

  proxyState = "/var/lib/capsule-proxy";

  # `repo` is baked into the programs above, so it is deliberately not here:
  # one value, one place. These are the paths that differ from the foreground
  # path's defaults, which are relative to a repo root no unit has.
  env = {
    CAPSULE_STATE = cfg.stateDir;
    CAPSULE_PROXY_STATE = proxyState;
    CAPSULE_ALLOWLIST = cfg.allowlist;
  };

  # Hardening common to both services. Neither needs privilege, a device, a
  # namespace or a second architecture's syscalls.
  confined = {
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
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    # Not `~@resources` as well: git's helpers do touch rlimits, and a filter
    # that breaks receive-pack would get turned off wholesale.
    SystemCallFilter = ["@system-service" "~@privileged"];
    # Ceilings, not working limits: the point is that neither service can take
    # the host down. MemoryMax is per-service — `pack-objects` on a real clone
    # is not small.
    TasksMax = 64;
    CPUQuota = "100%";
    IOWeight = 50;
    Restart = "on-failure";
    RestartSec = "3s";
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
        "services will not bind until 'capsule-net up' (or the VM) creates it"

      # BindsTo on both services, so exiting takes their egress with it. A
      # preflight alone would only prove the perimeter held at start.
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
    enable = lib.mkEnableOption "the capsule's host-side proxy and git mirror, under dedicated uids";

    owner = lib.mkOption {
      type = lib.types.str;
      description = ''
        The human who owns the source repo. Runs `capsule-sync`, and is added
        to the `capsule-git` group so `capsule/*` branches can be fetched back
        out of the mirror. Never runs either service.
      '';
    };

    repo = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.owner}/dev/${target.name}";
      defaultText = "/home/\${owner}/dev/\${target.name}";
      description = ''
        Repo to mirror. Read by `capsule-sync` only, as `owner`. Defaults under
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
      description = "Holds the bare mirror. Group-owned by `capsule-git`, setgid.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.capsule-git = {
      isSystemUser = true;
      group = "capsule-git";
      description = "capsule git mirror daemon";
    };
    users.users.capsule-proxy = {
      isSystemUser = true;
      group = "capsule-proxy";
      description = "capsule egress proxy";
    };
    # `owner` is a member so it can sync the mirror and fetch the guest's
    # branches back out. Read and write of the mirror; nothing else.
    users.groups.capsule-git.members = [cfg.owner];
    # Read-only by ownership: the state directory is 0750 and everything in it
    # 0644, so this buys `owner` the egress log — the record of every attempt,
    # and the first thing you read when the guest cannot reach something — and
    # no write anywhere. `just proxy-log` needing sudo made the record the one
    # part of the perimeter you could not casually look at.
    users.groups.capsule-proxy.members = [cfg.owner];

    # Setgid, so objects the guest pushes stay group-owned and `owner` can
    # fetch them out. Created here rather than by StateDirectory= because
    # `capsule-sync` runs before either service and needs it to exist.
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 2775 capsule-git capsule-git -"
    ];

    # Wrapped, not `perimeter.sync` bare: unwrapped it defaults the mirror to
    # `$PWD/.vm/host` — the foreground path's — so running it to feed the units
    # would quietly build a second mirror wherever you happened to be standing.
    # The devshell's copy comes first on PATH inside the repo, so `capsule-host`
    # is unaffected; both print the mirror they used.
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "capsule-sync";
        text = ''
          export CAPSULE_STATE=${cfg.stateDir}
          exec ${lib.getExe perimeter.sync} "$@"
        '';
      })
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

      capsule-gitd = {
        description = "capsule git mirror daemon";
        bindsTo = ["capsule-perimeter-guard.service"];
        after = ["capsule-perimeter-guard.service" "network.target"];
        # The bind address exists only while the tap does. Skipped rather than
        # failed when it doesn't.
        unitConfig.ConditionPathExists = "/sys/class/net/${net.tap}";
        environment = env;
        serviceConfig =
          confined
          // {
            ExecStart = lib.getExe perimeter.gitd;
            User = "capsule-git";
            Group = "capsule-git";
            ProtectHome = true; # the source tree is not this uid's business
            ReadWritePaths = [cfg.stateDir];
            # A clone of real history repacks; 512M would OOM it.
            MemoryMax = "2G";
            # Group-writable, so `owner` can sync into what the guest pushed.
            UMask = "0002";
            RestrictAddressFamilies = ["AF_INET" "AF_UNIX"];
            # The guest is the only peer it may ever speak to. `receive-pack`
            # running with no way out is most of the value here.
            IPAddressAllow = ["${net.guest}/32"];
            IPAddressDeny = "any";
          };
      };

      capsule-proxy = {
        description = "capsule egress proxy (allowlist)";
        bindsTo = ["capsule-perimeter-guard.service"];
        after = ["capsule-perimeter-guard.service" "network.target" "nss-lookup.target"];
        unitConfig.ConditionPathExists = "/sys/class/net/${net.tap}";
        environment = env;
        serviceConfig =
          confined
          // {
            ExecStart = lib.getExe perimeter.proxy;
            User = "capsule-proxy";
            Group = "capsule-proxy";
            StateDirectory = "capsule-proxy";
            StateDirectoryMode = "0750";
            # tmpfs rather than `true`, so the one file it does need can be
            # bound back in and nothing else in $HOME is visible at all.
            ProtectHome = "tmpfs";
            BindReadOnlyPaths = [cfg.allowlist];
            MemoryDenyWriteExecute = true;
            MemoryMax = "256M";
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
