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

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
      runtimeInputs = [pkgs.iproute2];
      text = ''
        tap=${net.tap}
        case "''${1:-}" in
          up)
            if ip link show "$tap" >/dev/null 2>&1; then
              echo "$tap already up"
              exit 0
            fi
            sudo ip tuntap add dev "$tap" mode tap user "$USER"
            sudo ip addr add ${net.host}/${toString net.prefix} dev "$tap"
            sudo ip link set "$tap" up
            echo "$tap up — host ${net.host} <-> guest ${net.guest}"
            echo "if the guest cannot reach the host, the host firewall is dropping it;"
            echo "durable fix: networking.firewall.trustedInterfaces = [ \"$tap\" ];"
            ;;
          down)
            sudo ip link del "$tap"
            ;;
          *)
            echo "usage: capsule-net up|down" >&2
            exit 1
            ;;
        esac
      '';
    };

    # Guests may only push to refs/heads/capsule/* — the mirror's own history
    # is not theirs to rewrite.
    pushGuard = pkgs.writeShellScript "capsule-push-guard" ''
      case "$1" in
        refs/heads/capsule/*) exit 0 ;;
      esac
      echo "capsule: pushes are restricted to refs/heads/capsule/*" >&2
      exit 1
    '';

    # @ALLOW@ / @STATE@ are filled in at run time so the allowlist stays an
    # ordinary editable file rather than a store path behind a rebuild.
    tinyproxyConf = pkgs.writeText "capsule-tinyproxy.conf" ''
      Port ${toString net.proxyPort}
      Listen ${net.host}
      Timeout 600
      MaxClients 32
      Allow ${net.guest}
      ConnectPort 443
      Filter "@ALLOW@"
      FilterDefaultDeny Yes
      FilterExtended On
      FilterCaseSensitive No
      LogLevel Info
      LogFile "@STATE@/tinyproxy.log"
      PidFile "@STATE@/tinyproxy.pid"
    '';

    # The two host-side services the guest talks to over the p2p link.
    capsule-host = pkgs.writeShellApplication {
      name = "capsule-host";
      runtimeInputs = [pkgs.git pkgs.tinyproxy pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.iproute2];
      text = ''
        # Both services bind ${net.host}, which only exists while the tap does.
        if ! ip -brief addr show ${net.tap} 2>/dev/null | grep -q ${net.host}; then
          echo "capsule-host: ${net.host} is not assigned — run 'capsule-net up' first" >&2
          exit 1
        fi
        # Nothing here wants privilege, and running it as root would leave the
        # mirror root-owned.
        if [ "$(id -u)" = 0 ]; then
          echo "capsule-host: do not run as root" >&2
          exit 1
        fi

        for port in ${toString net.proxyPort} ${toString net.gitPort}; do
          if ss -lnt "sport = :$port" | grep -q ${net.host}; then
            echo "capsule-host: ${net.host}:$port is already bound:" >&2
            ss -lntp "sport = :$port" >&2
            exit 1
          fi
        done

        root="''${MICROVM_SPIKE_ROOT:-$PWD}"
        src="''${CAPSULE_REPO:-$HOME/dev/doctrine}"
        state="$root/.vm/host"
        mirror="$state/$(basename "$src").git"
        allow="$root/net/egress-allow.txt"
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

        sed -e "s|@ALLOW@|$allow|" -e "s|@STATE@|$state|" \
          ${tinyproxyConf} > "$state/tinyproxy.conf"

        echo "capsule-host: proxy on ${net.host}:${toString net.proxyPort} (allowlist: $allow)"
        echo "capsule-host: git on ${net.host}:${toString net.gitPort} serving $state"
        tinyproxy -d -c "$state/tinyproxy.conf" &
        proxy=$!
        git daemon \
          --base-path="$state" --export-all --enable=receive-pack \
          --listen=${net.host} --port=${toString net.gitPort} \
          --reuseaddr --verbose &
        daemon=$!
        # INT/TERM as well as EXIT, and `wait -n` so that either child dying
        # tears the other down instead of leaving it holding a port.
        trap 'kill $proxy $daemon 2>/dev/null' EXIT INT TERM
        wait -n
        echo "capsule-host: a service exited — shutting down" >&2
      '';
    };

    # Each VM's runner keeps mutable state (volume images, API socket) in $PWD,
    # so give every one its own directory under .vm/.
    vm = pkgs.writeShellApplication {
      name = "vm";
      text = ''
        name="''${1:-capsule}"
        root="''${MICROVM_SPIKE_ROOT:-$PWD}"
        dir="$root/.vm/$name"
        mkdir -p "$dir"
        cd "$dir"
        exec nix run "$root#$name"
      '';
    };
  in {
    nixosConfigurations = vms;

    packages.${system} =
      lib.mapAttrs (_: cfg: cfg.config.microvm.declaredRunner) vms
      // {
        inherit vm capsule-net capsule-host;
        default = self.packages.${system}.capsule;
      };

    devShells.${system}.default = pkgs.mkShellNoCC {
      packages = [
        vm
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
