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
  policies,
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
  # them. **No allowlist**: the perimeter carries none any more (NOTES item 36),
  # and each proxy is handed its policy's file in the environment — through the
  # per-slot symlink below, so re-pointing it is a verb rather than a rebuild.
  perimeter = import ../perimeter {
    inherit pkgs;
    bind = net.host;
    client = net.guest;
    inherit (net) proxyPort;
  };

  # Where a slot's *selected* allowlist is, as one stable path the proxy unit can
  # bind. It is a symlink into `policyDir`, created at the slot's declared
  # default by tmpfiles and re-pointed by `capsule <slot> policy <name>` — which
  # is what keeps the proxy from having to read the assignment record to learn
  # its own perimeter (item 36).
  #
  # **Its own directory, and not beside the record** (NOTES item 39). It was
  # `stateDir/slot/<name>/allowlist` on the reasoning that the two are one slot's
  # desired state and one verb writes both — true, and it made the proxy unable
  # to start. `stateDir` is `0750 owner:users` and the proxy runs as
  # `capsule-proxy`, which is in neither, so it cannot *traverse* to a file that
  # was bound for it: `BindReadOnlyPaths` mounts as root and the open happens as
  # the unit's user. The fix is not to widen `stateDir` — traversal there reaches
  # `collect/`, which holds everything a capsule ever sent back — so the one path
  # the perimeter must read lives outside the directory the human's state is in.
  # Which is item 36's own rule, made true of the filesystem rather than only of
  # the code: the proxy has no way to the record, instead of no reason to read it.
  # One declaration of what `profileDir` is, read by the tmpfiles rule that makes
  # it at boot and by the activation script that fills it at switch — CLAUDE.md's
  # rule, since two carefully-equal spellings are the thing that drifts. 0755 for
  # `allowlistDir`'s reason: a document says which paths a target has and what
  # they may grow to, and every one of them is in a file this repo commits.
  profileDirOwner = {
    mode = "0755";
    user = cfg.owner;
    group = "users";
  };

  allowlistOf = c: "${cfg.allowlistDir}/${c.name}";
  policyFile = name: "${cfg.policyDir}/${policies.policies.${name}.allowlist}";

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
    inherit pkgs lib net target capsules policies workBranch;
    access = guestSsh.viaSocket {
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
    inherit pkgs lib net capsules policies guestSsh;
    # Same store path as the devshell's, because it is the same construction from
    # the same values (host/programs.nix) — a status asks a guest one question
    # and does not care which door it came through.
    inherit (hostPrograms) observe observeFragment programVerbs profileVerbs stateRefPrefix;
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
        export CAPSULE_POLICY_DIR=${cfg.policyDir}
        export CAPSULE_ALLOWLIST_DIR=${cfg.allowlistDir}
        export CAPSULE_PROFILE_DIR=${cfg.profileDir}
        exec ${lib.getExe program} "$@"
      '';
    };

  # The one program that can see inside a capsule's namespace, in its own file
  # because its tools are an argument: the same text is built against stubs by
  # `flake.nix`'s `guardCases` (host/guard.nix).
  guard = import ./guard.nix {
    inherit pkgs lib net capsules netns;
    tools = [pkgs.iproute2 pkgs.procps pkgs.gnugrep pkgs.coreutils pkgs.systemd];
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
        # The slot's symlink, not a policy's file: what it points at is run-time
        # state a verb owns, and a unit that named a policy would need a rebuild
        # to change one (NOTES item 36).
        CAPSULE_ALLOWLIST = allowlistOf c;
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
        # The whole policy directory, so the symlink above resolves inside the
        # unit whichever declared policy it points at — and so the readable set
        # is the declaration rather than whatever one symlink happened to name
        # at start.
        BindReadOnlyPaths = [
          cfg.policyDir
          (allowlistOf c)
          "${netns.resolvConf c.ns}:/etc/resolv.conf"
        ];
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
  # There is a second reason now, and it is about the slot rather than about
  # this repo — a declared VM's `current` is re-pointed at the declaration on
  # every rebuild, silently. Asserted above; NOTES item 49.
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

    policyDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.owner}/dev/microvm-spike/${policies.dir}";
      defaultText = "/home/\${owner}/dev/microvm-spike/\${policies.dir}";
      description = ''
        Directory holding every declared policy's allowlist. Deliberately plain
        files rather than store paths, so changing one needs a proxy restart and
        not a rebuild — the directory is bind-mounted read-only into each proxy's
        namespace, which is why the policies are in one place: it makes the set
        of files a proxy could ever read bounded and legible (policies.nix).
      '';
    };

    profileDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/capsule-profiles";
      description = ''
        Holds one rendered profile document per target, `<name>.json`, read at
        run time by every host-side program through `profileLoad`
        (host/profile.nix). Outside the store on purpose (NOTES item 52): while
        the documents were a store path, adding a target was a rebuild and a
        switch, and no producer but nix could write one — which is the whole of
        what making a target run-time state was for (Plan D §6.1's controller
        that never runs `nixos-rebuild`).

        **This module owns the names it renders and nothing else here.** The
        activation script installs one document per target `target.nix` declares
        and overwrites it every time, because copy-if-absent would make an edit
        to `target.nix` invisible forever after the first boot — item 22's
        write-if-absent payload rule applied to a *derived* payload, which Plan D
        §6.3 already names as the thing to get right. A document under any other
        name is its writer's and nothing here touches it. So a document edited in
        place under this host's own target name is reverted at the next
        activation: `target.nix` is the source and the file is a render.
      '';
    };

    allowlistDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/capsule-allowlist";
      description = ''
        Holds one symlink per slot, named for the slot, pointing at the allowlist
        file in `policyDir` that slot's selected policy declares. tmpfiles creates
        each at the slot's declared default and `capsule <slot> policy <name>`
        re-points it; the proxy binds only its own.

        Its own directory rather than `stateDir`, for `stopKey`'s reason and then
        one more. `stateDir` is the human's and closed to everyone else, and each
        proxy runs as `capsule-proxy` — so a link under it is one the proxy cannot
        traverse to, however carefully the bind names it, and opening `stateDir`
        far enough to fix that also opens `collect/`, which holds everything every
        capsule has ever sent back. This is the one path the perimeter must read,
        so it sits where the perimeter can read it and the record does not
        (NOTES item 39).
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
        # **A slot's state directory is ours, and one line in another repo is
        # what keeps it that way** (NOTES item 49). `vmDropins` below says why
        # `microvm.vms.<name>` goes undeclared — the host's config would
        # evaluate the guest closure — and that reason is about *this* repo's
        # portability. The second reason is about the slot: microvm.nix's
        # `install-microvm-<name>` carries no `ConditionPathExists` unless
        # `updateFlake` is set, so it runs on **every rebuild** and its second
        # line is `ln -sTf <runner> current`. A slot whose `current` is a
        # composition somebody chose (Plan D D7) is therefore reverted to the
        # declaration by an unrelated `nixos-rebuild`, and restarted, with no
        # error and no diff — a slot running something other than what its
        # record says it was assigned, which is item 41's shape.
        #
        # Upstream's own marker does not cover it: `[ -e toplevel ]` is tested
        # only in the `microvm` command's `build()`, so it refuses a human's
        # `microvm -u` and never sees the declarative path. The absence of the
        # declaration is the whole control, which is why it is asserted rather
        # than left in a comment two repos away.
        #
        # Vacuous where the option is undefined, which is `hostModuleUnits`'
        # standalone eval — it does not import microvm.nix's host module — and
        # fires at the switch, where both modules meet. Same shape and same
        # honest placement as the sudoers precedence check below.
        (let
          declared = lib.attrNames (lib.attrByPath ["microvm" "vms"] {} config);
        in {
          assertion = declared == [];
          message = "services.capsule-perimeter: microvm.vms declares ${toString (lib.length declared)} VM(s) (${lib.concatStringsSep ", " declared}), and a capsule's state directory cannot be shared. install-microvm-<name> re-points `current` at the declaration on every rebuild, so a slot's chosen runner is reverted and restarted silently, and a `toplevel` marker does not stop it — only the `microvm` command reads that. Create capsules imperatively (`just up <name>`) and leave microvm.vms empty (NOTES item 49).";
        })
        # **A rule is granted by being in the file and effective by being the
        # last line that matches** (NOTES item 43), and every instrument this
        # repo had answered the first question. `hostModuleUnits` asserts the
        # rule is declared; `sudo -n -l <cmd>` answers whether the command is
        # *permitted*, never which of the matching lines won, so it printed the
        # rule's own path back while a later `%wheel ALL=(ALL:ALL) ALL` — same
        # command, no tag — was the one taking effect. `mkAfter` where the rule
        # is written is the fix; this is the thing that says the fix still holds,
        # because precedence is a property of the whole rendered file and only a
        # host has one. It is therefore vacuous in `hostModuleUnits`' standalone
        # eval and fires at the switch, which is the honest place for it: the
        # shadowing rule belongs to a config this repo does not own.
        (let
          rendered =
            lib.optionals config.security.sudo.enable
            (lib.splitString "\n" (lib.attrByPath ["security" "sudo" "configFile"] "" config));
          indexed = lib.imap0 (i: line: {inherit i line;}) rendered;
          words = line: lib.filter (s: s != "") (lib.splitString " " line);
          # The principals that cover `owner`: the user by name, or a group the
          # host's own declaration puts them in. Read rather than assumed, the
          # same way the bind check reads group membership (item 39).
          ownerGroups = (config.users.users.${cfg.owner} or {}).extraGroups or [];
          covers = line: let
            w = words line;
          in
            w
            != []
            && (
              lib.head w
              == cfg.owner
              || (
                lib.hasPrefix "%" (lib.head w)
                && lib.elem (lib.removePrefix "%" (lib.head w)) ownerGroups
              )
            );
          # `ALL` as the command spec with no tag keeping it passwordless: the one
          # shape that matches this rule's command and outranks it.
          blanket = line: lib.hasSuffix "ALL" line && !(lib.hasInfix "NOPASSWD" line);
          lastGrant =
            lib.foldl'
            (acc: e:
              if lib.hasInfix "restart capsule-proxy-" e.line
              then e.i
              else acc)
            (-1)
            indexed;
          shadows =
            lib.filter (e: e.i > lastGrant && covers e.line && blanket e.line) indexed;
        in {
          # No grant at all is `unrestartable`'s finding, not this one.
          assertion = lastGrant == -1 || shadows == [];
          message = "services.capsule-perimeter: the sudoers rule permitting `capsule <slot> policy <name>` to restart its proxy is shadowed — sudoers is last-match-wins and ${toString (lib.length shadows)} later line(s) match the same command untagged, so the grant is present and inert and the verb will undo every selection it is asked for: ${lib.concatMapStringsSep "; " (e: lib.concatStringsSep " " (words e.line)) shadows}. Order that rule before this one, or drop it if the NixOS sudo module's own `%wheel ALL=(ALL:ALL) ALL` (mkOrder 600) already covers it (NOTES item 43).";
        })
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

      # The one privilege `capsule <slot> policy <name>` needs, and the reason it
      # is here rather than in the host's own config: this module declares the
      # `capsule-proxy-<slot>` units, so it is the only thing that knows their
      # names, and a rule kept anywhere else would go stale the moment the pool
      # changed (NOTES item 41).
      #
      # **Proportionate, and it is worth saying why it is not a widening.** The
      # verb is item 36's delegable one: an assigner may select a policy from the
      # set the *operator* declared for that slot, and may not widen the set. All
      # this adds is bouncing the proxy that renders the selection — an egress
      # outage of about a second, fail-closed while it lasts, on a unit the
      # assigner has just been allowed to reconfigure anyway. Refusing it does not
      # withhold anything; it only makes the verb fail after the record moved,
      # which is the fault this closes.
      #
      # **One literal command per declared slot, no wildcard.** A `capsule-proxy-*`
      # would be a rule about a pattern rather than about the ten units this
      # module made, and sudoers wildcards are a classic way to permit more than
      # was meant.
      #
      # The command is `./proxy-restart.nix`'s and is not spelled here, because
      # sudo matches by the path the *caller* resolves and this host sets no
      # `secure_path`: a rule and an invocation that merely look alike are two
      # commands (NOTES item 44). One construction, three consumers — this, the
      # front end that runs it, and `flake.nix`'s `unrestartable`.
      #
      # **`mkAfter`, and it is the whole difference between granted and
      # effective** (NOTES item 43). sudoers is last-match-wins, so a narrow
      # NOPASSWD rule only holds while nothing broader follows it — and a plain
      # definition here lands at priority 1000 alongside every other module's,
      # where *merge order* decides. On this host `~/flakes` contributes its own
      # `%wheel ALL=(ALL:ALL) ALL` at that priority; it rendered after this rule,
      # matched the same command, carried no tag, and took it. The declaration was
      # present, correct and inert. `mkAfter` says what is actually meant: this
      # grant is narrower than any blanket and outranks one.
      security.sudo.extraRules = lib.mkAfter [
        {
          users = [cfg.owner];
          commands =
            map (c: {
              command = import ./proxy-restart.nix "capsule-proxy-${c.name}";
              options = ["NOPASSWD"];
            })
            instances;
        }
      ];

      # Plain and owner-owned. It was setgid and group-shared when a daemon uid
      # had to write into the same repositories the human read; nothing shares a
      # repository any more, which is the point of item 18.
      systemd.tmpfiles.rules =
        [
          "d ${cfg.stateDir} 0750 ${cfg.owner} users -"
          # Traversable, unlike `stateDir`, because a proxy has to reach its own
          # link and is in neither of that directory's owners. Nothing is in here
          # but the links, which is what makes 0755 cost nothing: a reader learns
          # which policy a slot is on, and every policy is already declared in a
          # file this repo commits.
          "d ${cfg.allowlistDir} 0755 ${cfg.owner} users -"
          # Traversable for the same reason one layer over: a document says which
          # paths a target has and what they may grow to, and every one of them is
          # already in a file this repo commits. Owned by `owner` rather than root
          # because the point of the documents leaving the store (NOTES item 52)
          # is that a producer which is not nix can put one here — and the
          # directory is what grants that, since the documents themselves are
          # installed read-only. It is declared here as well as installed by the
          # activation script below so that `hostModuleUnits`' traversal pairing
          # (item 39) sees it the day a *unit* binds a document; no unit reads one
          # today, and an assertion with no failure mode would be a round that
          # never discriminates.
          "d ${cfg.profileDir} ${profileDirOwner.mode} ${profileDirOwner.user} ${profileDirOwner.group} -"
          # The directory is made; the key is not. `z` only corrects what is
          # already there, so a host that has not been given a stop key is refused
          # at VM start with a message, rather than handed a generated key that
          # no guest closure knows about.
          "d ${builtins.dirOf cfg.stopKey} 0755 root root -"
          "z ${cfg.stopKey} 0400 microvm kvm -"
        ]
        # A slot's record directory, and — in the other directory entirely, see
        # `allowlistOf` — its policy as declared by the host operator.
        # `L` and not `L+`: it creates the symlink when it is absent and leaves one
        # that is already there, so the operator's declaration is what an
        # unassigned slot runs and an assigner's selection survives every boot.
        # That is the whole of "a declared default, not a fallback" — there is no
        # code path that picks a policy, only a link that exists.
        ++ lib.concatMap (c: [
          "d ${cfg.stateDir}/slot/${c.name} 0750 ${cfg.owner} users -"
          "L ${allowlistOf c} - - - - ${policyFile c.policy}"
        ])
        instances;

      # The documents themselves, **installed rather than linked** (NOTES item 52,
      # decision 1). A symlink into the store would keep nix authoritative and
      # give up the whole point, since nobody can write the target of one; a
      # copy-if-absent would make an edit to `target.nix` invisible forever after
      # the first boot. So they are overwritten at every activation, and only
      # under the names this host renders — a document called anything else
      # belongs to whoever wrote it and nothing here touches it.
      #
      # Read-only files in a writable directory: the *set* of documents is a
      # controller's to add to, and each document nix renders is nix's. An
      # activation as well as the tmpfiles rule above because the two run at
      # different times — tmpfiles at boot, this at switch — and a first switch on
      # a host that has never booted this module would otherwise install into a
      # directory that does not exist. Both read `profileDirOwner`, so the
      # directory has one declaration and two consumers rather than two
      # declarations.
      system.activationScripts.capsuleProfiles = ''
        install -d -m ${profileDirOwner.mode} -o ${profileDirOwner.user} -g ${profileDirOwner.group} ${cfg.profileDir}
        install -m 0444 -o ${profileDirOwner.user} -g ${profileDirOwner.group} \
          ${hostPrograms.profile.dir}/*.json ${cfg.profileDir}/
      '';

      # Only the three that touch host state need wrapping; `capsule-inject`,
      # `capsule-baseline` and `capsule-refresh` write nothing host-side, so they
      # go on PATH as they are. All of them but `capsule-adopt` reach the guest
      # through a relay socket, which is the only way in on this path — `--capsule <name>` or
      # `CAPSULE_NAME` picks whose,
      # and there is no fallback: a slot's name says nothing about what is in it,
      # so a program with a default acts on a slot nobody chose. `capsule` itself
      # resolves an unnamed invocation from what is running (host/cli.nix).
      #
      # **Every verb, unconditionally** (NOTES item 51 step 6). These four were
      # `lib.optional (… != null)` while a program's existence was a function of
      # what `target.nix` declared; that gate is gone — a host builds every verb
      # and a verb refuses at run time naming the profile that declares nothing.
      # A conditional here would be the *same* claim decision 3 refused one layer
      # up, and it would now read as "this host may lack `capsule-brief`" while
      # nothing can make that true.
      environment.systemPackages = [
        # Wrapped for the same reason the two stateful programs are, and it is the
        # same wrapper: `capsule <name> fetch` writes into `repo` and `capsule
        # <name> status` counts refs in `stateDir`, and both of those are this
        # host's rather than `target.nix`'s — a host whose human is not this one
        # has a different home. Wrapping keeps the CLI itself one store path.
        (wrap "capsule" cli)
        (wrap "capsule-provision" hostPrograms.provision)
        (wrap "capsule-collect" hostPrograms.collect)
        hostPrograms.inject
        hostPrograms.baseline
        hostPrograms.refresh
        # Wrapped like the other two that keep state: it reads the quarantine
        # `capsule-collect` wrote, so it needs the same `CAPSULE_STATE` and must
        # not derive one from `$PWD`.
        (wrap "capsule-adopt" hostPrograms.adopt)
        # Wrapped for the quarantine's sake like the other three, and it is the
        # only one that reads a quarantine belonging to a capsule other than the
        # one it acts on — which is the whole verb (NOTES item 35).
        (wrap "capsule-brief" hostPrograms.brief)
      ];

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
            # `requires` on the aggregator only: one per host, every capsule's
            # egress leaves through it, and there is no degraded version of the
            # thing they all share.
            #
            # The namespaces are **`after` and nothing else** — not `wants`
            # either, which was the first attempt and was wrong for a reason
            # worth keeping: `wants` is still a pull-in, so the guard would
            # instantiate all ten namespaces on the first start of any one
            # capsule. That removes the failure propagation and keeps the
            # lifecycle coupling, which makes "declared and absent" a state the
            # guard itself abolishes. With ordering only, a namespace is in the
            # transaction because *its own* capsule pulled it there —
            # `microvm@<name>` and its tap unit both `requires` it — and
            # `after` on a unit nobody queued is a no-op. A slot that was
            # requested and failed still has a completed job, so the guard is
            # ordered against it and observes its absence instead of inheriting
            # its failure (NOTES item 30).
            requires = [egressUnit];
            after = [egressUnit] ++ map netnsUnit instances;
            serviceConfig = {
              Type = "simple";
              ExecStart = lib.getExe guard;
              # A refusal must stay a refusal: restarting would flap between
              # tearing egress down and putting it straight back.
              Restart = "no";
              # `CAP_SYS_PTRACE` is limb two's, and it is not optional: asking
              # where a VMM is means reading `/proc/<pid>/ns/net` for a process
              # owned by `microvm`, which `ptrace_may_access` gates on exactly
              # this capability — `CAP_DAC_READ_SEARCH` does not cover that
              # check. Without it `ip netns pids` does not error, it returns a
              # list with the unreadable processes silently missing, so the guard
              # refused a correctly-bound guest with `is not in cap-a` (NOTES
              # item 30). It reads and nothing more, and it is strictly smaller
              # than the `CAP_SYS_ADMIN` already here, which is what `setns`
              # needs.
              CapabilityBoundingSet = ["CAP_NET_ADMIN" "CAP_SYS_ADMIN" "CAP_SYS_PTRACE"];
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
