{
  pkgs,
  lib,
  inputs,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;

  # The flake input's source tree: the committed HEAD of ~/dev/doctrine, sans
  # worktree dirt and sans .git.
  src = inputs.doctrine;

  # Reuse doctrine's own node_modules FOD (`nix build .#web-modules` over
  # there) rather than growing a second bun-install derivation here.
  nodeModules = inputs.doctrine.packages.${system}.web-modules;

  # Pure function of Cargo.lock — no toolchain involved, and doctrine's lock
  # has no git dependencies, so no outputHashes are needed.
  cargoVendor = pkgs.rustPlatform.importCargoLock {
    lockFile = "${src}/Cargo.lock";
  };

  # Offline crates: redirect crates.io at the vendored store path.
  cargoConfig = pkgs.writeText "cargo-config.toml" ''
    [source.crates-io]
    replace-with = "vendored-sources"

    [source.vendored-sources]
    directory = "${cargoVendor}"
  '';

  toolchain = pkgs.rust-bin.beta.latest.default;

  work = "/work";
  repo = "${work}/doctrine";
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
  };

  environment.systemPackages =
    [toolchain]
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
    ]);

  environment.variables = {
    CARGO_HOME = "${work}/.cargo";
    BUN_INSTALL_CACHE_DIR = "${work}/.bun-cache";
    # Keep rustc/link temporaries off the RAM-backed rootfs.
    TMPDIR = "${work}/tmp";
    LD_LIBRARY_PATH = lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib];
  };

  # Populate the volume on first boot; cheap no-ops afterwards, so the
  # checkout and build caches survive a reboot.
  systemd.services.capsule-seed = {
    description = "Seed /work with the doctrine checkout and offline deps";
    wantedBy = ["multi-user.target"];
    before = ["getty@ttyS0.service"];
    after = ["local-fs.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.coreutils];
    script = ''
      set -euo pipefail
      mkdir -p ${work}/tmp ${work}/.cargo ${work}/.bun-cache
      install -m644 ${cargoConfig} ${work}/.cargo/config.toml

      if [ ! -d ${repo} ]; then
        echo "seeding checkout"
        mkdir -p ${repo}
        cp -a ${src}/. ${repo}/
        chmod -R u+w ${repo}
      fi

      if [ ! -e ${repo}/web/map/node_modules ]; then
        echo "seeding node_modules"
        cp -a ${nodeModules}/node_modules ${repo}/web/map/node_modules
        chmod -R u+w ${repo}/web/map/node_modules
      fi
    '';
  };

  programs.bash.interactiveShellInit = "cd ${repo}";

  users.motd = ''
    doctrine capsule — offline. checkout at ${repo}

      just test        cargo test (crates vendored, no network needed)
      just web-build   bun install + vite build (node_modules pre-seeded)

    /work is a volume and persists across boots. `poweroff` to leave.
  '';
}
