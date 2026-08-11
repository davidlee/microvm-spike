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

    # Source of the guest's tool set (`packages.dev-tools`) — one list, shared
    # with doctrine's own devshell, so the capsule cannot drift from it.
    # `git+file:` reads committed HEAD, so changes there need a commit before
    # `nix flake update doctrine` will see them.
    doctrine.url = "git+file:///home/david/dev/doctrine";
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

    # Single source of truth for the host<->guest link. A /30 point-to-point
    # tap: no bridge, no LAN exposure, and deliberately no default route in the
    # guest — the only way out is the allowlist proxy on the host end.
    net = {
      tap = "vm-capsule";
      host = "10.99.0.1";
      guest = "10.99.0.2";
      prefix = 30;
      mac = "02:00:00:00:99:02";
      proxyPort = 3128;
      gitPort = 9418;
    };

    mkVm = name: module:
      lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs net;};
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

    # Firecracker cannot create its own tap, so one persistent tap is made up
    # front, owned by the invoking user — after which running the VM needs no
    # privilege at all.
    capsule-net = pkgs.writeShellApplication {
      name = "capsule-net";
      runtimeInputs = [pkgs.iproute2 pkgs.procps];
      text = ''
        tap=${net.tap}

        # Forwarding is global state this script has no business setting, and
        # docker and tailscale both turn it on for their own reasons. The
        # nftables drop in README "Host requirements" is what actually holds
        # the line; this only says when that stanza has started to matter.
        # bash's own redirect, so the check needs nothing on PATH.
        audit_host() {
          read -r forwarding < /proc/sys/net/ipv4/ip_forward
          if [ "$forwarding" != 0 ]; then
            echo "warning: net.ipv4.ip_forward is on. Without the FORWARD drop on" >&2
            echo "         $tap, a guest that gains root can add a default route" >&2
            echo "         and reach the LAN past the proxy." >&2
            echo "         See README 'Host requirements'." >&2
          fi
        }

        case "''${1:-}" in
          up)
            if ip link show "$tap" >/dev/null 2>&1; then
              echo "$tap already up"
              audit_host
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
            audit_host
            echo "if the guest reaches nothing at all, the host is missing the"
            echo "firewall stanza — see README 'Host requirements'."
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
            echo "usage: capsule-net up|down" >&2
            exit 1
            ;;
        esac
      '';
    };

    # Proxy + mirror + ref guard. Jail-agnostic by construction (see
    # perimeter/default.nix); the tap check is the one firecracker-specific
    # bit and is injected rather than assumed.
    perimeter = import ./perimeter {
      inherit pkgs;
      bind = net.host;
      client = net.guest;
      inherit (net) proxyPort gitPort;
      extraRuntimeInputs = [pkgs.iproute2];
      preflight = ''
        # Both services bind ${net.host}, which only exists while the tap does.
        if ! ip -brief addr show ${net.tap} 2>/dev/null | grep -q ${net.host}; then
          echo "capsule-host: ${net.host} is not assigned — run 'capsule-net up' first" >&2
          exit 1
        fi
      '';
    };
    capsule-host = perimeter.host;

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
          if ssh -o BatchMode=yes -o ConnectTimeout=4 \
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

    packages.${system} =
      lib.mapAttrs (_: cfg: cfg.config.microvm.declaredRunner) vms
      // {
        inherit vm vm-stop capsule-net capsule-host;
        default = self.packages.${system}.capsule;
      };

    devShells.${system}.default = pkgs.mkShellNoCC {
      packages = [
        vm
        vm-stop
        capsule-net
        capsule-host
        pkgs.firecracker
        microvm.packages.${system}.microvm # `microvm` CLI (host-module workflows)
      ];
      shellHook = ''
        echo "capsule — firecracker. host side:  capsule-net up  &&  capsule-host"
        echo "                       guest side: vm capsule   (or: vm hello)"
      '';
    };
  };
}
