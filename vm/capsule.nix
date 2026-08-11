{
  pkgs,
  lib,
  inputs,
  net,
  target,
  ...
}: let
  work = "/work";
  repo = "${work}/${target.name}";
  # $HOME lives on the volume, so ~/.claude, credentials and shell history
  # survive reboots.
  home = "${work}/home";
  remote = "git://${net.host}:${toString net.gitPort}/${target.name}.git";

  # Caches that would otherwise land on the RAM-backed rootfs. One declaration
  # (target.nix) for the env vars and for the directories the seed must create.
  cacheDirs = lib.mapAttrsToList (_: dir: "${work}/${dir}") target.caches;

  adminKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAgvwY62NVQgQkVkp5YbOKv26avHLypGNPdrOqKFtwjl david@Sleipnir"
  ];
  proxy = "http://${net.host}:${toString net.proxyPort}";

  # Fetch the real history from the host's mirror. Split out from the seed
  # service so it can be re-run by hand when the host side comes up late.
  capsule-clone = pkgs.writeShellApplication {
    name = "capsule-clone";
    runtimeInputs = [pkgs.git];
    text = ''
      if [ -e ${repo}/.git ]; then
        echo "already cloned; fetching"
        git -C ${repo} fetch origin
        exit 0
      fi
      git clone ${remote} ${repo}
    '';
  };

  # The mirror's update hook refuses anything outside refs/heads/capsule/*.
  capsule-push = pkgs.writeShellApplication {
    name = "capsule-push";
    runtimeInputs = [pkgs.git];
    text = ''
      name="''${1:?usage: capsule-push <name>}"
      git -C ${repo} push origin "HEAD:refs/heads/capsule/$name"
      echo "pushed to capsule/$name — on the host: just fetch"
    '';
  };
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
      capsule-clone
      capsule-push
      # git is the guest's own requirement, not the target's: the two helpers
      # above are a clone and a push.
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
      LD_LIBRARY_PATH = lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib];
    }
    // lib.mapAttrs (_: dir: "${work}/${dir}") target.caches;

  programs.git = {
    enable = true;
    config = {
      user.name = "capsule";
      user.email = "capsule@localhost";
      init.defaultBranch = target.defaultBranch;
    };
  };

  # The agent runs unprivileged. This is not the perimeter — egress and the
  # git ref restriction are enforced host-side, out of the guest's reach — it
  # just keeps a clumsy agent from wrecking the guest, and mirrors the uid
  # separation of the bwrap jails. uid 1000 matches the host user so ownership
  # reads correctly when the volume is inspected from outside — with fuse2fs or
  # debugfs, never `mount`: it is guest-written ext4 and mounting it hands the
  # metadata to the host kernel (NOTES.md).
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
  users.users.root.openssh.authorizedKeys.keys = adminKeys;

  # First boot: prepare the volume and pull the checkout. Non-fatal if the
  # host side isn't running yet — `capsule-clone` retries.
  systemd.services.capsule-seed = {
    description = "Seed /work and clone from the host mirror";
    wantedBy = ["multi-user.target"];
    before = ["getty@ttyS0.service"];
    after = ["local-fs.target" "systemd-networkd-wait-online.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.coreutils pkgs.util-linux capsule-clone];
    script = ''
      mkdir -p ${work}/tmp ${home} ${work}/ssh ${lib.escapeShellArgs cacheDirs}
      chmod 1777 ${work}/tmp
      # One-time migration for volumes seeded before the agent user existed.
      # Guarded on /work's owner so a populated target/ isn't walked each boot.
      if [ "$(stat -c %u ${work})" != "1000" ]; then
        chown -R agent:users ${work}
      fi
      chown agent:users ${home} ${lib.escapeShellArgs cacheDirs}
      runuser -u agent -- capsule-clone \
        || echo "capsule-seed: clone failed — start capsule-host, then run capsule-clone"
    '';
  };

  programs.bash.interactiveShellInit = ''
    [ -d ${repo} ] && cd ${repo}
    [ -f ${work}/.env ] && . ${work}/.env
  '';

  users.motd = ''
    ${target.name} capsule — confined. checkout at ${repo}

      capsule-clone         (re)fetch from the host mirror
      capsule-push <name>   push HEAD to capsule/<name> on the mirror
      ${target.commands}

    running as `agent` (uid 1000) — no sudo, no su.
    from the host: ssh agent@${net.guest}   admin: ssh root@${net.guest}
    $HOME is ${home} — on the volume, so ~/.claude survives reboots.

    egress: allowlist proxy at ${proxy} only — no default route.
    secrets: put `export ANTHROPIC_API_KEY=...` in ${work}/.env (sourced at login,
    persists on the volume).
  '';
}
