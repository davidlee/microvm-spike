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

        # The other path, if this host runs it. The port check below cannot see
        # the unit: it denies the host's address (the proxy denies RFC1918), so
        # systemd drops the connect probe and the port looks free — after which
        # the real bind fails and this composition serves nothing while appearing
        # to run. systemd-shaped, so it is injected here rather than living in
        # perimeter/.
        if command -v systemctl >/dev/null 2>&1 \
          && systemctl is-active --quiet capsule-proxy; then
          echo "capsule-host: capsule-proxy is active — the unit path owns the" >&2
          echo "  port. Use one path or the other: systemctl stop capsule-proxy" >&2
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

    # Host->guest ssh, for everything that is not the proxy. The guest's host
    # keys live on its volume, so a *fresh* capsule has fresh keys at the same
    # address — and freshness is the goal, not an accident (NOTES item 17). Since
    # the git channel rides ssh, a changed key no longer merely annoys
    # `just ssh`: it blocks provisioning. `accept-new` does not help, because it
    # accepts *unknown* hosts and this is a *changed* one.
    #
    # So: no host-key check at all, and no record of one. That is sound only
    # because of what this link is — a /30 this host created itself, with exactly
    # one peer, and no third party on it to be in the middle. It stops being
    # sound the moment the transport is a bridge, a LAN or another machine, and
    # it must change in the same commit that does that. `/dev/null` rather than a
    # capsule-scoped file on purpose: a file would accumulate one stale key per
    # capsule and quietly reintroduce the failure. LogLevel=ERROR because
    # otherwise every invocation announces the key it just accepted.
    #
    # The interactive paths — `just ssh`, `just admin` — deliberately do *not*
    # use this. A human present to read the warning is the case where the strict
    # default is still worth having.
    guestSsh = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR";

    # Git in both directions, host-initiated. The one jail-shaped fact it takes
    # is how to reach the guest's checkout: here, ssh over the p2p tap as the
    # unprivileged guest user. Under netns the URL is the same and `sshCommand`
    # grows a `ProxyCommand` against the capsule's unix socket (NOTES item 17),
    # at which point the socket path is the identity and the relaxation above
    # stops being needed.
    # Where the guest's checkout is, as a URL. One binding: the git channel
    # pushes and fetches against it, and probe-netns-boot asks the same question
    # of it through a unix socket.
    guestRepo = "ssh://agent@${net.guest}${target.guestPath}";

    gitChannel = import ./host/git-channel.nix {
      inherit pkgs target guestRepo;
      sshCommand = guestSsh;
    };
    capsule-provision = gitChannel.provision;
    capsule-collect = gitChannel.collect;

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

    # Does a network namespace per capsule hold up (PLAN_C.md, "Netns per
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
    # firecracker come up with its tap inside a namespace (PLAN_C.md, "The one
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

    # What does a fresh capsule cost, and which of REQ-450's five freshness axes
    # does a microVM actually satisfy (doctrine IMP-426 P1a)? Boots the real
    # guest image, twice, against its *own* state directory — freshness means
    # making and destroying volumes, and a probe that did that to `.vm/capsule`
    # could be run once.
    #
    # The socket path is the designed one rather than a mktemp, because
    # `capsule-provision` has to be built with a ProxyCommand against it: the
    # probe exercises the real program on the real seam, which is the whole
    # point of `sshCommand` being injected.
    nsSocket = "/run/capsule/capsule/ssh.sock";
    nsGitChannel = import ./host/git-channel.nix {
      inherit pkgs target guestRepo;
      sshCommand = "${guestSsh} -o ProxyCommand='socat - UNIX-CONNECT:${nsSocket}'";
    };
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
          if ${guestSsh} -o BatchMode=yes -o ConnectTimeout=4 \
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
    nixosModules.capsule-perimeter = import ./host/services.nix {inherit net target;};

    packages.${system} =
      lib.mapAttrs (_: cfg: cfg.config.microvm.declaredRunner) vms
      // {
        inherit vm vm-stop capsule-net capsule-host capsule-provision capsule-collect;
        inherit probe-netns probe-netns-boot probe-freshness;
        default = self.packages.${system}.capsule;
      };

    devShells.${system}.default = pkgs.mkShellNoCC {
      packages = [
        vm
        vm-stop
        capsule-net
        capsule-host
        capsule-provision
        capsule-collect
        probe-netns
        probe-netns-boot
        probe-freshness
        pkgs.firecracker
        pkgs.just
        microvm.packages.${system}.microvm # `microvm` CLI (host-module workflows)
        # stdenv's PATH carries plain `pkgs.bash`, which is built without readline
        # or progcomp: running `bash` in here gave `complete: command not found`
        # and a prompt full of literal \[ \]. `packages` comes first, so this puts
        # the real one back. Not repo-specific — every nix devshell does it.
        pkgs.bashInteractive
      ];
      shellHook = ''
        echo "capsule — firecracker. host side:  capsule-net up  &&  capsule-host"
        echo "                       guest side: vm capsule   (or: vm hello)"
        echo "                       then:       capsule-provision  /  capsule-collect"
      '';
    };
  };
}
