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

    # Where a collected exhibit lives and what its refs are called. Bound here
    # rather than imported at each use because there are three now — the token
    # bound in `snapshotCases`, and both probes that assert a collect landed
    # where it was sent. A probe that spells a ref convention is a probe that
    # keeps asserting the old one after the convention moves, which is what
    # `refs/capsule/<name>/heads/` cost (NOTES item 38).
    quarantine = import ./host/quarantine.nix;

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
      inherit pkgs lib net target capsules policies workBranch;
      # The same socket expression the units inject, for the opposite purpose:
      # there it is the way in, here its existence is what says this copy is the
      # wrong one (host/guest-ssh.nix).
      access = guestSsh.direct {
        names = builtins.attrNames capsules.instances;
        socket = socketOf ''"$capsule"'';
      };
    };

    # The same values, rendered instead of interpolated — `target.nix`'s run-time
    # half as `<name>.json`, plus the one function that reads one back
    # ([item 51](./docs/ledger/051-the-target-in-four-store-paths.md) step 3).
    # Nothing consumes it yet; step 4 points the programs above at it, and until
    # then the suite beside it is what builds it.
    #
    # Built here rather than inside `host/programs.nix` for that file's own
    # reason: it is a function of `target` and of nothing else — no transport, no
    # capsule — so a second construction would have nothing to differ in, and one
    # store path is the honest statement of that.
    # A function of a target rather than the value, because the suite beside it
    # pins the render's *refusals* and needs to apply it to a fixture — and one
    # construction is the rule (CLAUDE.md), so this host's own profile is that
    # function applied to this host's target rather than a second import.
    render = t:
      import ./host/profile.nix {
        inherit pkgs lib;
        target = t;
      };
    # This host's own, taken from where the programs get it rather than built a
    # second time: `host/programs.nix` constructs it because both of its callers
    # need one and a value constructed twice is a value one of them can construct
    # differently (CLAUDE.md). `render` stays for the suite's fixtures alone.
    hostProfile = hostPrograms.profile;

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
      inherit pkgs lib net capsules policies guestSsh;
      inherit (hostPrograms) observe observeFragment programVerbs profileVerbs stateNeedsUnit;
    };

    # The third kind of check (CLAUDE.md): a host-side program's own text, run
    # with a substitute for the one thing tying it to this host. One file per
    # suite, beside the program it pins — what stays here is who each one runs
    # and what it is handed
    # ([item 51](./docs/ledger/051-the-target-in-four-store-paths.md)), because
    # the alternative was half this file.
    #
    # **A suite runs the store path the program ships**, which is what step 2 of
    # that item made possible: every program below arrives from `hostPrograms`
    # rather than being rendered a second time. The two exceptions are handed a
    # fixture on purpose — the guard its stubbed kernel, the front end a pool
    # that is not this host's — and each says so in its own header.
    guardCases = import ./host/guard-cases.nix {inherit pkgs lib net capsules;};

    briefCases = import ./host/brief-cases.nix {
      inherit pkgs;
      runner = hostPrograms.briefRunner;
      spec = hostPrograms.briefSpecChecker;
    };

    snapshotCases = import ./host/state-snapshot-cases.nix {
      inherit pkgs quarantine;
      snapshot = hostPrograms.stateSnapshotScript;
      # The other end of the same command line (item 51 step 4): the fragment
      # that builds it off a document, and the reader it needs.
      snapshotArgs = hostPrograms.snapshotArgsFragment;
      profileFragment = hostProfile.fragment;
      inherit (hostProfile) inputs;
    };

    baselineCases = import ./host/baseline-cases.nix {
      inherit pkgs;
      runner = hostPrograms.baselineRunner;
    };

    observeCases = import ./host/observe-cases.nix {
      inherit pkgs;
      inherit (hostPrograms) observe observeFragment;
      inherit (hostProfile) inputs;
    };

    refreshCases = import ./host/refresh-cases.nix {
      inherit pkgs lib;
      script = hostPrograms.refreshScript;
    };

    # The ninth, and the first over a program that talks to a guest: what it can
    # reach is everything upstream of the door, which is the whole of what step 4
    # of [item 51](./docs/ledger/051-the-target-in-four-store-paths.md) rewrote.
    # The slot name is this host's declaration and not a fixture, because the
    # shipped program has that list baked in — see the file's own header.
    gitChannelCases = import ./host/git-channel-cases.nix {
      inherit pkgs lib;
      inherit (hostPrograms) provision collect;
      slot = builtins.head (builtins.attrNames capsules.instances);
    };

    # The one suite whose subject is a *library* rather than a program, and the
    # only thing that builds the rendered document — which is why it is not
    # optional on anything (host/profile-cases.nix).
    profileCases = import ./host/profile-cases.nix {
      inherit pkgs lib;
      inherit (hostProfile) fragment select inputs dir name;
      # The same construction this host's own profile comes from, so the suite
      # can watch the render *refuse* a target. A throw is not a build, so it is
      # read at eval and asserted in the shell — `hostModuleUnits`' arrangement.
      inherit render;
    };

    policyCases = import ./host/policy-cases.nix {
      inherit pkgs lib net capsules policies guestSsh;
      inherit (hostPrograms) observe observeFragment programVerbs profileVerbs stateNeedsUnit;
    };

    # The host module has no build of its own — it is a NixOS module, and this
    # repo cannot rebuild someone's host to try it. So *evaluate* it: a text
    # file naming the units it generates drags the whole module through the
    # evaluator, which is where a wrong option name, a bad interpolation or a
    # failed assertion actually lives. Seconds, no NixOS build, and it is in
    # `just build` — the alternative was finding those in a host rebuild.
    # Two derivations off one evaluation of the module: what it *says*
    # (`hostModuleUnits`, seconds, no build) and what it *runs*
    # (`hostModulePrograms`, a build, because shellcheck is a build).
    hostModule = let
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
      directives = n:
        literals (lib.attrValues (host.config.systemd.services.${n}.serviceConfig or {}));
      newlined = lib.filter (n: lib.any (lib.hasInfix "\n") (directives n)) units;

      # A bound path is mounted as **root** and opened as the unit's **user**, so
      # `BindReadOnlyPaths` naming a file under a directory that user cannot
      # traverse builds a unit that starts and then dies at `open()` — `filter
      # file: Permission denied` about a path that is plainly there, with the
      # bind itself reported as fine. Every capsule proxy was in exactly that
      # state, on every slot and under every policy, and the only witness was one
      # line in one unit's journal ([NOTES item 39]).
      #
      # Evaluable because both halves are this module's own declarations: its `d`
      # rules say what mode it gives each directory it creates, and each unit says
      # who it runs as. Same shape as the guard's capability pairing above and as
      # `borrowed` in the probe fabric — the alternative is a comment that is true
      # on the day it is written. It cannot see directories the module did not
      # declare, which is the honest limit: it pairs what this repo controls.
      dirRules =
        lib.filter (d: d != null)
        (map (
            rule: let
              w = lib.filter (s: s != "") (lib.splitString " " rule);
              at = i: lib.elemAt w i;
            in
              if lib.length w >= 5 && at 0 == "d"
              then {
                path = at 1;
                # tmpfiles' own defaults for `-`, so a rule that declines to say
                # is read as what it will actually produce.
                mode =
                  if at 2 == "-"
                  then "0755"
                  else at 2;
                owner =
                  if at 3 == "-"
                  then "root"
                  else at 3;
                group =
                  if at 4 == "-"
                  then "root"
                  else at 4;
              }
              else null
          )
          host.config.systemd.tmpfiles.rules);

      # Traversal is the `x` bit, and for a user who is neither the owner nor in
      # the group that is the *others* digit. Group membership is a declaration
      # too, so it is read rather than assumed.
      othersTraverse = mode: lib.elem (lib.last (lib.stringToCharacters mode)) ["1" "3" "5" "7"];
      mayTraverse = user: d:
        d.owner
        == user
        || lib.elem user (host.config.users.groups.${d.group}.members or [])
        || othersTraverse d.mode;

      binds = n: let
        v = host.config.systemd.services.${n}.serviceConfig.BindReadOnlyPaths or [];
      in
        map (e: lib.head (lib.splitString ":" e)) (lib.toList v);

      unreachable = lib.concatMap (n: let
        user = host.config.systemd.services.${n}.serviceConfig.User or "root";
      in
        if user == "root"
        then []
        else
          lib.concatMap (
            p:
              map (d: "${n} runs as ${user} and binds ${p}, which is under ${d.path} (${d.mode} ${d.owner}:${d.group}) — it cannot traverse that, so the open fails though the mount does not")
              (lib.filter (d: lib.hasPrefix "${d.path}/" p && !(mayTraverse user d)) dirRules)
          )
          (binds n))
      units;

      # `capsule <slot> policy <name>` ends in `sudo systemctl restart
      # capsule-proxy-<slot>`, and on a host that does not permit it the verb
      # cannot finish — it now undoes the selection rather than half-applying it,
      # but a verb built to be *delegable* that always refuses is not delegable
      # (NOTES item 41). Both halves are this module's own declarations: the
      # proxy units it makes, and the rule it installs for them. Fourth instance
      # of the shape, after the guard's capability (item 30) and the bind's
      # traversal (item 39) — and this one earns its place twice, because nothing
      # else here reads `security.sudo.extraRules` at all, so without it a type
      # error in that rule would surface in a host rebuild.
      #
      # The literal path is sudo's, not nix's: sudo resolves the command against
      # its own `secure_path` before matching, so a rule naming a store path would
      # look right and never fire (host/services.nix says the same where the rule
      # is written).
      sudoCommands =
        lib.concatMap (r: map (c: c.command or c) r.commands)
        host.config.security.sudo.extraRules;
      unrestartable =
        lib.filter (n: !(lib.elem (import ./host/proxy-restart.nix n) sudoCommands))
        (lib.filter (lib.hasPrefix "capsule-proxy-") units);

      # Refused before either derivation is named, so a `nix build` of the
      # programs cannot pass a module whose units are wrong.
      checked = drv:
        if failed != []
        then throw "capsule-perimeter: ${lib.concatMapStringsSep "; " (a: a.message) failed}"
        else if newlined != []
        then throw "capsule-perimeter: a newline in a serviceConfig value of ${lib.concatStringsSep ", " newlined} — systemd reads that as unbalanced quoting and drops the rest of the unit. Put the script in the store and name it."
        else if !(lib.elem "CAP_SYS_PTRACE" guardCaps)
        then throw "capsule-perimeter: the guard's CapabilityBoundingSet has no CAP_SYS_PTRACE, so `ip netns pids` will silently omit the VMM it is asked about and the guard will refuse a correctly-bound guest (NOTES item 30)."
        else if unreachable != []
        then throw "capsule-perimeter: ${lib.concatStringsSep "; " unreachable} (NOTES item 39)."
        else if unrestartable != []
        then throw "capsule-perimeter: no sudoers rule permits restarting ${lib.concatStringsSep ", " unrestartable}, so `capsule <slot> policy <name>` cannot finish a selection for those slots and will undo it instead (NOTES item 41)."
        else drv;
    in {
      units = checked (pkgs.writeText "capsule-units.txt" ''
        units:
        ${lib.concatStringsSep "\n" units}

        programs:
        ${lib.concatStringsSep "\n" installed}
      '');

      # **The exact inversion of the rule one comment up**, and deliberately a
      # second derivation for it: embedding the *string* of a store path makes
      # every program a build input, which is why `installed` refuses to — and
      # is the only way to make shellcheck run on a program no flake output
      # names. `capsule-netns` and `capsule-egress-ns` are only ever an
      # ExecStart, so nothing in `just build` had ever built them and a rollback
      # written into one shipped unchecked (NOTES item 37).
      #
      # Every serviceConfig literal, not a hand-listed set, so a program added
      # to a unit tomorrow is checked without this line being touched.
      programs =
        checked (pkgs.writeText "capsule-module-programs.txt"
          (lib.concatStringsSep "\n" (lib.concatMap directives units)));
    };

    hostModuleUnits = hostModule.units;
    hostModulePrograms = hostModule.programs;

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
    #
    # Harness, then prelude, then probe. The harness declares an empty default
    # for every value a prelude may inject — which is what lets it carry the
    # egress fabric below without every probe that never builds one tripping
    # SC2154 — so the prelude has to come *after* it or those defaults would win.
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
          builtins.readFile ./probe/harness.sh
          + prelude
          + builtins.readFile script;
      };

    # The names, links and addressing a probe's egress fabric is built from —
    # **and the eval-time refusal to share any of them with `capsules.nix`**,
    # which is the whole reason this is a value here rather than four literals in
    # `probe/harness.sh`.
    #
    # `capsules.nix` copied its map *from* `probe/netns-egress.sh` once that probe
    # had verified the shape, so the probe became a borrower of live addressing
    # with no line of it changing and nothing to notice: on a module-path host
    # `eg-rt` is the live aggregator's uplink to the root namespace, and the
    # probe's own teardown deletes that name (NOTES item 38). The rule about not
    # borrowing live addressing needs an enforcer, because it is broken by the
    # *other* file moving.
    #
    # A separate /16 and /30 is what keeps every per-index address off the live
    # fabric without asserting each one — the harness derives `<base>.<i>.{1,2}`
    # the same way `capsules.nix` does.
    probeFabric = rec {
      ns = "probe-egress";
      peerNs = "probe-peer";
      dev = "pr-up";
      peer = "pr-rt";
      addr = "10.111.0.2";
      peerAddr = "10.111.0.1";
      netBase = "10.110";
      net = "${netBase}.0.0/16";
      uplinkNet = "10.111.0.0/30";
      outPrefix = "pr-out";
      wanPrefix = "pr-wan";
    };

    # Every string this host's declaration puts on a wire or in `ip netns list`.
    # A probe may reuse none of them.
    liveNames = let
      eg = capsules.egress;
      c = i: [i.ns i.uplink.dev i.uplink.peer i.uplink.addr i.uplink.gw];
    in
      [eg.ns eg.dev eg.peer eg.addr eg.peerAddr capsules.uplinkNet]
      ++ lib.concatMap c (lib.attrValues capsules.instances);

    borrowed =
      lib.intersectLists (lib.attrValues probeFabric) liveNames;

    fabricPrelude = assert borrowed
    == []
    || throw "flake.nix: probeFabric borrows '${builtins.head borrowed}' from capsules.nix — a probe's fabric may share no name, link, address or network with the live one (NOTES item 38)"; ''
      EG_NS="${probeFabric.ns}"
      EG_DEV="${probeFabric.dev}"
      EG_PEER="${probeFabric.peer}"
      EG_ADDR="${probeFabric.addr}"
      EG_PEER_ADDR="${probeFabric.peerAddr}"
      EG_NET="${probeFabric.net}"
      EG_NET_BASE="${probeFabric.netBase}"
      EG_UPLINK_NET="${probeFabric.uplinkNet}"
      EG_OUT_PREFIX="${probeFabric.outPrefix}"
      EG_WAN_PREFIX="${probeFabric.wanPrefix}"
    '';

    # The fabric, plus what a round that puts a *proxy* on it needs. Two strings
    # because `probe/netns.sh` builds the fabric with no proxy in it, and an
    # allowlist path a probe never reads is an unused variable — which is a build
    # failure here rather than a stray line.
    egressPrelude =
      fabricPrelude
      + ''
        PROXY_PORT="${toString net.proxyPort}"
        PROXY="${perimeter.proxy}/bin/capsule-proxy"
        # The two policies a wire round asserts under, named rather than
        # defaulted: the perimeter has no allowlist of its own any more, so a
        # probe states which policy it is asserting under exactly as a capsule
        # does (NOTES item 36). `build` is the one that has to admit a host,
        # since every round asserts a 200 as well as a 403; `sealed` must not.
        ALLOWLIST="${policies.dir}/${policies.policies.build.allowlist}"
        SEALED_ALLOWLIST="${policies.dir}/${policies.policies.sealed.allowlist}"
      '';

    # This flake's copy of the namespace layer. `host/services.nix` builds its
    # own from the module's `pkgs`, which is a different nixpkgs and therefore a
    # different store path — one *file*, two instantiations, exactly as
    # `guardCases` already instantiates it against a fixture. What must not
    # happen is a second file: a probe that reimplemented `up` and `down` would
    # assert that its own shell agrees with itself.
    netns = import ./host/netns.nix {inherit pkgs lib net capsules;};

    # Does a network namespace per capsule hold up (docs/plan-c-multi-capsule.md, "Netns per
    # capsule")? Models two capsules with identical addressing and no VM, on
    # addressing deliberately unlike the live capsule's.
    probe-netns = probe {
      name = "probe-netns";
      script = ./probe/netns.sh;
      # Its links and namespaces were always its own (`spk-*`, `capspk-*`); its
      # *addressing* was the live aggregator's, and stage 2 puts `10.101.0.1` and
      # a route for `10.100.0.0/16` in the **root** namespace. Third instance of
      # NOTES item 38, and the reason the fix is a value rather than a rename.
      prelude = fabricPrelude;
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
    # Does a capsule's namespace survive being torn down and rebuilt (NOTES item
    # 37)? Drives the **real** `capsule-netns` through the seam it already has —
    # every per-capsule value comes from its unit's `Environment=`, so a probe
    # supplies a whole capsule's worth of addressing that is nobody's capsule.
    # No VM, no tap, no guest, and nothing in the root namespace.
    probe-netns-restart = probe {
      name = "probe-netns-restart";
      script = ./probe/netns-restart.sh;
      # The program, not its text. Same store path `host/services.nix` puts in
      # an ExecStart, up to the nixpkgs each was built from.
      prelude = ''
        CAPSULE_NETNS="${lib.getExe netns.programs.capsule}"
      '';
      runtimeInputs = [
        pkgs.iproute2
        pkgs.procps
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gawk # `since`, in the harness
      ];
    };

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
      prelude =
        egressPrelude
        + ''
          TAP="${net.tap}"
          HOST_ADDR="${net.host}"
          GUEST_ADDR="${net.guest}"
          PREFIX="${toString net.prefix}"
          VM="capsule"
          # The VM-less sibling that exists to be unreachable. Prefixed like the
          # rest of the fabric rather than `cap-`, which is what a slot's
          # namespace is called.
          NSPEER="${probeFabric.peerNs}"
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
      inherit pkgs lib net target capsules policies workBranch;
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
      prelude =
        egressPrelude
        + ''
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
          # Where a collect lands, from the one construction that decides it
          # rather than from this file's memory of it. The probe used to spell
          # `refs/capsule/<name>/<branch>` and was two assertions red from the
          # day item 32 split the code half under `heads/` — silently, because
          # nothing runs a probe (NOTES item 38).
          CODE_REFS_A="${quarantine.codeRefsOf pairA}"
          CODE_REFS_B="${quarantine.codeRefsOf pairB}"
        '';
      runtimeInputs = [
        pkgs.iproute2
        pkgs.iputils
        pkgs.nftables # the aggregator's drops, and each capsule's own
        pkgs.procps
        pkgs.coreutils # du, dirname, date, tr
        pkgs.gnugrep
        pkgs.gnused # the allowed host comes out of the allowlist, not the probe
        pkgs.gawk # the arithmetic behind every figure
        pkgs.util-linux # runuser: enter the namespace as root, boot the VM as you
        pkgs.glibc.bin # getent, for the human's home directory
        pkgs.bash
        pkgs.socat
        pkgs.openssh
        pkgs.bind.dnsutils # whether the host's own resolver is reachable
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

        # `capsule-halt` is namespace-relative and takes no transport, by design:
        # it is always run somewhere ${net.guest} is directly routable — the unit
        # from inside the capsule's own namespace, this program from the root one
        # where the devshell path's tap lives. So it is not that a transport was
        # forgotten here; it is that *this* copy is only correct on a host whose
        # taps are in the root namespace, and the module path's are not.
        #
        # Which makes this `direct`'s second refusal (host/guest-ssh.nix), owed by
        # a program that never selects a capsule because its argv is the name
        # already. Without it the ssh times out at ${net.guest}, `capsule-halt`
        # reports "no guest answering" — naming the wrong cause, since the guest
        # answers fine through its relay — and then `own_vms` correctly finds no
        # VMM of *this* namespace and the fall-through prints `is down` over a
        # capsule still running. Two true-in-scope sentences that compose into a
        # false one, which is the `pkill -f` trap one level up: the scoping is
        # right and the claim it licenses is not.
        sock=${socketOf ''"$name"''}
        if [ -S "$sock" ]; then
          echo "capsule '$name' is on the module path here ($sock exists), and this" >&2
          echo "  is the devshell's stop: it would ask a guest that is not routable" >&2
          echo "  from this namespace, then report a VMM it cannot see as down." >&2
          echo "    /run/current-system/sw/bin/capsule $name stop" >&2
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
      // lib.optionalAttrs (hostPrograms.stateSnapshotScript != null) {inherit snapshotCases;}
      // lib.optionalAttrs (hostPrograms.refreshScript != null) {inherit refreshCases;}
      // lib.optionalAttrs (hostPrograms.baselineRunner != null) {inherit baselineCases;}
      // {
        inherit vm vm-stop capsule-halt capsule-net capsule-host;
        # The checks that need no root and no host: what the module says, what the
        # guard decides, and which policy a slot resolves to.
        inherit hostModuleUnits hostModulePrograms guardCases policyCases observeCases;
        inherit profileCases gitChannelCases;
        # The rendered run-time half of `target.nix`, so a human can read what a
        # program will resolve (host/profile.nix). `nix build .#capsule-profiles`.
        capsule-profiles = hostProfile.dir;
        inherit capsule-cli capsule-provision capsule-collect capsule-inject;
        inherit probe-netns probe-netns-restart probe-netns-boot probe-netns-egress;
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
