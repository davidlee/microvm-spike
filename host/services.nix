# The host half of the perimeter, under its own uid and its own resource
# ceilings, with every capsule in its own network namespace. NixOS-only by
# nature, hence here and not in `perimeter/` — it takes the proxy `capsule-host`
# composes and gives it a unit, plus the guard that is this path's version of
# `preflight` and `watch`.
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
#   - **a namespace per capsule** (`host/netns.nix`), which is what makes more
#     than one of them possible: identical addressing, one guest image, and a
#     forwarding switch that is ours rather than the host's.
#
# Not here: the nftables drop on the devshell path's tap, the interface-scoped
# port, and the sudoers rule that makes the drop readable. Those are the host's
# own config (README "Host requirements") and belong to the *tap* shape, which
# this path no longer uses.
{
  net,
  target,
  capsules,
  # The guest's branch, threaded through to the git channel exactly as the
  # devshell path does it (flake.nix): the installed programs and the guest image
  # have to agree on it, and neither of them may spell it.
  workBranch,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.capsule-perimeter;

  netns = import ./netns.nix {inherit pkgs lib net capsules;};

  instances = lib.attrValues capsules.instances;
  inherit (capsules) egress;

  # Every capsule runs the same VM closure from the same store path, so a unit
  # name is the *instance's* name and never a second VM.
  unitOf = prefix: c: "${prefix}-${c.name}.service";
  netnsUnit = unitOf "capsule-netns";
  proxyUnit = unitOf "capsule-proxy";
  relayUnit = unitOf "capsule-ssh-relay";
  tapUnit = c: "microvm-tap-interfaces@${c.name}.service";

  egressUnit = "capsule-egress-ns.service";
  guardUnit = "capsule-perimeter-guard.service";

  # Same perimeter, built with the host's pkgs, once — it is identical for every
  # capsule, because every capsule has the identical tap address. Only the
  # namespace and the state directory differ. No preflight/watch: those are for
  # the foreground composition, and the guard unit is this path's version of
  # them. The allowlist comes from the options rather than from `target.nix`,
  # so a host that sets it differently gets what it asked for.
  perimeter = import ../perimeter {
    inherit pkgs;
    bind = net.host;
    client = net.guest;
    inherit (net) proxyPort;
    allowlistFile = target.allowlist;
  };

  # The guest is not routable from the root namespace any more, so the human's
  # programs reach it the way `just ssh` does: a ProxyCommand against the
  # capsule's relay socket.
  #
  # One set of programs for every capsule, because the socket path is the only
  # thing that differs between two of them and it is derivable from the name —
  # `capsules.socketOf` applied to a shell expression, so the convention still
  # has one definition and this file still learns nothing about namespaces.
  # These were built for the lowest-indexed capsule until N=2 made that a bug:
  # four programs with one capsule's transport in their store paths, and no way
  # in to a second.
  guestSsh = import ./guest-ssh.nix {inherit lib;};

  hostPrograms = import ./programs.nix {
    inherit pkgs net target workBranch;
    transport = guestSsh.viaSocket {
      socat = "${pkgs.socat}/bin/socat";
      socket = capsules.socketOf ''"$capsule"'';
    };
  };

  # The front end the human on this host actually types: `capsule <name> <verb>`.
  # It carries no transport — it resolves a name and execs the four programs and
  # the systemctl verbs — so this is the *same store path* the devshell installs
  # rather than a second instantiation, which is the honest way to say that this
  # is the one thing about a capsule that does not differ between the two paths.
  cli = import ./cli.nix {
    inherit pkgs lib net target capsules guestSsh;
    programVerbs =
      ["provision" "collect" "inject"]
      ++ lib.optional (hostPrograms.baseline != null) "baseline";
  };

  # The one program that runs at guest *root*, and the reason a stop on this
  # path is not a power cut. No transport: it is an `ExecStop` on the VM's own
  # unit, so it is already in that capsule's namespace and the guest is one hop
  # away — which is also why it needs no capsule name. Its identity cannot be
  # the human's: the unit runs as `microvm` with no agent and no access to her
  # home, so the host keeps a key of its own (`stopKey`).
  halt = import ./halt.nix {inherit pkgs net guestSsh;};

  # A script rather than a `bash -c '…'` in the unit, and that is not a style
  # choice: a **newline inside a unit directive is unbalanced quoting**, and
  # systemd's answer is to ignore that directive *and* the rest of the drop-in
  # with it. This one spent its whole first rebuild dropping the namespace, the
  # `ExecStop` and `Restart=no` that follow it — so every capsule booted in the
  # root namespace, found no tap and crash-looped, while every other unit and
  # the guard said the perimeter was intact (CLAUDE.md). One store path is one
  # token, and shellcheck reads it on the way past.
  stopKeyCheck = pkgs.writeShellApplication {
    name = "capsule-stop-key-check";
    text = ''
      test -r ${cfg.stopKey} || {
        echo "no stop key at ${cfg.stopKey}: this capsule could only be power-cut. See README, 'Host requirements'." >&2
        exit 1
      }
    '';
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

  # One guard for every capsule, and it holds all of them: a `BindsTo` that only
  # tears some of them down is worse than no guard, because the survivors look
  # healthy. Every question is asked of the running kernel in the namespace that
  # owns the answer — see host/netns.nix for why there is no `latent` state left.
  guard = pkgs.writeShellApplication {
    name = "capsule-perimeter-guard";
    runtimeInputs = [pkgs.iproute2 pkgs.procps pkgs.gnugrep pkgs.coreutils];
    text = ''
      ${netns.check}

      namespaces=(${lib.concatMapStringsSep " " (c: ''"${c.ns}"'') instances})

      audit() {
        local ns bad=0

        ns_present "${egress.ns}" || bad=1
        # Capsule to capsule, and capsule to the host's own networks. The
        # resolver is allowed narrowly ahead of the second one, which is what
        # makes the pair testable: DNS works, a ping to the same address does
        # not.
        ns_rule "${egress.ns}" capsule-egress \
          'iifname "${egress.linkPattern}" oifname "${egress.linkPattern}" drop' || bad=1
        ns_rule "${egress.ns}" capsule-egress \
          'ip saddr ${capsules.uplinkNet}' || bad=1

        for ns in "''${namespaces[@]}"; do
          ns_present "$ns" || {
            bad=1
            continue
          }
          ns_not_forwarding "$ns" || bad=1
          # The guest reaching a service in its own namespace is INPUT, not
          # forward, so no forwarding switch covers it (probe/netns.sh, cost 1).
          ns_rule "$ns" capsule-guard \
            'iifname "${net.tap}" ip daddr != ${net.host} drop' || bad=1
        done

        return "$bad"
      }

      if ! audit; then
        echo "capsule-perimeter-guard: refusing — the perimeter above is not intact." >&2
        exit 1
      fi
      echo "capsule-perimeter-guard: ${toString (builtins.length instances)} capsule namespace(s) verified"

      # BindsTo on every proxy, so exiting takes their egress with it. A
      # preflight alone would only prove the perimeter held at start.
      while sleep 10; do
        audit && continue
        echo "capsule-perimeter-guard: the perimeter changed under us. Tearing down egress." >&2
        exit 1
      done
    '';
  };

  # ------------------------------------------------------------------- units

  perInstance = f: lib.listToAttrs (map f instances);

  proxyServices = perInstance (c: {
    name = "capsule-proxy-${c.name}";
    value = {
      description = "capsule egress proxy (allowlist) — ${c.name}";
      # The guard holds the perimeter; the tap holds the address this binds.
      # Neither is a condition, because a condition is evaluated by PID 1 in the
      # *root* namespace and this tap is not there.
      bindsTo = [guardUnit (tapUnit c)];
      requires = [(netnsUnit c)];
      after = [guardUnit (netnsUnit c) (tapUnit c)];
      environment = {
        CAPSULE_PROXY_STATE = "${proxyState}/${c.name}";
        CAPSULE_ALLOWLIST = cfg.allowlist;
      };
      # Neither privilege, a device, a namespace nor a second architecture's
      # syscalls. Ceilings rather than working limits: the point is that it
      # cannot take the host down.
      serviceConfig = {
        ExecStart = lib.getExe perimeter.proxy;
        User = "capsule-proxy";
        Group = "capsule-proxy";
        StateDirectory = "capsule-proxy/${c.name}";
        StateDirectoryMode = "0750";
        # The namespace is the capsule. Same bind address in every one of them,
        # which is the whole point: one guest image, no addressing per instance.
        NetworkNamespacePath = netns.nsPath c.ns;
        # `ip netns exec` bind-mounts /etc/netns/<ns>/resolv.conf over
        # /etc/resolv.conf; systemd does not, and the host's stub on 127.0.0.53
        # is not reachable from here — loopback is per-namespace. Without this
        # line tinyproxy resolves nothing and every request 403s as if the
        # allowlist had denied it.
        BindReadOnlyPaths = [cfg.allowlist "${netns.resolvConf c.ns}:/etc/resolv.conf"];
        # tmpfs rather than `true`, so the one file it does need can be
        # bound back in and nothing else in $HOME is visible at all.
        ProtectHome = "tmpfs";
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
        # It is the egress point, so it cannot be denied by default — but it
        # has no business anywhere private. Most specific match wins, so the
        # guest and the resolver survive the denials. The uplink gateway is
        # absent on purpose: it is a router, not a destination.
        IPAddressAllow = ["${net.guest}/32" "${netns.resolver}/32"];
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
  });

  # The way in, and the reason `just ssh` needs no privilege: `ip netns exec`
  # wants CAP_SYS_ADMIN, but the filesystem is not namespaced, so a socket
  # inside the namespace is reachable from the human's shell. The socket path is
  # also the capsule's identity, which is what keeps N guests at one address out
  # of `known_hosts` (NOTES item 17).
  relayServices = perInstance (c: {
    name = "capsule-ssh-relay-${c.name}";
    value = {
      description = "ssh into capsule ${c.name}, over a unix socket";
      # The tap as well as the namespace, and the tap is the load-bearing half:
      # a namespace unit is `active exited` and *stays* up, which is right for a
      # namespace and wrong for the way into a guest. Bound to the namespace
      # alone, this relay outlived every stopped capsule — and the socket is not
      # just a convenience, it is the test every host program uses to decide
      # which copy of itself to run (host/guest-ssh.nix). So a dead capsule read
      # as "the module path owns this one", the devshell's copies refused, and
      # the module's copy accepted the unix connection and then blocked forwarding
      # into a namespace where nothing listens. `ConnectTimeout` bounds that, but
      # a bounded lie is still a lie. The tap is what a VM pulls up and takes
      # down, so binding to it is what the proxy already does, for the same
      # reason.
      bindsTo = [(netnsUnit c) (tapUnit c)];
      after = [(netnsUnit c) (tapUnit c)];
      serviceConfig = {
        # `nodelay` because socat does not set TCP_NODELAY and ssh cannot set it
        # on a socket it did not open, so Nagle clumps keystroke echo on this leg
        # (docs/probes.md, "keystroke echo through the relay socket"). Interactive
        # traffic is all this socket carries, so nothing here wants coalescing.
        ExecStart = "${pkgs.socat}/bin/socat UNIX-LISTEN:${c.socket},fork,mode=0600 TCP:${net.guest}:22,nodelay";
        # As the human, so the socket is hers and no sudo stands between her and
        # the guest. It carries no privilege of its own: one socket, one
        # destination, and nothing else reachable.
        User = cfg.owner;
        RuntimeDirectory = "capsule/${c.name}";
        RuntimeDirectoryMode = "0700";
        NetworkNamespacePath = netns.nsPath c.ns;
        UMask = "0077";
        NoNewPrivileges = true;
        CapabilityBoundingSet = [""];
        AmbientCapabilities = [""];
        ProtectHome = "tmpfs";
        ProtectSystem = "strict";
        PrivateTmp = true;
        PrivateDevices = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@privileged"];
        RestrictAddressFamilies = ["AF_INET" "AF_UNIX"];
        # socat catches SIGTERM and exits 143 itself rather than dying of it, so
        # every ordinary stop left this unit `failed` — which spends the one
        # signal that is supposed to mean the perimeter is wrong.
        SuccessExitStatus = "143";
        IPAddressAllow = ["${net.guest}/32"];
        IPAddressDeny = "any";
        MemoryMax = "64M";
        TasksMax = 32;
        Restart = "on-failure";
        RestartSec = "3s";
      };
    };
  });

  netnsServices = perInstance (c: {
    name = "capsule-netns-${c.name}";
    value = {
      description = "network namespace for capsule ${c.name}";
      requires = [egressUnit];
      after = [egressUnit];
      # The tap is created *inside* here, so nothing ever moves a tap under a
      # running VM.
      before = [(tapUnit c)];
      environment = netns.capsuleEnv c;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe netns.programs.capsule} up";
        ExecStop = "${lib.getExe netns.programs.capsule} down";
      };
    };
  });

  # microvm.nix emits its own per-name drop-ins for these two, so this uses the
  # mechanism the module itself uses in-tree — and there is no `%i` expansion to
  # gamble on. Inert until the VM exists, which is `microvm -c <name>` and
  # deliberately not `microvm.vms.<name>`: declaring it would make the host's
  # config evaluate the guest closure, and `~/flakes` is fetchable from a
  # machine the target repo does not exist on (README, "The module path").
  vmDropins =
    perInstance (c: {
      name = "microvm-tap-interfaces@${c.name}";
      value = {
        overrideStrategy = "asDropin";
        requires = [(netnsUnit c)];
        after = [(netnsUnit c)];
        serviceConfig = {
          NetworkNamespacePath = netns.nsPath c.ns;
          # microvm.nix's `tap-up` creates the tap and brings it up; it knows
          # nothing about addresses, and the address cannot exist before the tap
          # does. Runs in the namespace, because the unit is already joined.
          ExecStartPost = "${lib.getExe netns.programs.capsule} addr";
        };
        environment = netns.capsuleEnv c;
      };
    })
    // perInstance (c: {
      name = "microvm@${c.name}";
      value = {
        overrideStrategy = "asDropin";
        requires = [(netnsUnit c)];
        after = [(netnsUnit c)];
        # Boot a capsule and its perimeter comes with it. Not `requires`: a
        # guest with no proxy reaches nothing, which is safe, and a capsule that
        # will not start because its proxy will not is worse than one with no
        # egress.
        wants = [(proxyUnit c) (relayUnit c)];
        serviceConfig = {
          NetworkNamespacePath = netns.nsPath c.ns;
          # Refusing to start what it cannot stop cleanly. Runs as the unit's
          # own user, which is the uid that will have to read the key at stop
          # time — root being able to read it proves nothing. The alternative is
          # discovering it during a host shutdown, which is the one moment
          # nobody is watching and every capsule is mounted.
          ExecStartPre = lib.getExe stopKeyCheck;
          # A stop is two acts and microvm.nix only has the second. Its
          # `ExecStop` is `microvm-shutdown`: `SendCtrlAltDel`, which this guest
          # has no keyboard to receive (host/halt.nix), and then a `socat` on
          # the API socket that blocks until firecracker exits. So the list is
          # cleared and rebuilt with the request in front of the wait — ask the
          # guest to reboot, then let their own command block until the VMM is
          # gone. `-` because a guest that cannot answer must not skip the wait
          # and the teardown behind it; the timeout is what covers that case.
          ExecStop = [
            ""
            "-${lib.getExe halt} --identity ${cfg.stopKey}"
            "/var/lib/microvms/${c.name}/booted/bin/microvm-shutdown"
          ];
          # `Restart = always` is microvm.nix's default and it fights a
          # deliberate stop.
          Restart = "no";
          # Generous on purpose: what the timeout produces is the power cut this
          # whole path exists to avoid, and the guest is unmounting a volume
          # that may be carrying a cold build.
          TimeoutStopSec = "120s";
        };
      };
    });
in {
  options.services.capsule-perimeter = {
    enable = lib.mkEnableOption "the capsule's host-side egress proxy, under a dedicated uid";

    owner = lib.mkOption {
      type = lib.types.str;
      description = ''
        The human who owns the source repo and runs the git channel. Added to
        the `capsule-proxy` group so the egress log is readable, and owns each
        capsule's ssh relay socket. Never runs the proxy.
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

    stopKey = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/capsule-stop/key";
      description = ''
        Private half of the key that asks a guest to shut down, read by the
        `microvm` uid at `ExecStop`. Its own directory rather than `stateDir`,
        which is the human's and closed to everyone else.

        Not in the store, and not the human's key: a unit has no ssh agent, and
        a key it holds should not be one whose passphrase or rotation is a
        person's business. Generated once by hand (README, "Host requirements");
        its public half is in the guest's closure, so replacing it is a guest
        rebuild.
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

  config = lib.mkIf cfg.enable (lib.mkMerge [
    netns.hostConfig
    {
      # A capsule resolves through the host's stub or it resolves through
      # nothing: the fallback that would make it work anyway is a public
      # resolver, which quietly drops the DoT chain.
      assertions = [
        {
          assertion = config.services.resolved.enable;
          message = "services.capsule-perimeter needs systemd-resolved: a capsule's only resolver is the stub on ${netns.resolver}.";
        }
        {
          assertion = instances != [];
          message = "services.capsule-perimeter is enabled but capsules.nix declares no capsules.";
        }
      ];

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
        # The directory is made; the key is not. `z` only corrects what is
        # already there, so a host that has not been given a stop key is refused
        # at VM start with a message, rather than handed a generated key that
        # no guest closure knows about.
        "d ${builtins.dirOf cfg.stopKey} 0755 root root -"
        "z ${cfg.stopKey} 0400 microvm kvm -"
      ];

      # Only the two that keep state need wrapping; `capsule-inject` and
      # `capsule-baseline` write nothing host-side, so they go on PATH as they
      # are. All four reach the guest through a relay socket, which is the only
      # way in on this path — `--capsule <name>` or `CAPSULE_NAME` picks whose,
      # and there is no fallback: a slot's name says nothing about what is in it,
      # so a program with a default acts on a slot nobody chose. `capsule` itself
      # resolves an unnamed invocation from what is running (host/cli.nix).
      environment.systemPackages =
        [
          # Wrapped for the same reason the two stateful programs are, and it is the
          # same wrapper: `capsule <name> fetch` writes into `repo` and `capsule
          # <name> status` counts refs in `stateDir`, and both of those are this
          # host's rather than `target.nix`'s — a host whose human is not this one
          # has a different home. Wrapping keeps the CLI itself one store path.
          (wrap "capsule" cli)
          (wrap "capsule-provision" hostPrograms.provision)
          (wrap "capsule-collect" hostPrograms.collect)
          hostPrograms.inject
        ]
        ++ lib.optional (hostPrograms.baseline != null) hostPrograms.baseline;

      # Rotated rather than truncated: it is the record of every egress attempt
      # (NOTES open item 15). copytruncate, so tinyproxy needs no signal. One
      # glob rather than N stanzas — a capsule is a directory under here.
      services.logrotate.settings.capsule-proxy = {
        files = "${proxyState}/*/tinyproxy.log";
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

      systemd.services =
        {
          # One per host, not per capsule: it is the only place the capsules'
          # networks meet, which is why the drops between them live on it.
          capsule-egress-ns = {
            description = "aggregating namespace every capsule's proxy leaves through";
            environment = netns.egressEnv;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${lib.getExe netns.programs.egress} up";
              ExecStop = "${lib.getExe netns.programs.egress} down";
            };
          };

          # Root, because reading a ruleset and entering a namespace need
          # CAP_NET_ADMIN and CAP_SYS_ADMIN. Holds nothing else: no writable
          # path, no network of its own.
          capsule-perimeter-guard = {
            description = "Verify and hold every capsule's perimeter";
            requires = [egressUnit] ++ map netnsUnit instances;
            after = [egressUnit] ++ map netnsUnit instances;
            serviceConfig = {
              Type = "simple";
              ExecStart = lib.getExe guard;
              # A refusal must stay a refusal: restarting would flap between
              # tearing egress down and putting it straight back.
              Restart = "no";
              CapabilityBoundingSet = ["CAP_NET_ADMIN" "CAP_SYS_ADMIN"];
              NoNewPrivileges = true;
              ProtectHome = true;
              ProtectSystem = "strict";
              PrivateTmp = true;
              IPAddressDeny = "any";
              SystemCallArchitectures = "native";
              MemoryMax = "64M";
              TasksMax = 16;
            };
          };
        }
        // netnsServices
        // proxyServices
        // relayServices
        // vmDropins;
    }
  ]);
}
