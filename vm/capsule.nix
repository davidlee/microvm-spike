{
  pkgs,
  lib,
  inputs,
  net,
  target,
  ...
}: let
  # The two paths the host also knows, so both come from target.nix rather than
  # being derived twice — the host pushes to `repo` and fetches from it, and it
  # resolves the caches and the baseline's record directory against `work`.
  work = target.volumePath;
  repo = target.guestPath;
  # $HOME lives on the volume, so ~/.claude, credentials and shell history
  # survive reboots.
  home = "${work}/home";

  # Static configuration the capsule renders from its own declared reservation
  # (target.nix's `guestConfig`), rather than carrying one in from a machine
  # that is not this one. It is config, not secret, so it rides in the closure
  # and needs no transport — but the tools look for it on the volume, so the
  # seed links it there.
  #
  # Links rather than copies, for the same reason it is derived rather than
  # copied: a copy on the volume outlives the sizes it was rendered from, and
  # nothing would say so. This way a rebuild replaces it and a fresh capsule
  # cannot start with a stale one.
  configLinks =
    lib.mapAttrsToList (path: text: {
      dest = "${work}/${path}";
      src = pkgs.writeText "capsule-${lib.replaceStrings ["/"] ["-"] path}" text;
    })
    target.guestConfig;

  # What a binary the guest did not build links against. One list, two
  # consumers: the login environment's `LD_LIBRARY_PATH` below, and nix-ld's,
  # which is the same question asked by a loader instead of by a linker.
  runtimeLibs = [pkgs.stdenv.cc.cc.lib pkgs.zlib];

  adminKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAgvwY62NVQgQkVkp5YbOKv26avHLypGNPdrOqKFtwjl david@Sleipnir"
  ];

  # The public half of the host's stop key: what a `microvm@<name>` unit's
  # `ExecStop` presents to ask this guest to reboot, which is the only clean
  # stop firecracker leaves available (host/halt.nix, NOTES item 11). Root's
  # alone — an unprivileged session cannot reboot anything, so giving it to the
  # agent would only widen what a key on the host reaches.
  #
  # Not the human's key, because the unit has no agent and no way into her home;
  # not in the store, because the private half is a secret; and required rather
  # than optional, because a guest that quietly omits it is one whose volume
  # gets power-cut — and it would say so for the first time at host shutdown.
  stopKey =
    if builtins.pathExists ./stop-key.pub
    then lib.removeSuffix "\n" (builtins.readFile ./stop-key.pub)
    else throw "vm/stop-key.pub is missing: generate this host's capsule stop key and commit its public half (README, 'Host requirements').";
  proxy = "http://${net.host}:${toString net.proxyPort}";
in {
  # claude-code is unfree; permit it by name rather than opening the whole
  # guest closure to unfree packages.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) ["claude-code"];

  microvm = {
    inherit (target.sizes) vcpu mem;
    volumes = [
      {
        image = "capsule-work.img";
        mountPoint = work;
        size = target.sizes.volume;
      }
    ];
    interfaces = [
      {
        type = "tap";
        id = net.tap;
        mac = net.mac;
      }
    ];
  };

  # Guest ring-0 is the input to KVM's attack surface (NOTES, "Security
  # posture"), and loading a module is the cheap way to get there from guest
  # root. Locking that raises the price to a guest kernel LPE. This is not a
  # perimeter control moved inward — the perimeter is still host-side; it makes
  # the host-guest boundary costlier to reach at all. The device set is fixed
  # and everything needed is loaded during boot, so nothing wants a module
  # later. Turn it off if you ever need one on demand (fuse, loop, nf_tables).
  security.lockKernelModules = true;
  security.protectKernelImage = true;

  # No resolver in the guest, which the boundary claim has always said and this
  # makes true: networkd pulled in systemd-resolved, leaving a stub on
  # 127.0.0.53 with no configured upstream and no route to one — it could only
  # ever SERVFAIL, but it answered, and a client that retries a stub is a client
  # that hangs. Names are resolved by the host's proxy instead, as the host, so
  # guest lookups inherit whatever the host resolves through (here: resolved ->
  # stubby -> ControlD over DoT). Nothing guest-side can bypass that, because
  # nothing guest-side has a route to a nameserver.
  services.resolved.enable = false;

  # Point-to-point link only. No gateway, no resolver: everything outbound
  # goes through the host's allowlist proxy, which does its own DNS.
  systemd.network = {
    enable = true;
    networks."10-capsule" = {
      matchConfig.MACAddress = net.mac;
      address = ["${net.guest}/${toString net.prefix}"];
      networkConfig.DHCP = "no";
      linkConfig.RequiredForOnline = "carrier";
    };
  };

  environment.systemPackages =
    [
      # The guest's own requirement, not the target's — and the guest's whole
      # part in the git channel: it commits locally and answers the host's
      # `upload-pack` and `receive-pack`. There are no capsule helpers in here
      # any more, because there is nothing for the guest to initiate.
      pkgs.git
    ]
    # The target's devshell tool set, built from the target's own nixpkgs pin so
    # the guest and that devshell cannot drift.
    ++ lib.optional (target.toolsPackage != null)
    inputs.target.packages.${pkgs.stdenv.hostPlatform.system}.${target.toolsPackage}
    # What that list leaves out because it assumes a host which has them.
    ++ map (name: pkgs.${name}) target.extraTools
    # Only in nixpkgs on recent channels; skip rather than break eval.
    ++ lib.optional (pkgs ? claude-code) pkgs.claude-code;

  environment.variables =
    {
      HTTP_PROXY = proxy;
      HTTPS_PROXY = proxy;
      http_proxy = proxy;
      https_proxy = proxy;
      NO_PROXY = "${net.host},localhost,127.0.0.1";
      no_proxy = "${net.host},localhost,127.0.0.1";

      # Keep compiler and link temporaries off the RAM-backed rootfs.
      TMPDIR = "${work}/tmp";
      # Anything built in the guest links against these at run time.
      LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;
    }
    // lib.mapAttrs (_: dir: "${work}/${dir}") target.caches;

  # A guest that cannot run a binary it downloaded cannot run most toolchains.
  # NixOS ships no `/lib64/ld-linux-x86-64.so.2`, so a pypi wheel's `ruff`, an
  # npm package's prebuilt node-gyp artefact or a Go module's vendored helper
  # dies with `Could not start dynamically linked executable` — which is exactly
  # what the second target's first baseline hit, one second in, after resolving
  # 31 packages through the proxy perfectly well (NOTES item 23).
  #
  # Not a `target.nix` field, and that is the finding rather than a shortcut:
  # every non-nix-native toolchain needs this and none of them parameterises it,
  # so it belongs beside `TMPDIR` and the caches in what the capsule *supplies*
  # (docs/contract-target.md). doctrine never hit it only because cargo links
  # against nix's own stdenv.
  #
  # It widens nothing outward. The perimeter is host-side, and a guest carrying a
  # compiler could already build and run whatever it liked; this only stops the
  # kernel refusing an interpreter that is missing for packaging reasons.
  programs.nix-ld = {
    enable = true;
    libraries = runtimeLibs;
  };

  programs.git = {
    enable = true;
    config = {
      user.name = "capsule";
      user.email = "capsule@localhost";
      init.defaultBranch = target.defaultBranch;
      # What makes `capsule-provision` land in the worktree and not just move a
      # ref: the host pushes the branch the guest has checked out, which git
      # refuses by default. `updateInstead` accepts it and checks it out, and
      # refuses while the worktree is dirty — which is the guard on the agent's
      # uncommitted work, and the reason a provision can fail mid-session.
      #
      # In /etc rather than in the repo so it cannot be lost to a re-init. Not a
      # control: the host decides what it pushes, and nothing here can widen
      # that.
      receive.denyCurrentBranch = "updateInstead";
    };
  };

  # The agent runs unprivileged. This is not the perimeter — egress and the
  # git ref restriction are enforced host-side, out of the guest's reach — it
  # just keeps a clumsy agent from wrecking the guest, and mirrors the uid
  # separation of the bwrap jails. uid 1000 matches the host user so ownership
  # reads correctly when the volume is inspected from outside — with fuse2fs or
  # debugfs, never `mount`: it is guest-written ext4 and mounting it hands the
  # metadata to the host kernel (docs/design.md).
  users.users.agent = {
    isNormalUser = true;
    uid = 1000;
    group = "users";
    home = home;
    createHome = false; # on the volume, made by capsule-seed
    openssh.authorizedKeys.keys = adminKeys;
  };

  # A host->guest door, so the console isn't the only session. It widens
  # nothing outbound: the guest still has no route past the proxy. The tap is
  # point-to-point, so this is reachable from this host and nowhere else.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
    # /etc is tmpfs here, so keys kept there would be regenerated every boot
    # and your known_hosts would fight it. Park them on the volume.
    hostKeys = [
      {
        path = "${work}/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };
  services.getty.autologinUser = lib.mkForce "agent";

  # Root is reachable by key from the host only — no password, no sudo, no su
  # for the agent. Admin is a thing you do from outside the jail.
  users.users.root.openssh.authorizedKeys.keys = adminKeys ++ [stopKey];

  # First boot: prepare the volume and make an empty repository for the host to
  # push into. No clone, so no network and no host service has to be up — the
  # capsule boots empty and gets its history when you provision it. That is what
  # makes the base commit an argument rather than a value in this closure.
  systemd.services.capsule-seed = {
    description = "Seed /work and the empty checkout";
    wantedBy = ["multi-user.target"];
    before = ["getty@ttyS0.service"];
    after = ["local-fs.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.coreutils pkgs.util-linux pkgs.git];
    script = ''
      mkdir -p ${work}/tmp ${home} ${work}/ssh ${lib.escapeShellArgs target.cachePaths}
      chmod 1777 ${work}/tmp
      # One-time migration for volumes seeded before the agent user existed.
      # Guarded on /work's owner so a populated target/ isn't walked each boot.
      if [ "$(stat -c %u ${work})" != "1000" ]; then
        chown -R agent:users ${work}
      fi
      chown agent:users ${home} ${lib.escapeShellArgs target.cachePaths}
      ${lib.concatMapStringsSep "\n" (f: ''
          install -d -o agent -g users ${builtins.dirOf f.dest}
          ln -sfn ${f.src} ${f.dest}
        '')
        configLinks}
      if [ ! -e ${repo}/.git ]; then
        install -d -o agent -g users ${repo}
        # --initial-branch explicitly, not via init.defaultBranch below: HEAD
        # must point at the branch `capsule-provision` pushes to, because
        # `receive.denyCurrentBranch` only governs a push to the branch HEAD
        # names. Seeded on any other branch, a provision creates the ref, skips
        # the guard entirely, never checks anything out, and leaves a repo with
        # history and no files — silently. The two values are the same one from
        # target.nix, and provision verifies it besides.
        runuser -u agent -- git init --quiet \
          --initial-branch=${target.defaultBranch} ${repo}
        echo "capsule-seed: ${repo} is empty — run capsule-provision on the host"
      fi
    '';
  };

  programs.bash.interactiveShellInit = ''
    [ -d ${repo} ] && cd ${repo}
    [ -f ${work}/.env ] && . ${work}/.env
  '';

  users.motd = ''
    ${target.name} capsule — confined. checkout at ${repo}

      ${target.commands}

    running as `agent` (uid 1000) — no sudo, no su.
    from the host: ssh agent@${net.guest}   admin: ssh root@${net.guest}
    $HOME is ${home} — on the volume, so ~/.claude survives reboots.

    git: commit locally, and there is nothing to push to. The host initiates
    both directions — `capsule-provision` puts history here, `capsule-collect`
    takes work out. If the checkout is empty, it has not been provisioned yet.

    egress: allowlist proxy at ${proxy} only — no default route.
    secrets: put `export ANTHROPIC_API_KEY=...` in ${work}/.env (sourced at login,
    persists on the volume).
  '';
}
