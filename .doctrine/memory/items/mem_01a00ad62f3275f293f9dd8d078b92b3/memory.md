Verified in microvm.nix source. `lib/runners/firecracker.nix` **throws** on:
9p/virtiofs **shares**, device passthrough, balloon, hotplug memory, and
`user != null`. It has **no user-mode networking** (tap only), and microvm.nix
has **no jailer support**.

Consequences, which shape nearly every decision here:

- **No host directory can ever be mounted into the guest.** Anything that must
  get in comes over the tap or is baked into the closure.
- The guest store is a generated **read-only image**; `nix` in the guest would
  need `writableStoreOverlay` plus its own volume.
- **Guest roots are tmpfs, i.e. guest RAM** — hence `/work` on a volume for the
  checkout, `target/`, `TMPDIR` and caches.

The absence of a balloon and of free-page reporting is also why a capsule holds
most of its ceiling until it is stopped (`QUE-004`).