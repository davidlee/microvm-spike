{
  description = "microvm.nix spike — firecracker capsule for agent confinement";

  # microvm.nix's own cache; saves compiling hypervisors + guest kernel.
  # Only honoured if you are in nix.settings.trusted-users, else nix asks.
  nixConfig = {
    extra-substituters = ["https://microvm.cachix.org"];
    extra-trusted-public-keys = ["microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The repo this capsule confines, as a flake: the source of the guest's tool
    # set (`target.nix`'s `toolsPackage`), one list shared with that repo's own
    # devshell so the guest cannot drift from it. Everything else about the
    # target is described in ./target.nix — this must name the same repo as
    # `path` there, and nix cannot check that for you (NOTES item 16). An input
    # url has to be a literal, hence the duplication; `--override-input target
    # path:/…` switches it for one build.
    #
    # `git+file:` reads committed HEAD, so changes there need a commit before
    # `nix flake update target` will see them.
    target.url = "git+file:///home/david/dev/doctrine";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    microvm,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (nixpkgs) lib;

    # Tap name, both addresses, MAC and ports. Its own file because the
    # host-side NixOS module needs the same values.
    net = import ./net.nix;

    # Which repo is confined, and the target-shaped settings that follow from it.
    # Same rule as net.nix: nothing below spells a target detail twice.
    target = import ./target.nix;

    # Which capsules exist, and each one's namespace, socket and uplink. Same
    # rule again. Under netns the guest-facing link is *not* in here — it is
    # identical in every capsule, so it stays in net.nix above.
    capsules = import ./capsules.nix;
    # Where a capsule's way in lives, for the probes' throwaway capsules — which
    # are not instances, and must not spell that path a second time.
    inherit (capsules) socketOf;

    mkVm = name: module:
      lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs net target;};
        modules = [
          microvm.nixosModules.microvm
          ./vm/common.nix
          module
          {networking.hostName = name;}
        ];
      };

    vms = {
      # Smoke test: does firecracker boot at all on this host. No network.
      hello = mkVm "hello" ./vm/hello.nix;
      # The agent jail.
      capsule = mkVm "capsule" ./vm/capsule.nix;
    };

    # Is the host-side half of the perimeter loaded? Injected into the
    # jail-agnostic perimeter as `preflight` + `watch` and shared verbatim with
    # capsule-net, so "intact" has one definition. The systemd path reads the
    # same ruleset as root instead (host/services.nix); this path goes through
    # a NOPASSWD sudo rule, since `capsule-host` holds no privilege.
    #
    # /run/current-system/sw, not a store path: the host config's sudoers rule
    # has to name the same string this does, and this one survives a rebuild on
    # either side.
    perimeterChecks = import ./host/perimeter-check.nix {
      inherit net;
      nft = "sudo -n /run/current-system/sw/bin/nft";
    };

    # Firecracker cannot create its own tap, so one persistent tap is made up
    # front, owned by the invoking user — after which running the VM needs no
    # privilege at all.
    capsule-net = pkgs.writeShellApplication {
      name = "capsule-net";
      runtimeInputs = [pkgs.iproute2 pkgs.procps pkgs.gnugrep];
      text = ''
        tap=${net.tap}

        ${perimeterChecks}

        # Fail closed, before the link exists: `open` means the tap would be a
        # transit path the moment the guest asks for one.
        audit_host() {
          case "$(perimeter_state)" in
            dropped)
              echo "$tap: FORWARD drop verified"
              ;;
            latent)
              echo "warning: net.ipv4.ip_forward is 0, so nothing forwards today, but" >&2
              perimeter_advice
              ;;
            open)
              echo "capsule-net: refusing — net.ipv4.ip_forward is on and" >&2
              perimeter_advice
              return 1
              ;;
          esac
        }

        case "''${1:-}" in
          up)
            audit_host
            if ip link show "$tap" >/dev/null 2>&1; then
              echo "$tap already up"
              # A tap with no address is a half-created link: capsule-host
              # would fail its bind check with nothing pointing at the cause.
              tap_up || {
                echo "warning: $tap exists but ${net.host} is not assigned —" >&2
                echo "         'capsule-net down' then up again." >&2
              }
              exit 0
            fi
            if pgrep -f "microvm@" >/dev/null; then
              echo "warning: a microvm is already running and is attached to the" >&2
              echo "         *old* tap — recreating one will not reattach it." >&2
            fi
            sudo ip tuntap add dev "$tap" mode tap user "$USER"
            # Before the link comes up, so the tap never emits a router
            # solicitation and the host's IPv6 stack is never on the guest's
            # side of the boundary. Per-interface, and the interface is ours,
            # so this one belongs here rather than in the host config — a
            # boot-time sysctl would fire before the tap exists.
            # Absent only if the host kernel has no IPv6 at all, in which case
            # there is nothing to turn off.
            if [ -e "/proc/sys/net/ipv6/conf/$tap/disable_ipv6" ]; then
              sudo sysctl -q -w "net.ipv6.conf.$tap.disable_ipv6=1"
            fi
            sudo ip addr add ${net.host}/${toString net.prefix} dev "$tap"
            sudo ip link set "$tap" up
            echo "$tap up — host ${net.host} <-> guest ${net.guest}"
            # The allow half of the host config fails loud, unlike the drop:
            # omit it and the guest simply reaches nothing.
            echo "if the guest reaches nothing at all, the host is missing the"
            echo "firewall stanza — see README 'Host requirements'."
            ;;
          verify)
            audit_host
            ;;
          down)
            # Deleting a tap out from under a running VM silently kills its
            # NIC: the fd survives, the netdev doesn't, and recreating the tap
            # attaches to nothing. Only a VM restart recovers it.
            if pgrep -f "microvm@" >/dev/null && [ "''${2:-}" != "--force" ]; then
              echo "capsule-net: a microvm is running — stop it first (vm-stop)," >&2
              echo "             or pass --force to sever its network." >&2
              exit 1
            fi
            sudo ip link del "$tap"
            ;;
          *)
            echo "usage: capsule-net up|down|verify" >&2
            exit 1
            ;;
        esac
      '';
    };

    # The allowlist egress proxy. Jail-agnostic by construction (see
    # perimeter/default.nix); the tap check is the one firecracker-specific
    # bit and is injected rather than assumed.
    perimeter = import ./perimeter {
      inherit pkgs;
      bind = net.host;
      client = net.guest;
      inherit (net) proxyPort;
      allowlistFile = target.allowlist;
      extraRuntimeInputs = [pkgs.iproute2];
      preflight = ''
        ${perimeterChecks}

        if ! tap_up; then
          echo "capsule-host: ${net.host} is not assigned — run 'capsule-net up' first" >&2
          exit 1
        fi

        # The other path, if this host runs it. It is no longer a port conflict
        # — a unit-path proxy binds this address *inside a namespace*, so the
        # two can both appear to work — which makes it worse rather than
        # better: two perimeters, two logs, and no way to tell which one served
        # a request. One shape at a time. systemd-shaped, so it is injected
        # here rather than living in perimeter/.
        if command -v systemctl >/dev/null 2>&1 \
          && [ -n "$(systemctl list-units --state=active --no-legend \
               'capsule-proxy-*.service' 2>/dev/null)" ]; then
          echo "capsule-host: a capsule-proxy unit is active — the module path" >&2
          echo "  owns the perimeter. Use one path or the other:" >&2
          echo "  systemctl stop 'capsule-proxy-*'" >&2
          exit 1
        fi

        # The proxy is the guest's only reachable surface, so refuse to offer it
        # at all when the host-side half of the perimeter is gone.
        case "$(perimeter_state)" in
          dropped) echo "capsule-host: FORWARD drop on ${net.tap} verified" ;;
          latent)
            echo "capsule-host: warning — net.ipv4.ip_forward is 0, so nothing" >&2
            echo "  forwards today, but" >&2
            perimeter_advice
            ;;
          open)
            echo "capsule-host: refusing — net.ipv4.ip_forward is on and" >&2
            perimeter_advice
            exit 1
            ;;
        esac
      '';
      # Preflight only proves the perimeter was intact at start. Docker or
      # tailscale can flip forwarding on at any point in a session, and a
      # `capsule-net down --force` can take the bind address out from under
      # both services, so keep checking and take the egress down with it.
      # Cheap checks every cycle; the ruleset read only once forwarding is
      # actually live, which is the only case where the drop matters. The
      # checks themselves come from `preflight`, which has already run in this
      # shell.
      watch = ''
        while sleep 10; do
          if ! tap_up; then
            echo "capsule-host: ${net.host} is gone — the tap was removed" >&2
            exit 1
          fi
          forwarding_off && continue
          if ! forward_dropped; then
            echo "capsule-host: net.ipv4.ip_forward went live mid-session and" >&2
            perimeter_advice
            echo "  Tearing down egress." >&2
            exit 1
          fi
        done
      '';
    };
    capsule-host = perimeter.host;

    # Host->guest ssh, for everything that is not the proxy: no host-key check
    # and no record of one, because a fresh capsule has fresh keys at the same
    # address. The reasoning, and why it is its own file rather than a literal
    # here, is in host/guest-ssh.nix — the units need the identical relaxation
    # and a security default in two copies is one copy nobody edits.
    guestSsh = import ./host/guest-ssh.nix {inherit lib;};

    # Everything the human runs at a capsule: the git channel both ways,
    # `capsule-inject`, `capsule-baseline`. Built here to reach the guest
    # straight over the tap, and built again in `host/services.nix` with the
    # relay socket instead — one construction, two transports, which is the only
    # thing that differs (host/programs.nix).
    hostPrograms = import ./host/programs.nix {
      inherit pkgs lib net target;
      sshArgs = guestSsh.args;
    };
    inherit (hostPrograms) guestHost guestRepo;
    capsule-provision = hostPrograms.provision;
    capsule-collect = hostPrograms.collect;
    capsule-inject = hostPrograms.inject;

    # An attrset because the field is optional — a target that declares no
    # baseline gets no program at all.
    baselinePackages =
      lib.optionalAttrs (hostPrograms.baseline != null)
      {capsule-baseline = hostPrograms.baseline;};

    # The host module has no build of its own — it is a NixOS module, and this
    # repo cannot rebuild someone's host to try it. So *evaluate* it: a text
    # file naming the units it generates drags the whole module through the
    # evaluator, which is where a wrong option name, a bad interpolation or a
    # failed assertion actually lives. Seconds, no NixOS build, and it is in
    # `just build` — the alternative was finding those in a host rebuild.
    hostModuleUnits = let
      host = lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.capsule-perimeter
          {
            system.stateVersion = "25.05";
            # Only the unit graph is being read, so nothing here boots — but the
            # base assertions about a root filesystem and a bootloader fire
            # first and bury whatever the module itself has to say. Stubbed
            # rather than answered with `boot.isContainer`, which mutes them by
            # changing what kind of machine this is: that also turns on
            # `useHostResolvConf`, which resolved then refuses, and would go on
            # quietly moving defaults the units are read against.
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "none";
              fsType = "tmpfs";
            };
            # The module asserts on this: a capsule's only resolver is the stub
            # resolved puts on the aggregator's host end.
            services.resolved.enable = true;
            services.capsule-perimeter = {
              enable = true;
              owner = "nobody";
            };
          }
        ];
      };
      failed = lib.filter (a: !a.assertion) host.config.assertions;
      units =
        lib.filter (n: lib.hasPrefix "capsule-" n || lib.hasPrefix "microvm" n)
        (lib.attrNames host.config.systemd.services);
    in
      if failed != []
      then throw "capsule-perimeter: ${lib.concatMapStringsSep "; " (a: a.message) failed}"
      else pkgs.writeText "capsule-units.txt" (lib.concatStringsSep "\n" units + "\n");

    # Each VM's runner keeps mutable state (volume images, API socket) in $PWD,
    # so give every one its own directory under .vm/.
    vm = pkgs.writeShellApplication {
      name = "vm";
      text = ''
        name="''${1:-capsule}"
        root="''${CAPSULE_ROOT:-''${MICROVM_SPIKE_ROOT:-$PWD}}"
        dir="$root/.vm/$name"
        mkdir -p "$dir"
        cd "$dir"
        exec nix run "$root#$name"
      '';
    };

    # Probes are in the tree rather than in a scratch file for two reasons: each
    # is the evidence behind a decision and has to outlive the conversation that
    # produced it, and building them here means shellcheck runs and their tools
    # are pinned rather than borrowed from whatever `sudo` happens to have on
    # PATH. They need root, so they are the human's to run.
    #
    # `prelude` is how a probe gets net.nix/target.nix values without spelling
    # an address itself. The harness is concatenated rather than sourced: one
    # `writeShellApplication` is one script, so shellcheck sees both halves and
    # the probe needs no path to a sibling at run time.
    probe = {
      name,
      script,
      runtimeInputs,
      prelude ? "",
    }:
      pkgs.writeShellApplication {
        inherit name runtimeInputs;
        # A probe's whole job includes running commands that must fail.
        bashOptions = ["nounset" "pipefail"];
        text =
          prelude
          + builtins.readFile ./probe/harness.sh
          + builtins.readFile script;
      };

    # Does a network namespace per capsule hold up (docs/plan-c-multi-capsule.md, "Netns per
    # capsule")? Models two capsules with identical addressing and no VM, on
    # addressing deliberately unlike the live capsule's.
    probe-netns = probe {
      name = "probe-netns";
      script = ./probe/netns.sh;
      runtimeInputs = [
        pkgs.iproute2
        pkgs.iputils
        pkgs.nftables
        pkgs.procps
        pkgs.gawk
        pkgs.coreutils
        pkgs.bash # /dev/tcp, via `timeout 5 bash -c`
        pkgs.bind.dnsutils
        pkgs.socat # listeners, and the unix-socket way into a namespace
      ];
    };

    # The one thing that probe cannot answer, because it has no VM in it: does
    # firecracker come up with its tap inside a namespace (docs/plan-c-multi-capsule.md, "The one
    # thing still unverified")? Boots the real capsule, so it takes the real
    # values — and refuses to run beside the devshell shape.
    probe-netns-boot = probe {
      name = "probe-netns-boot";
      script = ./probe/netns-boot.sh;
      # Quoted, and it matters: `TAP=vm-capsule` unquoted reads as arithmetic to
      # shellcheck (SC2100) the moment the harness has a `vm` variable in scope,
      # and writeShellApplication takes that as a build failure.
      prelude = ''
        TAP="${net.tap}"
        HOST_ADDR="${net.host}"
        GUEST_ADDR="${net.guest}"
        PREFIX="${toString net.prefix}"
        VM="capsule"
        GUEST_REPO="${guestRepo}"
      '';
      runtimeInputs = [
        pkgs.iproute2
        pkgs.iputils
        pkgs.procps
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.util-linux # runuser: enter the namespace as root, boot the VM as you
        pkgs.glibc.bin # getent, for the human's home directory
        pkgs.bash # /dev/tcp, via `timeout 3 bash -c`
        pkgs.socat
        pkgs.openssh
        pkgs.git
        pkgs.nix # builds the runner, as the human
      ];
    };

    # The claim neither of those two makes: does the *perimeter* survive the move
    # into a namespace (docs/status.md, "Egress under netns is unproven")? Boots
    # the real capsule, joins the real proxy to its namespace, and asks the guest
    # to get out — to a host the allowlist permits and to one it does not. Takes
    # the proxy as a store path rather than rebuilding one, because a probe
    # against a lookalike proves nothing about the program that ships.
    probe-netns-egress = probe {
      name = "probe-netns-egress";
      script = ./probe/netns-egress.sh;
      prelude = ''
        TAP="${net.tap}"
        HOST_ADDR="${net.host}"
        GUEST_ADDR="${net.guest}"
        PREFIX="${toString net.prefix}"
        PROXY_PORT="${toString net.proxyPort}"
        VM="capsule"
        PROXY="${perimeter.proxy}/bin/capsule-proxy"
        ALLOWLIST="${target.allowlist}"
      '';
      runtimeInputs = [
        pkgs.iproute2
        pkgs.iputils
        pkgs.nftables
        pkgs.procps
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused # the allowed host comes out of the allowlist, not the probe
        pkgs.gawk
        pkgs.util-linux # runuser: enter the namespace as root, boot the VM as you
        pkgs.glibc.bin # getent, for the human's home directory
        pkgs.bash # /dev/tcp, host-side and (over ssh) guest-side
        pkgs.socat
        pkgs.openssh
        pkgs.bind.dnsutils
        pkgs.nix # builds the runner, as the human
      ];
    };

    # What does a fresh capsule cost, and which of REQ-450's five freshness axes
    # does a microVM actually satisfy (doctrine IMP-426 P1a)? Boots the real
    # guest image, twice, against its *own* state directory — freshness means
    # making and destroying volumes, and a probe that did that to `.vm/capsule`
    # could be run once.
    #
    # The socket path is the designed one — `capsules.socketOf`, the same
    # convention a declared instance gets — rather than a mktemp, because
    # `capsule-provision` has to be built with a ProxyCommand against it: the
    # probe exercises the real program on the real seam, which is the whole
    # point of `sshArgs` being injected.
    #
    # A function over the socket, because the pair probe needs two of these and
    # the socket is the only thing that differs. That it *has* to be two sets of
    # programs rather than one program and an argument is the finding, not the
    # plumbing: under netns a capsule's identity is its socket path, and here
    # that path is baked into a store path. `capsule-collect` already takes its
    # name as an argument; nothing takes its *transport* as one, and N capsules
    # make that asymmetry cost something.
    nsProgramsFor = sock:
      import ./host/programs.nix {
        inherit pkgs lib net target;
        sshArgs = guestSsh.viaSocket {
          socat = "socat";
          socket = sock;
        };
      };
    nsSocket = capsules.instances.capsule.socket;
    nsGitChannel = nsProgramsFor nsSocket;
    probe-freshness = probe {
      name = "probe-freshness";
      script = ./probe/freshness.sh;
      prelude = ''
        TAP="${net.tap}"
        HOST_ADDR="${net.host}"
        GUEST_ADDR="${net.guest}"
        PREFIX="${toString net.prefix}"
        VM="capsule"
        GUEST_PATH="${target.guestPath}"
        TARGET_PATH="${target.path}"
        DEFAULT_BRANCH="${target.defaultBranch}"
        CACHES="${lib.concatStringsSep " " (lib.attrValues target.caches)}"
        PROVISION="${nsGitChannel.provision}/bin/capsule-provision"
      '';
      runtimeInputs = [
        pkgs.iproute2
        pkgs.iputils
        pkgs.procps
        pkgs.coreutils # du, dirname, date
        pkgs.gnugrep
        pkgs.gawk # the arithmetic behind every figure
        pkgs.util-linux # runuser: enter the namespace as root, boot the VM as you
        pkgs.glibc.bin # getent, for the human's home directory
        pkgs.bash
        pkgs.socat
        pkgs.openssh
        pkgs.git
        pkgs.nix # builds the runner and prices its closure, as the human
      ];
    };

    # Can two capsules run at once, are they independent, and what does the pair
    # cost (doctrine IMP-426 P1b, REQ-454)? Two namespaces, two volumes, two base
    # commits — and deliberately *one* runner from one store path, because that
    # is the shape being priced and it is what makes instance identity a real
    # problem rather than a hypothetical one.
    pairA = "pair-a";
    pairB = "pair-b";
    pairChannelA = nsProgramsFor (socketOf pairA);
    pairChannelB = nsProgramsFor (socketOf pairB);
    probe-two-capsules = probe {
      name = "probe-two-capsules";
      script = ./probe/two-capsules.sh;
      prelude = ''
        TAP="${net.tap}"
        HOST_ADDR="${net.host}"
        GUEST_ADDR="${net.guest}"
        PREFIX="${toString net.prefix}"
        VM="capsule"
        NAME_A="${pairA}"
        NAME_B="${pairB}"
        SOCKDIR_A="${builtins.dirOf (socketOf pairA)}"
        SOCKDIR_B="${builtins.dirOf (socketOf pairB)}"
        PROVISION_A="${pairChannelA.provision}/bin/capsule-provision"
        PROVISION_B="${pairChannelB.provision}/bin/capsule-provision"
        COLLECT_A="${pairChannelA.collect}/bin/capsule-collect"
        COLLECT_B="${pairChannelB.collect}/bin/capsule-collect"
        GUEST_PATH="${target.guestPath}"
        TARGET_PATH="${target.path}"
        DEFAULT_BRANCH="${target.defaultBranch}"
        MEM_MIB="${toString target.sizes.mem}"
      '';
      runtimeInputs = [
        pkgs.iproute2
        pkgs.iputils
        pkgs.procps
        pkgs.coreutils # du, dirname, date, tr
        pkgs.gnugrep
        pkgs.gawk # the arithmetic behind every figure
        pkgs.util-linux # runuser: enter the namespace as root, boot the VM as you
        pkgs.glibc.bin # getent, for the human's home directory
        pkgs.bash
        pkgs.socat
        pkgs.openssh
        pkgs.git
        pkgs.nix # builds the one runner both capsules share, as the human
      ];
    };

    # Clean shutdown without a console. The runner's own microvm-shutdown is
    # SendCtrlAltDel over the API socket, which systemd maps to
    # ctrl-alt-del.target (a *reboot*) and which the guest may ignore outright
    # — observed doing nothing here. Ask the guest to power off over ssh
    # instead, and keep the API route as the fallback.
    vm-stop = pkgs.writeShellApplication {
      name = "vm-stop";
      runtimeInputs = [pkgs.nix pkgs.openssh pkgs.procps pkgs.coreutils];
      text = ''
        name="''${1:-capsule}"
        root="''${CAPSULE_ROOT:-''${MICROVM_SPIKE_ROOT:-$PWD}}"

        stopped=0
        if [ "$name" = capsule ]; then
          # Same relaxed host-key handling as the git channel, and for the same
          # reason: a fresh capsule's new key would otherwise send this down the
          # API-socket fallback, which is a worse shutdown than the ssh poweroff.
          if ${guestSsh.command} -o BatchMode=yes -o ConnectTimeout=4 \
               root@${net.guest} 'systemctl --no-block poweroff' 2>/dev/null; then
            echo "vm-stop: poweroff requested over ssh"
            stopped=1
          fi
        fi

        if [ "$stopped" = 0 ]; then
          echo "vm-stop: ssh unavailable, falling back to the API socket"
          runner=$(nix build --no-link --print-out-paths "$root#$name")
          (cd "$root/.vm/$name" && "$runner/bin/microvm-shutdown") || true
        fi

        # Firecracker does NOT exit when the guest powers off: a guest halt
        # stops the vCPU and leaves the VMM sitting there holding the tap, so
        # the next `vm capsule` dies with EBUSY. Once the guest is down the
        # disks are flushed and terminating the VMM is safe.
        for _ in $(seq 20); do
          pgrep -f "microvm@$name" >/dev/null || { echo "vm-stop: $name is down"; exit 0; }
          sleep 1
        done

        echo "vm-stop: guest halted but the VMM is still up — terminating it"
        pkill -f -- "microvm@$name" || true
        sleep 2
        if pgrep -f "microvm@$name" >/dev/null; then
          pkill -9 -f -- "microvm@$name" || true
          sleep 1
        fi
        pgrep -f "microvm@$name" >/dev/null && {
          echo "vm-stop: $name will not die" >&2
          exit 1
        }
        echo "vm-stop: $name is down"
      '';
    };
  in {
    nixosConfigurations = vms;

    # The host half of the perimeter as units under dedicated uids, for a NixOS
    # host that wants it as its real posture. Opt-in: `capsule-host` in the
    # devshell stays the development path and needs no rebuild. Import it in the
    # host's config and set `services.capsule-perimeter.{enable,owner}`.
    nixosModules.capsule-perimeter = import ./host/services.nix {inherit net target capsules;};

    packages.${system} =
      lib.mapAttrs (_: cfg: cfg.config.microvm.declaredRunner) vms
      // baselinePackages
      // {
        inherit vm vm-stop capsule-net capsule-host hostModuleUnits;
        inherit capsule-provision capsule-collect capsule-inject;
        inherit probe-netns probe-netns-boot probe-netns-egress;
        inherit probe-freshness probe-two-capsules;
        default = self.packages.${system}.capsule;
      };

    devShells.${system}.default = pkgs.mkShellNoCC {
      packages =
        [
          vm
          vm-stop
          capsule-net
          capsule-host
          capsule-provision
          capsule-collect
          capsule-inject
          probe-netns
          probe-netns-boot
          probe-netns-egress
          probe-freshness
          probe-two-capsules
          pkgs.firecracker
          pkgs.just
          # `just ssh` reaches a namespaced capsule through its relay socket, so
          # the devshell needs the same tool the units do.
          pkgs.socat
          microvm.packages.${system}.microvm # `microvm` CLI (host-module workflows)
          # stdenv's PATH carries plain `pkgs.bash`, which is built without readline
          # or progcomp: running `bash` in here gave `complete: command not found`
          # and a prompt full of literal \[ \]. `packages` comes first, so this puts
          # the real one back. Not repo-specific — every nix devshell does it.
          pkgs.bashInteractive
        ]
        ++ lib.attrValues baselinePackages;
      shellHook = ''
        echo "capsule — firecracker. host side:  capsule-net up  &&  capsule-host"
        echo "                       guest side: vm capsule   (or: vm hello)"
        echo "                       then:       capsule-provision / capsule-inject"
        ${lib.optionalString (target.baseline != null)
          ''echo "                                   capsule-baseline (to green)"''}
        echo "                       and back:   capsule-collect"
      '';
    };
  };
}
