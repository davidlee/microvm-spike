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
# `rec`, for one reason: the guest paths below are paths both sides must agree
# on, and deriving them keeps the target — and the volume's mount point — named
# once each.
#
# This is the *second* target, and the whole point of it is that only this file,
# one allowlist and one literal in flake.nix changed — see NOTES item 23 for what
# it cost and docs/contract-target.md for the surface it exercises. doctrine's
# version of this file is on `main`.
rec {
  # The guest's checkout directory name, and the motd.
  name = "panopticon";

  # Read by `capsule-provision` only, and always as the human — it is the source
  # of the push that provisions a capsule. Nothing serves it and nothing else
  # reads it.
  path = "/home/david/dev/panopticon";

  # The guest's checkout, absolute. Both sides need it: `vm/capsule.nix` creates
  # it on the volume, and the host's git channel pushes to it and fetches from
  # it.
  guestPath = "${volumePath}/${name}";

  # Where the capsule's volume is mounted in the guest. What the guest arranges
  # *under* it is the guest's own business; the mount point itself is shared,
  # because `caches`, `cachePaths` and `guestConfig` are all declared relative to
  # it and all three are read host-side as well as guest-side. Named here so
  # neither side spells it twice — `vm/capsule.nix` takes it from here too.
  volumePath = "/work";

  # Package in the target's own flake carrying its devshell tool set, so the
  # guest and that devshell cannot drift. `null` for a target with no flake:
  # the guest then gets `extraTools` and nothing else, and loses that property.
  #
  # panopticon had to grow this package to be a target at all, and that is the
  # contract's floor working rather than a wart: its `packages.default` is the
  # *application*, which carries no pytest, no ruff and no just, and `extraTools`
  # cannot stand in — that field is bare nixpkgs attr names, and this target's
  # tool set contains a `python3.withPackages (…)`, which has no name. So the
  # target exports the same `projectPkgs` its jails and its devshell already
  # share (NOTES item 23).
  toolsPackage = "dev-tools";

  # Tools the target's list assumes the host already has, so it does not carry
  # them. nixpkgs attr names, resolved against the guest's pkgs.
  #
  # Empty, and that is the first absent path this second target exercises:
  # panopticon's list is self-contained because it was built for jails that bind
  # no host toolchain. A wheel-only `uv` resolve needs no compiler.
  extraTools = [];

  # Proxy hostname allowlist, relative to CAPSULE_ROOT so a moved checkout still
  # finds it, and a plain file rather than a store path so editing it needs no
  # rebuild. One file per target: this one is named for its target, since half of
  # any such list is that target's dependency hosts and doctrine's says
  # crates.io.
  allowlist = "perimeter/egress-allow-panopticon.txt";

  # Toolchain-shaped rather than repo-shaped, which is why they are here: caches
  # that must live on the volume instead of in guest RAM. Env var -> directory
  # under /work; the guest's seed service creates and chowns exactly these.
  #
  # One entry where doctrine has two, and a different variable — which is the
  # field being a value rather than a list of toolchains this repo knows about.
  # `.venv` is not in here: `uv` puts it in the checkout, which is already on the
  # volume.
  caches = {
    UV_CACHE_DIR = ".uv-cache";
  };

  # The same directories, absolute — what anything that is not setting an env
  # var actually wants. The guest's seed creates and chowns exactly these, and
  # `capsule-baseline` sizes them before and after a run, which is what makes a
  # recorded build checkably cold or warm. Derived, so a cache is declared once.
  cachePaths = map (dir: "${volumePath}/${dir}") (builtins.attrValues caches);

  # The branch the guest works on, and the branch `capsule-provision` lands a
  # base commit onto — which is *any* ref in the target repo, so a capsule's
  # base is an argument rather than a value in the guest's closure. The guest's
  # HEAD must name this branch or a provision silently does not check out; the
  # seed sets it, and provision verifies it.
  #
  # `main`, not doctrine's `edge` — and this is the one field a target switch
  # cannot leave to a run-time argument: it is baked into the host module's copy
  # of `capsule-provision`, so changing it costs a host rebuild where `path` only
  # costs `CAPSULE_REPO` (NOTES item 23).
  defaultBranch = "main";

  # Largest packfile one `capsule-collect` may write, as `ulimit -f`. A backstop
  # on the file, not a bound on the transfer — many small objects or a delta bomb
  # go straight past it (NOTES item 18). 64 MiB against a 2 MiB repo leaves the
  # same order of room doctrine's 512 MiB leaves its 32 MiB.
  collectMaxPackBytes = 67108864;

  # Shown in the motd: the target's own entrypoints, so the agent need not guess.
  commands = "just check / just test / just lint";

  # What takes a provisioned capsule to a working one: build and test to green,
  # filling `caches` on the way. `capsule-baseline` runs this in the checkout and
  # records green-plus-duration on the volume — on a fresh volume that is the
  # **cold build**, the largest term in time-to-interactive and the one figure
  # the freshness probe cannot take (docs/probes.md).
  #
  # A command line, run by the guest's own login shell, and that is the whole
  # generic capability: nothing outside this file knows what `just` is, or that
  # this one resolves its own dependency set from pypi on the way. `null` for a
  # target with nothing to build, which drops the program rather than shipping
  # one that cannot work.
  #
  # `just check` is `ruff check` then `pytest`, both under `uv run --extra dev`,
  # so unlike doctrine's this baseline is *network-bound before it is CPU-bound*:
  # it resolves the dev extra through the allowlist proxy on a cold volume. That
  # makes it a live test of the allowlist beside it, which doctrine's cargo build
  # also is — the difference is which hosts.
  baseline = "just check";

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
  #
  # Half doctrine's memory and a quarter of its volume, because a pytest suite is
  # not a cargo build: there is no `target/`, the checkout is 2 MiB, and the two
  # things that grow are `.venv` and the uv cache. Honest rather than copied — a
  # second target taking doctrine's numbers would be the same failure as copying
  # a human's `~/.cargo/config.toml`.
  sizes = {
    vcpu = 4;
    mem = 4096; # / is tmpfs, so guest RAM also pays for /tmp and rootfs
    volume = 8192; # sparse; holds the checkout, .venv, the uv cache
  };

  # Static build configuration for the guest: path relative to the volume's
  # mount point (same convention as `caches`), file content. Rendered into the
  # guest's closure and linked onto the volume by its seed — none of it is
  # secret, so none of it needs a transport.
  #
  # doctrine's entry is derived from `sizes`; this one is pure policy, which is
  # the other half of the same field. `uv` defaults to *downloading* an
  # interpreter, and a capsule that fetches 30 MiB of python-build-standalone
  # through an allowlist proxy — when its tool set already puts 3.12 on PATH —
  # is paying for a machine it is not. `never` is also why this target's
  # allowlist needs no github release host for the build.
  #
  # Under `$HOME`, which is `<volumePath>/home`: uv reads a user-level `uv.toml`,
  # and the seed makes the parent directory for any `guestConfig` path. Lower
  # precedence than a `uv.toml` in the checkout, so it is a default the target
  # repo can still override — the same property doctrine's cargo config has.
  #
  # `concurrent-downloads` is the knob if a resolve ever hangs rather than fails:
  # uv defaults to 50 and a proxy turns any client's parallelism into a shared
  # resource, which is NOTES item 9 and cost a session once already.
  guestConfig = {
    "home/.config/uv/uv.toml" = ''
      # Rendered from target.nix by the capsule. Edits here go on the next boot.

      # The tool set puts python3.12 on PATH; there is no reason to fetch one,
      # and no allowlist entry to fetch it through.
      python-preference = "only-system"
      python-downloads = "never"
    '';
  };
}
