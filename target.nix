# The repo the capsule confines, and the settings that follow from it. Its own
# file for the same reason as net.nix: several places need these values and none
# of them may spell them twice.
#
# What cannot live here is the flake reference itself — an input's url must be a
# literal in flake.nix — so `inputs.target` there and `path` here name the same
# repo and nothing checks that they agree. Change both to switch targets, or
# `--override-input target path:/…` for a one-off. See NOTES item 16.
#
# Everything here is host-side on purpose. Nothing below is read *from* the
# target repo: the allowlist is a control, and a control the confined thing can
# edit is not a control. Only the tool set comes from the target, because that is
# a build input rather than a control.
#
# `rec`, for one reason: `guestPath` is a path both sides must agree on, and
# deriving it keeps the target named once.
rec {
  # The guest's checkout directory name, and the motd.
  name = "doctrine";

  # Read by `capsule-provision` only, and always as the human — it is the source
  # of the push that provisions a capsule. Nothing serves it and nothing else
  # reads it.
  path = "/home/david/dev/doctrine";

  # The guest's checkout, absolute. Both sides need it: `vm/capsule.nix` creates
  # it on the volume, and the host's git channel pushes to it and fetches from
  # it. It has to sit under the volume's mount point, which is the guest's own
  # business (`work` in vm/capsule.nix) — this is the one part of the layout the
  # host is entitled to know.
  guestPath = "/work/${name}";

  # Package in the target's own flake carrying its devshell tool set, so the
  # guest and that devshell cannot drift. `null` for a target with no flake:
  # the guest then gets `extraTools` and nothing else, and loses that property.
  toolsPackage = "dev-tools";

  # Tools the target's list assumes the host already has, so it does not carry
  # them. nixpkgs attr names, resolved against the guest's pkgs.
  extraTools = ["pkg-config" "openssl"];

  # Proxy hostname allowlist, relative to CAPSULE_ROOT so a moved checkout still
  # finds it, and a plain file rather than a store path so editing it needs no
  # rebuild. One file per target: a second target gets its own, since half of
  # any such list is that target's dependency hosts.
  allowlist = "perimeter/egress-allow.txt";

  # Toolchain-shaped rather than repo-shaped, which is why they are here: caches
  # that must live on the volume instead of in guest RAM. Env var -> directory
  # under /work; the guest's seed service creates and chowns exactly these.
  caches = {
    CARGO_HOME = ".cargo";
    BUN_INSTALL_CACHE_DIR = ".bun-cache";
  };

  # The branch the guest works on, and the branch `capsule-provision` lands a
  # base commit onto — which is *any* ref in the target repo, so a capsule's
  # base is an argument rather than a value in the guest's closure. The guest's
  # HEAD must name this branch or a provision silently does not check out; the
  # seed sets it, and provision verifies it.
  defaultBranch = "edge";

  # Largest packfile one `capsule-collect` may write, as `ulimit -f`. A backstop
  # on the file, not a bound on the transfer — many small objects or a delta bomb
  # go straight past it (NOTES item 18). 512 MiB against a 32 MiB repo leaves
  # room for a working history.
  collectMaxPackBytes = 536870912;

  # Shown in the motd: the target's own entrypoints, so the agent need not guess.
  commands = "just test / just web-build";

  # The guest is sized for this target's build, not for the host.
  #
  # `mem` is a ceiling, not a charge: firecracker does not preallocate and the
  # guest's root is tmpfs, so two booted capsules cost ~1.5 GiB between them
  # against 32 GiB declared (docs/probes.md, the pair probe — it withdrew the
  # opposite claim, which had been read off this file rather than measured).
  # What makes the ceiling matter anyway is that there is no balloon: a capsule
  # is charged its high-water mark and never gives it back, so a long build
  # converges on this number and stays there. `vcpu` is a real charge from the
  # first busy thread. NOTES item 12.
  sizes = {
    vcpu = 4;
    mem = 8192; # / is tmpfs, so guest RAM also pays for /tmp and rootfs
    volume = 32768; # sparse; holds the checkout, target/, caches
  };

  # Static build configuration for the guest: path relative to the volume's
  # mount point (same convention as `caches`), file content. Rendered into the
  # guest's closure and linked onto the volume by its seed — none of it is
  # secret, so none of it needs a transport.
  #
  # The whole point is what it is *not*: a copy of a human's
  # ~/.cargo/config.toml. That file describes a 32-thread machine with a large
  # page cache, and its `jobs` inside a 4-vCPU guest is a worse default than no
  # file at all. So the machine-shaped value is derived from `sizes` above — the
  # same reservation the VM is built from, which is why the two cannot disagree
  # — and the policy-shaped ones are stated here, where this target's policy
  # already lives. A target that does not build with cargo writes a different
  # value here; nothing generic knows what a toolchain is.
  #
  # This is cargo's lowest-precedence config, so a `.cargo/config.toml` in the
  # checkout still wins: a default the target repo can override, not an
  # imposition on it.
  guestConfig = {
    "${caches.CARGO_HOME}/config.toml" = ''
      # Rendered from target.nix by the capsule. Edits here go on the next boot.
      [build]
      # The capsule's vCPUs, not the host's threads.
      jobs = ${toString sizes.vcpu}

      [profile.dev]
      # Disk, and disk is the binding constraint (docs/probes.md): full
      # debuginfo and an incremental cache are the two largest terms in
      # `target/`, nothing reclaims volume blocks, and the incremental cache
      # does not survive a fresh capsule anyway. `debug = "line-tables-only"` is
      # the knob if backtraces stop naming lines.
      debug = 0
      incremental = false
    '';
  };
}
