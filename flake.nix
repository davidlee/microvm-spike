{
  description = "microvm.nix spike — firecracker capsules";

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

    # The capsule's payload. `git+file:` gives the committed tree of the local
    # repo — i.e. exactly a clean clone, no worktree dirt, no .git. Refresh with
    #   nix flake update doctrine
    # Kept as a flake (not `flake = false`) so the capsule can reuse doctrine's
    # own `web-modules` node_modules FOD instead of forking a second copy of it.
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

    mkVm = name: module:
      lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs;};
        modules = [
          microvm.nixosModules.microvm
          ./vm/common.nix
          module
          {networking.hostName = name;}
        ];
      };

    vms = {
      # Smoke test: does firecracker boot at all on this host.
      hello = mkVm "hello" ./vm/hello.nix;
      # The real target.
      capsule = mkVm "capsule" ./vm/capsule.nix;
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
        inherit vm;
        default = self.packages.${system}.capsule;
      };

    devShells.${system}.default = pkgs.mkShellNoCC {
      packages = [
        vm
        pkgs.firecracker
        microvm.packages.${system}.microvm # `microvm` CLI (host-module workflows)
      ];
      shellHook = ''
        echo "microvm spike — firecracker. run:  vm hello  |  vm capsule"
      '';
    };
  };
}
