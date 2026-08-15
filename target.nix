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
rec {
  # The guest's checkout directory name, and the motd.
  name = "doctrine";

  # Read by `capsule-provision` only, and always as the human — it is the source
  # of the push that provisions a capsule. Nothing serves it and nothing else
  # reads it.
  path = "/home/david/dev/doctrine";

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
  toolsPackage = "dev-tools";

  # Tools the target's list assumes the host already has, so it does not carry
  # them. nixpkgs attr names, resolved against the guest's pkgs.
  extraTools = ["pkg-config" "openssl"];

  # No `allowlist` field, and nothing replaces it. What a capsule may talk to is
  # a **control**, and a control chosen by whoever names the project is a control
  # the naming authority holds (NOTES item 25) — invisible while one target was a
  # build-time literal, and an authority hole the moment assigning a project is a
  # run-time verb. It is a policy now, declared in `policies.nix`, selected per
  # slot, and the same is true of `collectMaxPackBytes` below (NOTES item 36).

  # Toolchain-shaped rather than repo-shaped, which is why they are here: caches
  # that must live on the volume instead of in guest RAM. Env var -> directory
  # under /work; the guest's seed service creates and chowns exactly these.
  caches = {
    CARGO_HOME = ".cargo";
    BUN_INSTALL_CACHE_DIR = ".bun-cache";
  };

  # The same directories, absolute — what anything that is not setting an env
  # var actually wants. The guest's seed creates and chowns exactly these, and
  # `capsule-baseline` sizes them before and after a run, which is what makes a
  # recorded build checkably cold or warm. Derived, so a cache is declared once.
  cachePaths = map (dir: "${volumePath}/${dir}") (builtins.attrValues caches);

  # No branch field, deliberately, and nothing replaces it. The guest's branch is
  # the constant `work` (`workBranch` in flake.nix): a name that identifies the
  # work is not project state, which is what two slices of one project at once
  # refutes any version of this field with. `capsule-provision <ref>` is still a
  # ref in *this* repo and is untouched — the two things called "branch" are
  # separate (docs/contract-target.md, plan-d L13).

  # The out-of-band half of a result: what this target keeps in its worktree
  # that no commit carries. `capsule-collect` snapshots exactly these paths into
  # a sideband commit under `refs/capsule/state/*` and fetches it beside the code
  # refs (NOTES item 32, host/state-snapshot.nix).
  #
  # An explicit allowlist, and emphatically not "the files git ignores": a
  # `.gitignore` covers credentials, machine-local config, agent state and build
  # caches, and `git add -f` over one is a loaded gun pointed wherever that list
  # happens to face. Keep it short, name real directories, and remember that
  # every path here is guest-authored data that a human will later extract.
  #
  # doctrine's storage rule is what makes it need one at all: its runtime tier —
  # phase sheets, dispatch state, research artefacts — is gitignored *on purpose*,
  # and is also what an audit of a finished capsule reads. Untracked-but-not-
  # ignored files come along regardless and are not declared here: "the agent has
  # not committed this yet" is generic, not a target's concept.
  #
  # What is NOT here is the rule worth keeping: **state a consumer regenerates
  # per checkout does not travel** (NOTES item 32). doctrine's boot snapshot
  # (`.doctrine/state/boot.md`) was declared here and is not any more — it is
  # derived from the checkout it sits in, so a copy landing in another tree is
  # stale authority the next tool there reads as its own. It comes back by being
  # regenerated where it is needed, which belongs to provisioning and not to a
  # collect — that is `refresh` below (NOTES item 33), and the two fields are one
  # decision read from its two ends: what is not here is there.
  #
  # A target with no such state omits the field, and `[]` is the same thing: the
  # snapshot is not built at all, so a collect is the code-only program it used
  # to be. That is narrower than it first reads and the difference is worth
  # stating, because it is a live tension rather than a settled call — the
  # untracked-but-not-ignored files and `.capsule/dirty.diff` are *generic* (see
  # above), so there is an argument that they should travel whether or not this
  # field is set. What holds today is the simpler degradation: one field, one
  # switch, and nothing collected out-of-band that a target did not ask for.
  #
  # This is also what gates `capsule-adopt`, the extractor at the far end
  # (host/adopt.nix, NOTES item 34): no `statePaths`, no state ref, so no program
  # to read one.
  #
  # **A template list, and `{unit}` is the one hole a path may hold** (NOTES item
  # 32). An exhibit has a scope — *the out-of-band state of the work the capsule
  # was assigned, and none that is not* — and a path list cannot state one,
  # because the unit of work is run-time state and this file is a build-time
  # literal. So the policy declares where the unit goes and the assignment says
  # which unit; a template with a hole and no unit is a refusal, never a
  # fall-through to the unscoped list. Unscoped is what these two paths were, and
  # it cost 1886 entries where 41 named the work
  # (docs/probes.md#the-first-exhibit-adopted--and-what-it-costs-to-over-collect).
  #
  # The hole is filled with an opaque token the guest substitutes and never
  # parses. Nothing outside this file knows that doctrine's unit of work is a
  # slice, or that a slice is a number — the capability is *a policy path
  # allowlist may be parameterised by one identifier the assignment carries*, and
  # a second target is a different template and a different token rather than
  # different code.
  #
  # A target whose out-of-band state is not per-unit writes no hole, and every
  # program behaves exactly as it did before this existed.
  #
  # What is *not* here: `.doctrine/dispatch` and `.doctrine/state/dispatch`, both
  # of which were declared and are gone. Not narrowed — **historical**: dispatch
  # is the mechanism capsules replaced, so what those paths hold is bookkeeping
  # from before this repo existed, and collecting it as a capsule's result would
  # be shipping an older answer to the question the exhibit settles.
  statePaths = [
    ".doctrine/state/slice/{unit}" # per-slice runtime: phase sheets, progress
    ".doctrine/slice/{unit}" # research/ (ignored) and uncommitted authored edits
  ];

  # Ceiling on one snapshot, in bytes. Not the same backstop as
  # `collectMaxPackBytes` and not in the same place: this one is checked in the
  # guest *before* the commit is made, because the fetch is atomic and a
  # too-large state half must skip rather than take the code refs down with it.
  #
  # 64 MiB against a target whole history of 32 MiB. The number is a smell
  # detector rather than a budget: this repo's own `.doctrine/state` on the
  # human's host has grown a 1.7 GiB scratch directory under it, and a path list
  # that catches one of those should fail loudly on the first collect rather than
  # quietly move a gigabyte per run.
  stateMaxBytes = 67108864;

  # Largest packfile one `capsule-collect` may write, as `ulimit -f`. A backstop
  # on the file, not a bound on the transfer — many small objects or a delta bomb
  # go straight past it (NOTES item 18). 512 MiB against a 32 MiB repo leaves
  # room for a working history.
  collectMaxPackBytes = 536870912;

  # Shown in the motd: the target's own entrypoints, so the agent need not guess.
  commands = "just test / just web-build";

  # What takes a provisioned capsule to a working one: build and test to green,
  # filling `caches` on the way. `capsule-baseline` runs this in the checkout and
  # records green-plus-duration on the volume — on a fresh volume that is the
  # **cold build**, the largest term in time-to-interactive and the one figure
  # the freshness probe cannot take (docs/probes.md).
  #
  # A command line, run by the guest's own login shell, and that is the whole
  # generic capability: nothing outside this file knows what `just` is, or that
  # anything here is built with cargo. `null` for a target with nothing to
  # build, which drops the program rather than shipping one that cannot work.
  baseline = "just web-build test";

  # What a *fresh checkout* needs before anything reads it: the command that
  # regenerates this target's derived state, run by `capsule-provision` once the
  # push has landed and by `capsule-refresh` on demand (NOTES item 33).
  #
  # The other end of `statePaths` above. Derived state is precisely what must not
  # travel between capsules — a copy is stale authority in the tree it lands in —
  # so it does not come back in a collect; it is regenerated here, from the code
  # the provision just delivered.
  #
  # A command line, like `baseline`, and the same generic capability with a
  # different lifecycle: nothing outside this file knows what `doctrine boot` is
  # or that a governance snapshot exists. `null` for a target that derives
  # nothing from its checkout, which drops the program rather than shipping one
  # with nothing to run.
  #
  # It may write tracked files, and `doctrine boot` does — the boot snapshot
  # itself is runtime tier, but a boot regenerates more than the snapshot. That
  # is handled rather than forbidden: `capsule-refresh` commits the tracked half
  # of what it wrote, because the alternative is a dirty worktree that the *next*
  # provision refuses on and that every subsequent collect records as noise in
  # its `dirty.diff`. The commit is safe because a provision can only land on a
  # clean tree, so there is nothing of anyone else's for it to sweep up — see
  # host/refresh.nix, where the precondition is enforced.
  #
  # The cost, stated once: a capsule whose refresh commits has a `work` branch
  # ahead of what the host pushed, so re-provisioning it wants `--force`. That is
  # the same override re-provisioning over an agent's commits already wants, and
  # `capsule-provision`'s refusal already names it.
  refresh = "doctrine boot";

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
    # 6144 because of the fleet, not because of a measurement: a ceiling is free
    # per capsule and a reservation per fleet, since nothing hands memory back
    # until a stop (docs/plan-d-fleet.md §0). Five cold builds peaked 6801-7845
    # MiB per *unit* at the old 8192, so it reads as a real cut. **Measured, and
    # it is not one**: a built slot holds ~6.1 GiB of `anon` at either ceiling,
    # because the VMM holds every page the build ever touched rather than a share
    # of what the guest was offered. Free — no wall clock, no guest pressure — and
    # not a saving (docs/probes.md#the-first-cold-build-at-a-6144-ceiling).
    mem = 6144; # / is tmpfs, so guest RAM also pays for /tmp and rootfs
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
