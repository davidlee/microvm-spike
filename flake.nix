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
        case "''${1:-}" in
          up)
            if ip link show "$tap" >/dev/null 2>&1; then
              echo "$tap already up"
              exit 0
            fi
            if pgrep -f "microvm@" >/dev/null; then
              echo "warning: a microvm is already running and is attached to the" >&2
              echo "         *old* tap — recreating one will not reattach it." >&2
            fi
            sudo ip tuntap add dev "$tap" mode tap user "$USER"
            sudo ip addr add ${net.host}/${toString net.prefix} dev "$tap"
            sudo ip link set "$tap" up
            echo "$tap up — host ${net.host} <-> guest ${net.guest}"
            echo "if the guest cannot reach the host, the host firewall is dropping it."
            echo "durable fix, and NOT trustedInterfaces (which would expose every"
            echo "0.0.0.0-bound host service to the guest):"
            echo "  networking.firewall.interfaces.\"$tap\".allowedTCPPorts ="
            echo "    [ ${toString net.proxyPort} ${toString net.gitPort} ];"
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
      FilterType extended
      FilterCaseSensitive No
      LogLevel Info
      LogFile "@STATE@/tinyproxy.log"
      PidFile "@STATE@/tinyproxy.pid"
    '';

    # The two host-side services the guest talks to over the p2p link.
    capsule-host = pkgs.writeShellApplication {
      name = "capsule-host";
      runtimeInputs = [pkgs.git pkgs.tinyproxy pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.iproute2 pkgs.procps];
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

        root="''${MICROVM_SPIKE_ROOT:-$PWD}"
        src="''${CAPSULE_REPO:-$HOME/dev/doctrine}"
        state="$root/.vm/host"

        # git daemon outlives the SIGINT that kills tinyproxy, so a Ctrl-C and
        # restart would otherwise hit a port it still holds. Match on this
        # state dir: strays from *this* capsule and nothing else.
        # Patterns must not start with a dash: pkill would read them as options.
        for pattern in "tinyproxy -d -c $state/tinyproxy.conf" "base-path=$state"; do
          if pkill -f -- "$pattern"; then
            echo "capsule-host: reaped a stray ($pattern)"
          fi
        done

        for port in ${toString net.proxyPort} ${toString net.gitPort}; do
          for _ in 1 2 3 4 5; do
            ss -lnt "sport = :$port" | grep -q ${net.host} || break
            sleep 0.2
          done
          if ss -lnt "sport = :$port" | grep -q ${net.host}; then
            echo "capsule-host: ${net.host}:$port is bound by something else:" >&2
            ss -lntp "sport = :$port" >&2
            exit 1
          fi
        done

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
        # Two independent guards on what the daemon will serve, since it is
        # unauthenticated and `receive-pack` is enabled: the per-repo marker
        # (which replaces --export-all) and the explicit whitelist below.
        touch "$mirror/git-daemon-export-ok"

        sed -e "s|@ALLOW@|$allow|" -e "s|@STATE@|$state|" \
          ${tinyproxyConf} > "$state/tinyproxy.conf"

        echo "capsule-host: proxy on ${net.host}:${toString net.proxyPort} (allowlist: $allow)"
        echo "capsule-host: git on ${net.host}:${toString net.gitPort} serving $state"
        tinyproxy -d -c "$state/tinyproxy.conf" &
        proxy=$!
        # --strict-paths + an explicit repo whitelist: the guest may reach
        # exactly this one path, spelled exactly, and no sibling under $state
        # that happens to look like a repo.
        git daemon \
          --base-path="$state" --strict-paths --enable=receive-pack \
          --listen=${net.host} --port=${toString net.gitPort} \
          --reuseaddr --verbose "$mirror" &
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
        root="''${MICROVM_SPIKE_ROOT:-$PWD}"

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
