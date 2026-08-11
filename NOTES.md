# microvm.nix spike — notes

Goal: a **capsule** — a firecracker microVM holding a clean checkout of
`~/dev/doctrine` that can run `just web-build` and `just test`.

## Layout

| path             | what                                                        |
| ---------------- | ----------------------------------------------------------- |
| `flake.nix`      | inputs, the two VMs, devshell, `vm` launcher                 |
| `vm/common.nix`  | shared guest config (firecracker, no net, serial console)    |
| `vm/hello.nix`   | smoke test VM                                                |
| `vm/capsule.nix` | the doctrine capsule                                         |
| `.vm/<name>/`    | per-VM runtime state — volume images, API socket (gitignored) |

## Running

```
direnv allow          # nix-direnv picks up the devshell
vm hello              # smoke test: firecracker boots, `hello` runs
vm capsule            # the real thing
```

`vm <name>` just makes `.vm/<name>/`, cds into it and runs
`nix run .#<name>`. The cd matters: the runner creates volume images and the
firecracker API socket in `$PWD`.

Inside the capsule you land in `/work/doctrine` as root. `poweroff` to leave.

First build is heavy — guest kernel, rust toolchain, bun, node_modules and the
vendored crate registry all go into a store disk image. The
`microvm.cachix.org` substituter in `flake.nix:nixConfig` covers microvm.nix's
own artifacts if you are in `nix.settings.trusted-users`; otherwise nix will
ask, or you build the hypervisor and kernel yourself.

## Why it is shaped this way

**Firecracker shares nothing.** `lib/runners/firecracker.nix:86` in microvm.nix:

```
else if shares != []
then throw "9p/virtiofs shares not implemented for Firecracker"
```

Same for device passthrough, balloon and hotplug memory. It also has no
user-mode networking — only tap, which needs host-side bridge/NAT setup. So:

- the guest `/nix/store` is a **generated disk image**, not the host's store;
- nothing can be mounted in from the host;
- **the VM has no network**, by design here.

Everything the build needs is therefore either baked into the closure or
seeded onto a volume at first boot.

**Checkout.** `inputs.doctrine.url = "git+file:///home/david/dev/doctrine"`.
A flake input over `git+file:` is the committed HEAD — a clean clone, no
worktree dirt, no `.git` directory. Pick up new commits with
`nix flake update doctrine`. It is kept as a *flake* (not `flake = false`) so
the capsule can consume doctrine's own `packages.web-modules` instead of
forking a second bun-install derivation; cost is that our lock pulls
doctrine's transitive inputs (`pub`, `llm-agents`, crane, …).

**Crates offline.** `rustPlatform.importCargoLock` over doctrine's
`Cargo.lock` — a pure function of the lock file, no toolchain needed, and that
lock has zero git dependencies so no `outputHashes` are required. Seeded as a
`[source.vendored-sources]` replacement in `/work/.cargo/config.toml`, so
`cargo test` never reaches for crates.io.

**node_modules offline.** Copied from doctrine's `web-modules` FOD into
`web/map/node_modules` on first boot.

**State.** One 32 GiB sparse volume at `/work` holds the checkout, `target/`,
`TMPDIR` and the caches, and survives reboots. It is deliberately not on the
rootfs — microvm.nix roots are tmpfs, i.e. guest RAM.

## Known gaps / things to check on first run

1. **`just web-build` runs `bun install` first.** node_modules is pre-seeded
   and `BUN_INSTALL_CACHE_DIR` points at the volume, but whether bun completes
   fully offline against a satisfied tree is unverified. If it reaches for the
   registry, the options are: give the capsule a tap interface, or call
   `bun run build` directly instead of the `web-build` recipe.
2. **`just test` may want a live Postgres.** doctrine's own flake sets
   `doCheck = false` with the comment *"tests need a live Postgres"*, though no
   `DATABASE_URL` appears in the tree. Not provisioned here; if it turns out to
   be needed, `services.postgresql.enable = true` in `vm/capsule.nix` is the
   fix.
3. **No `doctrine` binary in the guest** — so `just validate` / `just check`
   won't work, only the two target recipes. Adding
   `inputs.doctrine.packages.x86_64-linux.default` to `systemPackages` covers
   it at the cost of a bigger store disk.
4. **Toolchain pin drift.** The guest uses `rust-bin.beta.latest.default` from
   *this* flake's nixpkgs + rust-overlay, not doctrine's pins. Same channel,
   possibly a different revision.
5. **Getting results out** is console-only right now. No shares, no network —
   so build artifacts stay on the volume image.

## If networking becomes necessary

Firecracker only does tap. Host side needs a bridge or NAT for `vm-*` taps
(microvm.nix `doc/src/simple-network.md`), which means editing the NixOS host
config — out of scope for this spike directory. Guest side would be:

```nix
microvm.interfaces = [{
  type = "tap";
  id = "vm-capsule";
  mac = "02:00:00:00:00:01";
}];
```
