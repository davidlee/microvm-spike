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

    # The one tool source this host registers beyond nixpkgs and the target:
    # where the agent CLIs come from (`fragments.nix`'s `agents`). A fragment is
    # code in the guest closure, so its source is a flake input of *this* repo,
    # pinned in a lock this host owns and updated only by a deliberate
    # `nix flake update` (NOTES item 26, docs/contract-flavour.md). The literal
    # is per *source* rather than per project, which is why this list stays
    # short as the fleet grows.
    #
    # Deliberately not `follows = "nixpkgs"`: these are prebuilt in numtide's
    # cache against their own pin, and re-pointing nixpkgs rebuilds them here
    # for no gain.
    llm-agents.url = "github:numtide/llm-agents.nix";
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
    policies = import ./policies.nix;

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

    # The host operator's half of every guest's tool set: which fragments of
    # `fragments.nix`'s vocabulary this fleet composes into its image. A value
    # threaded like `workBranch`, and one list for the fleet — so every slot
    # arrives at the same composition and stays one image (NOTES item 21), and
    # a per-slot list is a field this value moves into rather than a mechanism
    # anything here has to grow (Plan D D7, docs/contract-flavour.md).
    #
    # The floor is *not* here: that is the target's, and `vm/capsule.nix` still
    # reads it out of `target.nix`. Two owners, two files, one composition.
    extras = ["agents" "dev-facilities"];

    # Where a capsule's way in lives, for the probes' throwaway capsules — which
    # are not instances, and must not spell that path a second time.
    inherit (capsules) socketOf;

    # `hostName`, not the instance's name: the hostname is in the closure, so a
    # per-instance one is a per-instance image (docs/plan-c-implementation.md).
    mkVm = hostName: module:
      lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs net target workBranch extras;};
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
    # `capsule-host`, with a policy resolved in front of it. The perimeter no
    # longer carries an allowlist (NOTES item 36), so the devshell path names one
    # the way it names a capsule: as an argument, refusing without. A wrapper
    # rather than an argument to `perimeter/` for the reason everything else here
    # is injected — a policy vocabulary is this host's, and `perimeter/` is the
    # one place that must stay portable enough for a seatbelt to reuse.
    #
    # It is a wrapper on `PATH`, so reading it answers about the wrapper and not
    # about the proxy (CLAUDE.md).
    capsule-host =
      pkgs.writeShellApplication {
        name = "capsule-host";
        text = ''
          root="''${CAPSULE_ROOT:-''${MICROVM_SPIKE_ROOT:-$PWD}}"
          case "''${1:-}" in
            --policy)
              [ -n "''${2:-}" ] || { echo "capsule-host: --policy takes a name" >&2; exit 1; }
              policy="$2"
              shift 2
              ;;
            *)
              echo "capsule-host: usage: capsule-host --policy <name> [args…]" >&2
              echo "  declared policies: ${lib.concatStringsSep " " policies.everything}" >&2
              echo "  A perimeter serves under a named policy or it does not serve" >&2
              echo "  (policies.nix, NOTES item 36)." >&2
              exit 1
              ;;
          esac
          case "$policy" in
          ${lib.concatMapStringsSep "
" (n: ''
              ${n}) allow="$root/${policies.dir}/${policies.policies.${n}.allowlist}" ;;'')
            policies.everything}
            *)
              echo "capsule-host: no policy named '$policy'." >&2
              echo "  declared: ${lib.concatStringsSep " " policies.everything}" >&2
              exit 1
              ;;
          esac
          [ -r "$allow" ] || {
            echo "capsule-host: policy '$policy' names $allow, which is not readable." >&2
            exit 1
          }
          echo "capsule-host: policy $policy"
          export CAPSULE_ALLOWLIST="$allow"
          exec ${lib.getExe perimeter.host} "$@"
        '';
      };

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
      inherit pkgs lib net target policies workBranch;
      # The same socket expression the units inject, for the opposite purpose:
      # there it is the way in, here its existence is what says this copy is the
      # wrong one (host/guest-ssh.nix).
      access = guestSsh.direct {
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

    # Attrsets because the fields are optional — a target that declares no
    # baseline, or derives nothing from its checkout, gets no program at all
    # rather than one that cannot work.
    baselinePackages =
      lib.optionalAttrs (hostPrograms.baseline != null)
      {capsule-baseline = hostPrograms.baseline;};

    refreshPackages =
      lib.optionalAttrs (hostPrograms.refresh != null)
      {capsule-refresh = hostPrograms.refresh;};

    adoptPackages =
      lib.optionalAttrs (hostPrograms.adopt != null)
      {capsule-adopt = hostPrograms.adopt;};

    briefPackages =
      lib.optionalAttrs (hostPrograms.brief != null)
      {capsule-brief = hostPrograms.brief;};

    # The front end: resolve a name, pick the copy of a program that can reach
    # that capsule, exec (host/cli.nix). Built once and installed by both paths,
    # because unlike the four programs it carries no transport — so there is
    # nothing for a second instantiation to differ in, and one store path is the
    # honest statement of that. `capsule-cli` as an attribute, `capsule` as a
    # program: `.#capsule` is the guest runner and has been all along.
    #
    # `observe` is what a capsule answers about itself, pushed over the door at
    # each status rather than baked into the guest — a store path, so the front
    # end never learns a guest path (host/observe.nix). It comes from
    # `hostPrograms` because that is where the paths it reads are named, and
    # because a thing built at each of this file's two call sites is a thing one
    # of them can be missing.
    capsule-cli = import ./host/cli.nix {
      inherit pkgs lib net target capsules policies guestSsh;
      inherit (hostPrograms) observe programVerbs stateNeedsUnit;
    };

    # The guard's verdicts, asserted at build time against a stubbed kernel.
    #
    # This is the third kind of check here and it earns its own kind: a `probe/`
    # needs root and asserts against the real host, `hostModuleUnits` evaluates
    # what the module *says*, and this runs a real host-side program's logic with
    # its tools replaced. The guard is the thing it is for — its branches decide
    # whether a broken slot degrades or denies the fleet, and reaching them on a
    # live host means unnaming a namespace under a running guest.
    #
    # It is not a second implementation of the guard: `host/guard.nix` takes
    # `tools` as an argument, and this builds that same text with stubs where
    # iproute2 and systemd would be. `writeShellApplication` prepends
    # `runtimeInputs` to `PATH`, which is exactly why the seam has to be an
    # argument — a stub directory prepended by a test would lose to the real
    # `ip` every time.
    guardStubs = let
      # The kernel and systemd, as far as the guard can tell. Each reads the
      # case's environment: `NS_FILE` names the namespaces that exist (a file,
      # not a variable, because `sleep` rewrites it to make a slot arrive or
      # leave mid-hold), `VMS` is `slot:pid` per *active* unit, and `PIDS_IN` is
      # `ns:pid` — where those pids actually are, which is the only way the two
      # can disagree.
      ip = pkgs.writeShellScriptBin "ip" ''
        case "$1 $2" in
          "netns list") for n in $(cat "$NS_FILE"); do echo "$n (id: 0)"; done ;;
          "netns pids")
            grep -qw "$3" "$NS_FILE" || exit 1
            for p in ''${PIDS_IN:-}; do
              case "$p" in "$3":*) echo "''${p#*:}" ;; esac
            done ;;
          "netns exec")
            shift 3
            case "$1" in
              *sysctl) echo "''${FORWARD:-0}" ;;
              *nft) printf '%s\n' "$NFT_RULES" ;;
            esac ;;
        esac
      '';
      systemctl = pkgs.writeShellScriptBin "systemctl" ''
        unit=''${*: -1}
        slot=''${unit#microvm@}
        slot=''${slot%.service}
        pid=""
        for v in ''${VMS:-}; do
          case "$v" in "$slot":*) pid=''${v#*:} ;; esac
        done
        case "$1" in
          is-active) [ -n "$pid" ] ;;
          show) echo "$pid" ;;
        esac
      '';
      # Holds the loop `LOOPS` times instead of forever, and applies `NS_THEN` on
      # the first cycle — which is how a slot arriving late is tested at all.
      sleep = pkgs.writeShellScriptBin "sleep" ''
        n=$(cat count 2>/dev/null || echo 0)
        [ "$n" -lt "''${LOOPS:-0}" ] || exit 1
        echo $((n + 1)) >count
        [ -z "''${NS_THEN:-}" ] || echo "$NS_THEN" >"$NS_FILE"
      '';
    in [ip systemctl sleep pkgs.gnugrep pkgs.coreutils];

    guardCases = let
      # Two slots, and not this host's two. The cases below assert a property
      # that holds at any fleet size — one absent slot is a smaller fleet, one
      # present-and-wrong slot is a breach — so following `capsules.nix` would
      # make widening the pool an edit to eleven expected strings and would test
      # today's declaration rather than the guard. Everything else about the
      # declaration is the real one: only `instances` is substituted, so the
      # aggregator, the uplink net and the drop pattern the cases grep for are
      # the shipped values.
      fixture =
        capsules
        // {
          instances = capsules.instancesOf {
            a = {index = 0;};
            b = {index = 1;};
          };
        };
      stubbed = import ./host/guard.nix {
        inherit pkgs lib net;
        capsules = fixture;
        netns = import ./host/netns.nix {
          inherit pkgs lib net;
          capsules = fixture;
        };
        tools = guardStubs;
      };

      # Both limbs, and the count. `want` is the exit status: 0 is a verdict of
      # intact — the stubbed `sleep` ends the hold loop, so a passing guard
      # returns rather than running forever — and 1 is a refusal. `expect` is a
      # fixed string that has to appear, because a refusal for the wrong reason
      # is not the same check.
      cases = [
        # --- limb one: declared ∩ present ---
        {
          name = "both present, nothing running";
          ns = "cap-egress cap-a cap-b";
          want = 0;
          expect = "2 of 2 declared";
        }
        {
          # The whole point of item 30: one slot short is a smaller fleet, not a
          # dead one.
          name = "a slot that never came up degrades";
          ns = "cap-egress cap-a";
          want = 0;
          expect = "1 of 2 declared";
        }
        {
          name = "no slot present at all";
          ns = "cap-egress";
          want = 0;
          expect = "0 of 2 declared";
        }
        {
          # One per host, and every capsule leaves through it.
          name = "the aggregator is not degradable";
          ns = "cap-a cap-b";
          want = 1;
          expect = "namespace cap-egress is gone";
        }
        {
          # Present and wrong is a breach, and absence is not breakage.
          name = "a present namespace that forwards";
          ns = "cap-egress cap-a cap-b";
          env = {FORWARD = "1";};
          want = 1;
          expect = "the guest's confinement is gone";
        }
        # --- limb two: a running VMM is inside its own namespace ---
        {
          name = "a running slot beside one that never started";
          ns = "cap-egress cap-a";
          env = {
            VMS = "a:4242";
            PIDS_IN = "cap-a:4242";
          };
          want = 0;
          expect = "1 of 2 declared";
        }
        {
          # The hole limb one would open on its own: `ip netns del` unnames a
          # namespace and the guest keeps running inside it.
          name = "a live guest in a namespace that has been unnamed";
          ns = "cap-egress cap-b";
          env = {
            VMS = "a:4242";
            PIDS_IN = "cap-a:4242";
          };
          want = 1;
          expect = "is not a named namespace";
        }
        {
          # A union-membership test calls this healthy: one slot's guest behind
          # another slot's perimeter.
          name = "a VMM bound to the wrong namespace";
          ns = "cap-egress cap-a cap-b";
          env = {
            VMS = "a:4242";
            PIDS_IN = "cap-b:4242";
          };
          want = 1;
          expect = "is not in cap-a";
        }
        {
          name = "an active unit with no MainPID";
          ns = "cap-egress cap-a";
          env = {VMS = "a:0";};
          want = 1;
          expect = "no MainPID";
        }
        # --- the count is part of the safety property, so it has to move ---
        {
          name = "a slot arriving during the hold is reported";
          ns = "cap-egress cap-a";
          env = {
            LOOPS = "2";
            NS_THEN = "cap-egress cap-a cap-b";
          };
          want = 0;
          expect = "2 of 2 declared";
        }
        {
          name = "a slot leaving during the hold is reported";
          ns = "cap-egress cap-a cap-b";
          env = {
            LOOPS = "2";
            NS_THEN = "cap-egress cap-a";
          };
          want = 0;
          expect = "1 of 2 declared";
        }
      ];

      runCase = i: c: ''
        mkdir -p case-${toString i} && cd case-${toString i}
        printf '%s\n' ${lib.escapeShellArg c.ns} >ns
        rc=0
        env NS_FILE="$PWD/ns" \
          ${lib.concatStringsSep " " (lib.mapAttrsToList
            (k: v: "${k}=${lib.escapeShellArg v}") (c.env or {}))} \
          ${lib.getExe stubbed} >out 2>&1 || rc=$?
        if [ "$rc" != ${toString c.want} ]; then
          echo "FAIL ${c.name}: exit $rc, wanted ${toString c.want}" >&2
          sed 's/^/    /' out >&2
          exit 1
        fi
        if ! grep -qF -- ${lib.escapeShellArg c.expect} out; then
          echo "FAIL ${c.name}: nothing matching ${c.expect}" >&2
          sed 's/^/    /' out >&2
          exit 1
        fi
        echo "ok (${toString c.want}) ${c.name}" >>"$log"
        cd ..
      '';
    in
      pkgs.runCommand "capsule-guard-cases" {} ''
        log=$PWD/log
        : >"$log"
        # nft's rendering, as the guard's `ns_rule` greps it. Every case has an
        # intact ruleset: a missing rule is `ns_rule`'s own test and not this
        # program's.
        export NFT_RULES='iifname "${capsules.egress.linkPattern}" oifname "${capsules.egress.linkPattern}" drop
        ip saddr ${capsules.uplinkNet}
        iifname "${net.tap}" ip daddr != ${net.host} drop'
        ${lib.concatStrings (lib.imap0 runCase cases)}
        cp "$log" $out
        cat $out
      '';

    # `capsule-brief`'s guest half, run against hand-built git objects.
    #
    # The third kind of check (CLAUDE.md), a second instance of it: `guardCases`
    # runs the guard's own text with its tools stubbed, and this runs the brief
    # runner's own text in a git repository the sandbox builds. Same argument for
    # the same reason — the branches that decide whether an exhibit may land are
    # a `code-oid` that does not match and a worktree somebody else dirtied, and
    # reaching those on a live host means two capsules and a deliberate mess in
    # one of them. The seam is `host/brief.nix`'s `runner`, a function of the
    # checkout it runs in, exactly as the guard's is a function of its tools.
    #
    # `null` for a target with no `statePaths`, in which case there is no program
    # and nothing to assert about one.
    briefCases = let
      runner = hostPrograms.briefRunner "dest";
    in
      pkgs.runCommand "capsule-brief-cases" {nativeBuildInputs = [pkgs.git];} ''
        export HOME=$PWD GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
        export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
        export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
        fail=0
        ck() {
          if [ "$2" = "$3" ]; then echo "ok   $1" >>"$log"
          else echo "FAIL $1: exit $3, wanted $2" >&2; fail=1; fi
        }
        ckt() {
          if "''${@:2}"; then echo "ok   $1" >>"$log"
          else echo "FAIL $1" >&2; fail=1; fi
        }
        log=$PWD/log
        : >"$log"

        # ------------------------------------------------- the source capsule
        #
        # A checkout shaped like the one this was written from: authored content
        # under a declared path, an agent's uncommitted edit to it, runtime state
        # that is only ever ignored, and the contained symlink item 34 found.
        mkdir src && cd src
        git init -q --initial-branch=work .
        mkdir -p .doctrine/state/slice/254/phases .doctrine/slice/254
        echo authored >.doctrine/slice/254/spec.md
        echo code >src.txt
        git add -A && git commit -qm base
        code=$(git rev-parse HEAD)
        echo "edited by the agent" >.doctrine/slice/254/spec.md
        echo "phase 3 notes" >.doctrine/state/slice/254/phases/03.md
        ln -s ../../state/slice/254/phases .doctrine/slice/254/phases

        # The outbound snapshot, built as `host/state-snapshot.nix` builds one —
        # temporary index, the `.capsule/dirty.diff` blob, the same message
        # fields. Hand-built rather than run, because that program's own
        # invocation is an ssh into a guest.
        git diff HEAD >../dirty.patch
        export GIT_INDEX_FILE=$PWD/../tmpidx
        git read-tree --empty
        git add -f -- .doctrine/state/slice .doctrine/slice
        blob=$(git hash-object -w --stdin <../dirty.patch)
        git update-index --add --cacheinfo "100644,$blob,.capsule/dirty.diff"
        tree=$(git write-tree)
        state=$(printf '%s\n' "capsule state: implementation" "" \
          "stage: implementation" "code-oid: $code" "dirty: 2" |
          git commit-tree "$tree")
        git update-ref refs/capsule/state/implementation "$state"
        unset GIT_INDEX_FILE
        cd ..

        # -------------------------------------------------- the guest briefed
        git clone -q src dest -b work
        git -C dest fetch -q "$PWD/src" '+refs/capsule/state/*:refs/capsule/state/*'

        rc=0; bash ${runner} "$state" 0000000000000000000000000000000000000000 >out 2>&1 || rc=$?
        ck "refuses a state that was the state of other code" 3 "$rc"
        ckt "  and names the commit it was of" grep -qF "that state was the state of" out
        ckt "  and wrote nothing" test ! -e dest/.doctrine/state/slice/254/phases/03.md

        echo mine >>dest/src.txt
        rc=0; bash ${runner} "$state" "$code" >out 2>&1 || rc=$?
        ck "refuses over an agent's own uncommitted work" 3 "$rc"
        ckt "  and wrote nothing" test ! -e dest/.doctrine/state/slice/254/phases/03.md
        git -C dest checkout -q -- src.txt

        rc=0; bash ${runner} "$state" "$code" >out 2>&1 || rc=$?
        ck "lays the tree out over matching code" 0 "$rc"
        ckt "  the ignored runtime file landed" test -f dest/.doctrine/state/slice/254/phases/03.md
        # The whole reason the code-oid check earns the overwrite: a state tree
        # carries worktree content, so this is the other agent's edit and not the
        # commit's version of the file.
        ckt "  the tracked file carries the other agent's edit" \
          test "$(cat dest/.doctrine/slice/254/spec.md)" = "edited by the agent"
        ckt "  the contained symlink resolves after extraction" \
          test "$(cat dest/.doctrine/slice/254/phases/03.md)" = "phase 3 notes"
        # `.capsule/` is this system's namespace, not the target's: on disk it
        # would be untracked content the *next* collect carries again.
        ckt "  .capsule/ is not on disk" test ! -e dest/.capsule
        ckt "  and .capsule/ is still in the exhibit" \
          test -n "$(git -C dest ls-tree -r --name-only "$state" -- .capsule)"
        ckt "  the agent's real index was not touched" \
          test -z "$(git -C dest diff --cached --name-only)"
        ckt "  the worktree now differs from its HEAD" \
          test -n "$(git -C dest status --porcelain)"

        rc=0; bash ${runner} "$state" "$code" >out 2>&1 || rc=$?
        ck "refuses a second brief onto an already-briefed capsule" 3 "$rc"

        [ "$fail" = 0 ] || exit 1
        cp "$log" $out
        cat $out
      '';

    # `capsule-collect`'s guest half, run against a checkout the sandbox builds,
    # plus the token bound that stands between an assignment and a path.
    #
    # The third kind of check (CLAUDE.md), a third instance of it, and the branch
    # it exists for is item 32's scope invariant: *a collect brings back the
    # out-of-band state of the work the capsule was assigned, and none that is
    # not*. Reaching that on a live host means a capsule that has driven a real
    # unit of work in a checkout holding several — which is a thirteen-hour slice
    # and one host, so it is asserted here on a checkout that holds two units and
    # costs a second. The seam is `host/state-snapshot.nix`'s `snapshotFor`, a
    # function of the checkout it runs in, exactly as `brief.nix`'s runner is.
    #
    # The token cases are here rather than in a suite of their own because they
    # are the *other half of the same control*: the bound is what makes a unit
    # token safe to substitute into the middle of a path, and a suite that pinned
    # the scoping without pinning the bound would pin the half that is easy.
    #
    # `null` for a target with no `statePaths`, in which case there is no
    # snapshot and nothing to assert about one.
    snapshotCases = let
      snapshot = hostPrograms.stateSnapshotFor "src";
      # The bound as a program, so the case suite runs the real fragment rather
      # than a description of it (host/quarantine.nix).
      token = pkgs.writeText "capsule-token-check" ''
        ${(import ./host/quarantine.nix).checkToken ''"$1"'' "'unit $1'"}
      '';
    in
      pkgs.runCommand "capsule-snapshot-cases" {nativeBuildInputs = [pkgs.git];} ''
        export HOME=$PWD GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
        export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
        export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
        fail=0
        ck() {
          if [ "$2" = "$3" ]; then echo "ok   $1" >>"$log"
          else echo "FAIL $1: exit $3, wanted $2" >&2; fail=1; fi
        }
        ckt() {
          if "''${@:2}"; then echo "ok   $1" >>"$log"
          else echo "FAIL $1" >&2; fail=1; fi
        }
        log=$PWD/log
        : >"$log"

        # ------------------------------------------------------- the token bound
        #
        # `.` and `..` are the cases the character class admits and the comment
        # always claimed it did not. Harmless while a token only ever landed at
        # the end of a ref; a path escape the moment one lands in the middle of a
        # path, which is what a unit token does.
        for good in 254 a.b-c_d 0 x; do
          rc=0; bash ${token} "$good" >/dev/null 2>&1 || rc=$?
          ck "token '$good' is a name" 0 "$rc"
        done
        for bad in "" . .. a/b "a b" 'a;b' '$x' '*'; do
          rc=0; bash ${token} "$bad" >/dev/null 2>&1 || rc=$?
          ck "token '$bad' is refused" 1 "$rc"
        done

        # ------------------------------------------------ a checkout of two units
        #
        # Shaped like the one the invariant was measured against: a runtime tier
        # the project ignores on purpose, authored content beside it, two units of
        # work in both, and an agent's uncommitted edit to one of them.
        mkdir src && cd src
        git init -q --initial-branch=work .
        printf '%s\n' '.doctrine/state/' > .gitignore
        mkdir -p .doctrine/slice/254 .doctrine/slice/253
        mkdir -p .doctrine/state/slice/254 .doctrine/state/slice/253
        echo authored-254 >.doctrine/slice/254/spec.md
        echo authored-253 >.doctrine/slice/253/spec.md
        echo code >src.txt
        git add -A && git commit -qm base
        echo "edited by the agent" >.doctrine/slice/254/spec.md
        echo phase-254 >.doctrine/state/slice/254/phase-01.md
        echo phase-253 >.doctrine/state/slice/253/phase-01.md
        echo scratch >notes.md
        cd ..

        # Into a file rather than down a pipe: `ckt` takes a command, and a
        # pipeline reaching it would grep `ckt`'s own output instead of git's —
        # which passes, silently, for the wrong reason.
        entries() { git -C src ls-tree -r --name-only "$1" >list; }

        # ------------------------------------------------------- no unit, no scope
        #
        # The guest's own guard, and the reason it is not left to the host's: a
        # missing token substitutes as the empty string, which collapses every
        # scoped path onto its parent — the unscoped collect wearing the scoped
        # one's name.
        rc=0; bash ${snapshot} implementation >out 2>err || rc=$?
        ck "refuses a scoped policy with no unit" 1 "$rc"
        ckt "  and says the two ends disagree" grep -q "scoped to one unit" err
        ckt "  and wrote no ref" \
          test -z "$(git -C src for-each-ref 'refs/capsule/state/')"

        # ----------------------------------------------------------- scoped, green
        rc=0; bash ${snapshot} implementation 254 >out 2>err || rc=$?
        ck "takes a snapshot scoped to one unit" 0 "$rc"
        oid=$(cut -f1 out)
        ckt "  and reported a commit" test "$oid" != -

        entries "$oid"
        ckt "  the unit's runtime tier is in it" \
          grep -qx '.doctrine/state/slice/254/phase-01.md' list
        ckt "  the unit's authored tree is in it" \
          grep -qx '.doctrine/slice/254/spec.md' list
        # The invariant, stated as the thing that used to be false: another unit's
        # state in this exhibit is a second, older answer to the question the
        # exhibit exists to settle, and nothing in the tree marks which is which.
        ckt "  and no other unit's state is" \
          test -z "$(grep 253 list || true)"

        # Generic, so unscoped: "the agent has not committed this" is nobody's
        # project's concept and there is no template to put a hole in.
        ckt "  untracked-but-not-ignored still travels" grep -qx 'notes.md' list
        ckt "  and the tracked edit travels as the diff" \
          grep -qx '.capsule/dirty.diff' list
        # A state tree is worktree content, which is what makes `code-oid` a
        # control rather than a note (NOTES item 35).
        ckt "  the authored file carries the agent's uncommitted edit" \
          test "$(git -C src cat-file -p "$oid:.doctrine/slice/254/spec.md")" = "edited by the agent"
        # What the tree cannot say. An exhibit whose scope is not on the record is
        # one nobody can check the scope of.
        git -C src cat-file commit "$oid" >msg
        ckt "  the commit message names the unit" grep -qx 'unit: 254' msg
        ckt "  the agent's real index was not touched" \
          test -z "$(git -C src diff --cached --name-only)"

        # ------------------------------------------- a unit this checkout never had
        #
        # Not a refusal: a target says what its state *is*, not what any one run
        # produced, and that has to keep holding once the paths are scoped.
        rc=0; bash ${snapshot} implementation 999 >out 2>err || rc=$?
        ck "a unit with no state is a skip, not a failure" 0 "$rc"
        ckt "  and names the paths it skipped" grep -q 'slice/999 in this checkout' err
        oid=$(cut -f1 out)
        entries "$oid"
        ckt "  nothing of any unit is in it" \
          test -z "$(grep -E '25[34]|999' list || true)"
        ckt "  and the uncommitted work still is" grep -qx 'notes.md' list

        [ "$fail" = 0 ] || exit 1
        cp "$log" $out
        cat $out
      '';

    # `capsule`'s two policy limbs, run against a declaration that is not this
    # host's: the verb that selects one, and the collect that is filled from it.
    #
    # The third kind of check (CLAUDE.md), and its fourth instance. The branches
    # worth pinning are refusals a live host reaches expensively or destructively
    # — a slot declaring an empty set, an assigner naming a policy outside its
    # slot's set, and a re-point that cannot be written — and the one success that
    # matters is that the record and the allowlist link move *together*. Reaching
    # any of them here would mean editing `capsules.nix`, rebuilding the host, and
    # writing the live record of a slot that is actually assigned.
    #
    # Two seams, both already the ones the rule asks for: `capsules` is
    # substituted the way `guardCases` substitutes it, and `moduleState` — the one
    # thing tying this program to this host — is `host/cli.nix`'s argument, so the
    # record lands in the sandbox. Every real call site takes its default, so the
    # two shipped copies are still one store path.
    policyCases = let
      # Three slots, none of them this host's, each one a shape `capsules.nix`
      # itself would refuse: a set of one, a slot with no set at all, and a slot
      # whose declared default is not the first thing an assigner would pick.
      # That last is what makes "the record beats the declaration" assertable
      # rather than indistinguishable.
      fixture =
        capsules
        // {
          instances = capsules.instancesOf {
            one = {
              index = 0;
              policy = "build";
              policies = ["build"];
            };
            none = {index = 1;};
            both = {
              index = 2;
              policy = "sealed";
              policies = ["build" "sealed"];
            };
          };
        };
      cli = import ./host/cli.nix {
        inherit pkgs lib net target policies guestSsh;
        capsules = fixture;
        inherit (hostPrograms) observe programVerbs stateNeedsUnit;
        moduleState = ''"$CASE_STATE"'';
      };
      buildFile = policies.policies.build.allowlist;
      sealedFile = policies.policies.sealed.allowlist;
    in
      pkgs.runCommand "capsule-policy-cases" {nativeBuildInputs = [pkgs.jq];} ''
        export CASE_STATE=$PWD/state
        mkdir -p "$CASE_STATE" stub policies
        touch policies/${buildFile} policies/${sealedFile}

        # What `work` execs once the front end has filled the flags in.
        # `capsule-collect` is deliberately *not* one of the front end's
        # `runtimeInputs` — it picks between two copies of it on PATH — so a stub
        # on PATH is what it finds, and this is the one place a case can watch
        # what the front end decided rather than what it said.
        cat > stub/capsule-collect <<'EOF'
        #!/bin/sh
        echo "collect argv: $*"
        EOF
        chmod +x stub/capsule-collect
        export PATH=$PWD/stub:$PATH

        capsule=${lib.getExe cli}
        log=$PWD/log
        : > "$log"
        fail=0
        run() {
          rc=0
          "$capsule" "$@" > out 2>&1 || rc=$?
        }
        ck() {
          if [ "$2" = "$3" ]; then
            echo "ok   $1" >> "$log"
          else
            echo "FAIL $1: exit $3, wanted $2" >&2
            sed 's/^/    /' out >&2
            fail=1
          fi
        }
        ckt() {
          if "''${@:2}"; then
            echo "ok   $1" >> "$log"
          else
            echo "FAIL $1" >&2
            sed 's/^/    /' out >&2
            fail=1
          fi
        }
        saw() { grep -qF -- "$1" out; }
        gen() { jq -r .generation "$CASE_STATE/slot/$1/assignment.json"; }

        # ------------------------------------- what an unassigned slot resolves to
        #
        # The operator's declaration, in both readers. `sealed` rather than the
        # first name in the vocabulary, so a reader that returned a constant would
        # be caught.
        run both policy
        ck "an unassigned slot reads its declared policy" 0 "$rc"
        ckt "  which is the operator's, not the vocabulary's first" saw sealed
        run both collect
        ck "and a collect on one is filled from the same declaration" 0 "$rc"
        ckt "  as --policy, before the program sees it" \
          saw "collect argv: --capsule both --policy sealed"

        # ------------------------------------------------------- the two refusals
        #
        # A declaration nobody can satisfy is not the same fault as an argument
        # outside a set, and a refusal for the wrong reason is a different program
        # passing — so each names its own half.
        run none policy build
        ck "a slot with no declared set refuses" 1 "$rc"
        ckt "  and names the declaration rather than the argument" \
          saw "declares no policies"
        run one policy sealed
        ck "a policy outside the slot's set refuses" 1 "$rc"
        ckt "  and names the argument rather than the declaration" \
          saw "may not take policy 'sealed'"
        ckt "  pointing at who may widen it" saw "capsules.nix"
        ckt "  and nothing was written" test ! -e "$CASE_STATE/slot/one/assignment.json"

        # The perimeter half is the module path's, and this copy has no policy
        # directory yet — which is also the proof that the selection above was
        # accepted, since this refusal is the next one after it.
        run one policy build
        ck "a selection with nowhere to point refuses" 1 "$rc"
        ckt "  naming the copy that can" saw "no policy directory"

        export CAPSULE_POLICY_DIR=$PWD/policies

        # ------------------------------------------ the record and the link, once
        run one policy build
        ck "a declared selection is taken" 0 "$rc"
        ckt "  the record says so" \
          test "$(jq -r .policy "$CASE_STATE/slot/one/assignment.json")" = build
        ckt "  the link beside it points at that policy's file" \
          test "$(readlink "$CASE_STATE/slot/one/allowlist")" = "$CAPSULE_POLICY_DIR/${buildFile}"
        ckt "  and the generation moved once" test "$(gen one)" = 1

        # A record that disagrees with the declaration is the whole point of there
        # being a record: an assigner selected, and that is what the slot runs.
        run both policy build
        ck "a slot may be moved off its declared default" 0 "$rc"
        ckt "  the link follows the record" \
          test "$(readlink "$CASE_STATE/slot/both/allowlist")" = "$CAPSULE_POLICY_DIR/${buildFile}"
        run both policy
        ck "and the record is what it reads back" 0 "$rc"
        ckt "  not the declaration" saw build
        run both collect
        ck "a collect is filled from the record once there is one" 0 "$rc"
        ckt "  and not from the declaration" \
          saw "collect argv: --capsule both --policy build"
        run both collect --policy sealed
        ck "an explicit --policy wins" 0 "$rc"
        ckt "  and is not doubled" \
          saw "collect argv: --capsule both --policy sealed"

        # ------------------------------------------------- the ordering, asserted
        #
        # The link is written inside the record's lock and *before* the document
        # (host/record.nix's `recordAlso`), so the only failure either can have
        # leaves both as they were. A directory where the link should be is how a
        # sandbox reaches that; on a live host it is a disk or a permission.
        rm "$CASE_STATE/slot/one/allowlist"
        mkdir "$CASE_STATE/slot/one/allowlist"
        touch "$CASE_STATE/slot/one/allowlist/occupied"
        # `build` again rather than another name, because `one` declares a set of
        # one: this has to fail at the link and not at the selection, which is
        # what the run before it already proved is checked first.
        run one policy build
        ck "a link that cannot be re-pointed refuses" 1 "$rc"
        ckt "  and says which policy still holds" saw "still holds build"
        ckt "  the record did not move" test "$(gen one)" = 1
        ckt "  and still names the old policy" \
          test "$(jq -r .policy "$CASE_STATE/slot/one/assignment.json")" = build

        [ "$fail" = 0 ] || exit 1
        cp "$log" $out
        cat $out
      '';

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

      # The module's *programs*, and the reason this line exists: everything else
      # here reads the unit graph, and a unit graph does not mention what the
      # module puts on a human's PATH. So `host/cli.nix` — imported at two call
      # sites, this file's and the module's — could gain an argument at one of
      # them and every check here still pass. It did: `observe` was added to the
      # devshell's copy only, and the failure landed in a host rebuild, which is
      # the one thing this derivation exists to prevent.
      #
      # `seq` on the store path rather than the string *of* it: forcing an
      # outPath evaluates the derivation, which is where a missing argument
      # throws, while embedding one would make every program a build input of a
      # text file and turn seconds into a full build. Names in the output, paths
      # never.
      installed =
        lib.filter (lib.hasPrefix "capsule")
        (map (p: builtins.seq p.outPath (p.pname or p.name))
          host.config.environment.systemPackages);

      # The guard reads `/proc/<pid>/ns/net` for processes owned by `microvm`, and
      # a hardened unit that may not do that does not fail — `ip netns pids`
      # returns a list with the unreadable processes missing, so the guard refuses
      # a correctly-bound guest and names the wrong cause. Nothing else pairs a
      # program's needs with its unit's permissions, and this is the file that
      # reads both, so it is asserted rather than remembered (NOTES item 30).
      guardCaps = host.config.systemd.services.capsule-perimeter-guard.serviceConfig.CapabilityBoundingSet;

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
      else if !(lib.elem "CAP_SYS_PTRACE" guardCaps)
      then throw "capsule-perimeter: the guard's CapabilityBoundingSet has no CAP_SYS_PTRACE, so `ip netns pids` will silently omit the VMM it is asked about and the guard will refuse a correctly-bound guest (NOTES item 30)."
      else
        pkgs.writeText "capsule-units.txt" ''
          units:
          ${lib.concatStringsSep "\n" units}

          programs:
          ${lib.concatStringsSep "\n" installed}
        '';

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
        # The `build` policy's file, named rather than defaulted: the perimeter
        # has no allowlist of its own any more, so a probe states which policy it
        # is asserting under exactly as a capsule does (NOTES item 36). This is
        # the one that has to admit an allowlisted host, since the round asserts
        # a 200 as well as a 403.
        ALLOWLIST="${policies.dir}/${policies.policies.build.allowlist}"
        # The other one, for the round that asserts a policy is selected rather
        # than shared: the same guest, restarted under this, refuses the host the
        # first one allowed — and is allowed again when it is put back.
        SEALED_ALLOWLIST="${policies.dir}/${policies.policies.sealed.allowlist}"
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
      inherit pkgs lib net target policies workBranch;
      access = guestSsh.viaSocket {
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
        # What a slot's record and the operator's declaration would supply, for
        # two capsules that are neither (NOTES item 36, item 32). The unit half
        # is present only where this target's state paths have a hole for one,
        # since a flag that scopes nothing is refused.
        COLLECT_ARGS=(--policy build${
          lib.optionalString nsPrograms.stateNeedsUnit " --unit probe"
        })
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
    nixosModules.capsule-perimeter = import ./host/services.nix {inherit net target capsules policies workBranch;};

    packages.${system} =
      lib.mapAttrs (_: cfg: cfg.config.microvm.declaredRunner) vms
      // baselinePackages
      // refreshPackages
      // adoptPackages
      // briefPackages
      // lib.optionalAttrs (hostPrograms.briefRunner != null) {inherit briefCases;}
      // lib.optionalAttrs (hostPrograms.stateSnapshotFor != null) {inherit snapshotCases;}
      // {
        inherit vm vm-stop capsule-halt capsule-net capsule-host;
        # The checks that need no root and no host: what the module says, what the
        # guard decides, and which policy a slot resolves to.
        inherit hostModuleUnits guardCases policyCases;
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
        ++ lib.attrValues baselinePackages
        ++ lib.attrValues refreshPackages
        ++ lib.attrValues adoptPackages
        ++ lib.attrValues briefPackages;
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
