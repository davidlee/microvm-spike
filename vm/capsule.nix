{
  pkgs,
  lib,
  inputs,
  net,
  ...
}: let
  work = "/work";
  repo = "${work}/doctrine";
  remote = "git://${net.host}:${toString net.gitPort}/doctrine.git";
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
      echo "pushed to capsule/$name — on the host: git fetch .vm/host/doctrine.git 'refs/heads/capsule/*:refs/heads/capsule/*'"
    '';
  };
in {
  nixpkgs.overlays = [inputs.rust-overlay.overlays.default];

  microvm = {
    vcpu = 8;
    mem = 16384; # / is tmpfs, so guest RAM also pays for /tmp and rootfs
    volumes = [
      {
        image = "capsule-work.img";
        mountPoint = work;
        size = 32768; # sparse; holds the checkout, target/, caches
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
      pkgs.rust-bin.beta.latest.default
      capsule-clone
      capsule-push
    ]
    ++ (with pkgs; [
      just
      git
      bun
      nodejs_latest
      eslint
      typescript
      stdenv.cc # cc/ld — cargo's linker
      pkg-config
      openssl
      shellcheck
      procps
    ])
    # Only in nixpkgs on recent channels; skip rather than break eval.
    ++ lib.optional (pkgs ? claude-code) pkgs.claude-code;

  environment.variables = {
    HTTP_PROXY = proxy;
    HTTPS_PROXY = proxy;
    http_proxy = proxy;
    https_proxy = proxy;
    NO_PROXY = "${net.host},localhost,127.0.0.1";
    no_proxy = "${net.host},localhost,127.0.0.1";

    CARGO_HOME = "${work}/.cargo";
    BUN_INSTALL_CACHE_DIR = "${work}/.bun-cache";
    # Keep rustc/link temporaries off the RAM-backed rootfs.
    TMPDIR = "${work}/tmp";
    LD_LIBRARY_PATH = lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib];
  };

  programs.git = {
    enable = true;
    config = {
      user.name = "capsule";
      user.email = "capsule@localhost";
      init.defaultBranch = "edge";
    };
  };

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
    path = [pkgs.coreutils capsule-clone];
    script = ''
      mkdir -p ${work}/tmp ${work}/.cargo ${work}/.bun-cache
      capsule-clone || echo "capsule-seed: clone failed — start capsule-host, then run capsule-clone"
    '';
  };

  programs.bash.interactiveShellInit = ''
    [ -d ${repo} ] && cd ${repo}
    [ -f ${work}/.env ] && . ${work}/.env
  '';

  users.motd = ''
    doctrine capsule — confined. checkout at ${repo}

      capsule-clone         (re)fetch from the host mirror
      capsule-push <name>   push HEAD to capsule/<name> on the mirror
      just test / just web-build

    egress: allowlist proxy at ${proxy} only — no default route.
    secrets: put `export ANTHROPIC_API_KEY=...` in ${work}/.env (sourced at login,
    persists on the volume).
  '';
}
