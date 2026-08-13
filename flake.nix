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

    # The branch a capsule's checkout sits on, everywhere and always. Not a value
    # file of its own and not a field of any of the three above: it is not
    # addressing, it is not a slot's, and it is emphatically not the target's —
    # `target.nix`'s `defaultBranch` was deleted rather than given the run-time
    # override it lacked, because a name that identifies the work is not project
    # state and two slices of one project at once is what shows it (plan-d L13,
    # docs/contract-target.md). Two consumers, the guest's seed and
    # `capsule-provision`, and they must agree — so it is spelled here, where the
    # wiring already is, and threaded to both.
    workBranch = "work";
    # Where a capsule's way in lives, for the probes' throwaway capsules — which
    # are not instances, and must not spell that path a second time.
    inherit (capsules) socketOf;

    # `hostName`, not the instance's name: the hostname is in the closure, so a
    # per-instance one is a per-instance image (docs/plan-c-implementation.md).
    mkVm = hostName: module:
      lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs net target workBranch;};
        modules = [
          microvm.nixosModules.microvm
          ./vm/common.nix
          module
          {networking.hostName = hostName;}
        ];
      };

    # The agent jail. One value, however many capsules run it.
    capsuleVm = mkVm "capsule" ./vm/capsule.nix;

    vms =
      {
        # Smoke test: does firecracker boot at all on this host. No network.
        hello = mkVm "hello" ./vm/hello.nix;

        # The guest itself, under the hostname it carries — as against a *slot*,
        # which is one of the names below and is where a capsule's namespace,
        # socket and units live. They are the same value, and this one exists
        # because a runner is `microvm@<hostName>` in the process table: every
        # probe matches on that string and builds `.#capsule` to get it, so the
        # attribute and the process name have to be the one word. `.#capsule` is
        # also what `vm capsule` and `just build-vm` have always meant.
        capsule = capsuleVm;
      }
      # An attribute per declared capsule, because `microvm -c <name> -f .` is
      # what creates one and it resolves `nixosConfigurations.<name>` (CLAUDE.md
      # — the CLI appends that itself and takes no fragment). Every one of them
      # is the *same* value rather than a rebuild of it, so identical modules
      # make an identical derivation and "one image, N capsules" is structural
      # instead of a claim: nothing has to remember to keep two guests in step,
      # because there are not two. The cost is that the prompt no longer says
      # which capsule you are in — priced in plan-c-implementation.md, not
      # solved.
      // lib.mapAttrs (_: _: capsuleVm) capsules.instances;

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
      inherit pkgs net target workBranch;
      # The same socket expression the units inject, for the opposite purpose:
      # there it is the way in, here its existence is what says this copy is the
      # wrong one (host/guest-ssh.nix).
      transport = guestSsh.direct {
        names = builtins.attrNames capsules.instances;
        socket = socketOf ''"$capsule"'';
      };
    };

    # Not one of those four: they run at the *agent*, over whichever transport
    # reaches a capsule, and this one runs at guest root over the link itself —
    # every capsule has the same one, since the namespace is what tells two of
    # them apart. So it takes no capsule and no transport, only an identity, and
    # both paths use the one store path.
    capsule-halt = import ./host/halt.nix {inherit pkgs net guestSsh;};
    inherit (hostPrograms) guestHost guestRepo;
    capsule-provision = hostPrograms.provision;
    capsule-collect = hostPrograms.collect;
    capsule-inject = hostPrograms.inject;

    # An attrset because the field is optional — a target that declares no
    # baseline gets no program at all.
    baselinePackages =
      lib.optionalAttrs (hostPrograms.baseline != null)
      {capsule-baseline = hostPrograms.baseline;};

    # The front end: resolve a name, pick the copy of a program that can reach
    # that capsule, exec (host/cli.nix). Built once and installed by both paths,
    # because unlike the four programs it carries no transport — so there is
    # nothing for a second instantiation to differ in, and one store path is the
    # honest statement of that. `capsule-cli` as an attribute, `capsule` as a
    # program: `.#capsule` is the guest runner and has been all along.
    # What a capsule answers about itself, pushed over the door at each status
    # rather than baked into the guest (host/observe.nix). Built here so the front
    # end takes a store path and never learns a guest path: `capsule status` asks
    # a question it does not have to understand the inside of.
    observe = import ./host/observe.nix {
      inherit pkgs lib;
      workdir = target.guestPath;
      recordDir = hostPrograms.baselineRecord;
      inherit (target) volumePath;
    };

    capsule-cli = import ./host/cli.nix {
      inherit pkgs lib net target capsules guestSsh observe;
      programVerbs =
        ["provision" "collect" "inject"]
        ++ lib.optional (hostPrograms.baseline != null) "baseline";
    };

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

      # A newline in a unit directive is unbalanced quoting to systemd, which
      # ignores that directive *and* the rest of the drop-in — so a unit loses
      # its namespace and its `ExecStop` and says nothing about it. Nix will
      # happily produce one, systemd only complains at load, and both paths
      # around it look healthy: that is a whole rebuild and an evening
      # (docs/plan-c-implementation.md, "Traps already paid for"). Asked here
      # because this is the one thing that reads the module without a host.
      literals = v:
        if builtins.isList v
        then lib.concatMap literals v
        else if builtins.isString v
        then [v]
        else [];
      newlined = lib.filter (n:
        lib.any (lib.hasInfix "\n")
        (lib.concatMap literals
          (lib.attrValues (host.config.systemd.services.${n}.serviceConfig or {}))))
      units;
    in
      if failed != []
      then throw "capsule-perimeter: ${lib.concatMapStringsSep "; " (a: a.message) failed}"
      else if newlined != []
      then throw "capsule-perimeter: a newline in a serviceConfig value of ${lib.concatStringsSep ", " newlined} — systemd reads that as unbalanced quoting and drops the rest of the unit. Put the script in the store and name it."
      else pkgs.writeText "capsule-units.txt" (lib.concatStringsSep "\n" units + "\n");

    # Each VM's runner keeps mutable state (volume images, API socket) in $PWD,
    # so give every one its own directory under .vm/.
    vm = pkgs.writeShellApplication {
      name = "vm";
      text = ''
        # No default, since `capsules.default` went with slots being abstract:
        # every argument is a VM name and an omitted one used to mean the capsule
        # that was called `capsule`.
        name="''${1:-}"
        if [ -z "$name" ]; then
          echo "usage: vm <name>   (capsule | hello | a slot)" >&2
          exit 1
        fi
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
    # `capsule-provision` has to reach the guest through it: the probe exercises
    # the real program on the real seam, which is the whole point of `transport`
    # being injected.
    #
    # One set for every capsule a probe invents, `--capsule <name>` choosing
    # which. It used to be a function over the socket, because a socket path
    # baked into a store path meant a program per capsule — the asymmetry
    # `probe-two-capsules` was written to expose, and the reason the transport is
    # a run-time argument now. `socat` is bare here: a probe has it in
    # `runtimeInputs`, where a unit has no PATH to trust.
    nsPrograms = import ./host/programs.nix {
      inherit pkgs net target workBranch;
      transport = guestSsh.viaSocket {
        socat = "socat";
        socket = socketOf ''"$capsule"'';
      };
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
        CACHES="${lib.concatStringsSep " " (lib.attrValues target.caches)}"
        PROVISION="${nsPrograms.provision}/bin/capsule-provision"
        # Its own name, not a slot's: this probe makes and destroys volumes, so
        # it must not land on a declared slot's socket — and `socketOf` is what
        # keeps the convention single even for a capsule nobody declared.
        SOCKDIR="${builtins.dirOf (socketOf "capsule")}"
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
    # problem rather than a hypothetical one. One set of host programs too, now
    # that the transport is an argument: this probe is what found that it was not.
    pairA = "pair-a";
    pairB = "pair-b";
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
        PROVISION="${nsPrograms.provision}/bin/capsule-provision"
        COLLECT="${nsPrograms.collect}/bin/capsule-collect"
        GUEST_PATH="${target.guestPath}"
        TARGET_PATH="${target.path}"
        WORK_BRANCH="${workBranch}"
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

    # Stopping a VM is two jobs, and only the second one is this program's: get
    # the guest down (`capsule-halt`, shared with the unit path), then account
    # for the hypervisor. The API-socket fallback that used to sit here is gone
    # — it was `SendCtrlAltDel`, which this guest has no keyboard to receive
    # (host/halt.nix), so it only ever bought a wait and a `nix build`.
    vm-stop = pkgs.writeShellApplication {
      name = "vm-stop";
      runtimeInputs = [capsule-halt pkgs.procps pkgs.coreutils];
      text = ''
        name="''${1:-}"
        if [ -z "$name" ]; then
          echo "usage: vm-stop <name>   (capsule | hello | a slot)" >&2
          exit 1
        fi

        # One link, one guest: the devshell path runs a single capsule at
        # ${net.guest}, and every name below is that same guest — the image under
        # its own name, and each declared slot, which are one value in this flake.
        # Anything else (`hello`) is a VM this cannot talk to and is reaped rather
        # than asked. The list follows the slots because the alternative is a
        # literal that silently stops asking the moment a slot is renamed, and a
        # stop that does not ask is a power cut on a mounted volume.
        guests=(capsule ${lib.concatStringsSep " " (builtins.attrNames capsules.instances)})
        halted=0
        for g in "''${guests[@]}"; do
          [ "$name" = "$g" ] || continue
          if capsule-halt; then halted=1; fi
          break
        done

        # Only VMMs this shell can prove are its own. Every capsule is
        # `microvm@capsule` in the process table, so a bare `pkill -f` is a power
        # cut for any namespaced sibling the module path is running — and it
        # reads as a clean teardown while doing it. A VMM in a namespace is
        # root's and lives in another netns, so both tests exclude it: the
        # readlink fails, or it does not match this shell's.
        own_vms() {
          local self pid
          self=$(readlink /proc/self/ns/net)
          for pid in $(pgrep -f "microvm@$name" || true); do
            [ "$(readlink "/proc/$pid/ns/net" 2>/dev/null)" = "$self" ] \
              && echo "$pid"
          done
        }

        # A guest that took the reboot exits its own VMM — that is what
        # `reboot=k` buys, measured (docs/probes.md) — so the one correct move
        # here is to wait for it. Killing while it unmounts is precisely the
        # power cut this program exists to avoid, and a volume carrying a cold
        # build is where that costs something. Bounded, because a guest that
        # took the request and then hung still has to be reaped.
        if [ "$halted" = 1 ]; then
          for _ in $(seq 300); do
            mapfile -t pids < <(own_vms)
            [ "''${#pids[@]}" -gt 0 ] || { echo "vm-stop: $name is down"; exit 0; }
            sleep 0.2
          done
          echo "vm-stop: the guest took a reboot but its VMM outlived it" >&2
        fi

        mapfile -t pids < <(own_vms)
        [ "''${#pids[@]}" -gt 0 ] || { echo "vm-stop: $name is down"; exit 0; }

        echo "vm-stop: terminating the VMM"
        kill "''${pids[@]}" 2>/dev/null || true
        for _ in $(seq 50); do
          mapfile -t pids < <(own_vms)
          [ "''${#pids[@]}" -gt 0 ] || { echo "vm-stop: $name is down"; exit 0; }
          sleep 0.1
        done
        kill -9 "''${pids[@]}" 2>/dev/null || true
        sleep 0.5
        mapfile -t pids < <(own_vms)
        [ "''${#pids[@]}" -gt 0 ] && {
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
    nixosModules.capsule-perimeter = import ./host/services.nix {inherit net target capsules workBranch;};

    packages.${system} =
      lib.mapAttrs (_: cfg: cfg.config.microvm.declaredRunner) vms
      // baselinePackages
      // {
        inherit vm vm-stop capsule-halt capsule-net capsule-host hostModuleUnits;
        inherit capsule-cli capsule-provision capsule-collect capsule-inject;
        inherit probe-netns probe-netns-boot probe-netns-egress;
        inherit probe-freshness probe-two-capsules;
        default = self.packages.${system}.capsule;
      };

    devShells.${system}.default = pkgs.mkShellNoCC {
      packages =
        [
          vm
          vm-stop
          capsule-halt
          capsule-net
          capsule-host
          capsule-cli
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
