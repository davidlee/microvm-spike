# Everything the human runs *at* a capsule, built once for both paths — plus the
# one script a capsule runs *about itself*, which is here for the same reason:
# built once, so neither path can be built without it.
#
# There are **three** call sites and there must not be three implementations: the
# devshell builds these to reach the guest straight over the tap,
# `host/services.nix` builds the same set to reach it through the capsule's relay
# socket because under netns the guest is not routable from the root namespace at
# all, and `probe-freshness` builds its own to exercise the real programs on the
# real seam. The only difference between them is `access`, which is why that is
# the argument — and it is *one* argument holding two fields rather than two
# arguments, because a second argument is a second thing three call sites can
# each forget, and one of them did (NOTES item 34).
#
# `access.transport` is a shell fragment (`host/guest-ssh.nix`), not a value, and one
# store path serves every capsule because of it: spliced at the top of each
# program, it resolves which capsule this invocation means, strips that argument
# out of `"$@"`, and sets `ssh_cmd` to the argv that reaches it. Baking a
# transport instead — which is what an argv-valued `sshArgs` did — gives one
# program per capsule, since the only thing that differs between two capsules is
# a socket path.
#
# Everything else here is derivation, not decision: who the host talks to
# (`agent@`, the unprivileged guest user), where the checkout is, and which
# payloads leave this host. All of it comes from `net.nix`, `target.nix` and
# `setup.nix` — nothing target-shaped is spelled here.
{
  pkgs,
  lib,
  net,
  target,
  # The guest's branch, a constant threaded from `flake.nix` rather than a
  # target's field: only the git channel reads it, but both this file's callers
  # have to hand it the same one the guest was built with.
  workBranch,
  # Which capsule, and how to reach it — `host/guest-ssh.nix`'s `direct` or
  # `viaSocket`, as **one value with two fields**:
  #
  #   - `transport` resolves the name *and* sets `ssh_cmd`, for everything that
  #     talks to a guest;
  #   - `selectCapsule` resolves the name alone, for `capsule-adopt`, which must
  #     know which capsule it is for and must not reach one — it reads a
  #     host-owned quarantine, and a transport refuses when the guest is down,
  #     which is the state a finished capsule's exhibit is adopted in (NOTES item
  #     34).
  #
  # One argument rather than two because there are three call sites and a second
  # argument is a second thing each of them can omit.
  access,
}: let
  inherit (access) transport selectCapsule;

  # Where a capsule's collected exhibit lives, and what its refs are called. Two
  # programs over one convention: `capsule-collect` writes it, `capsule-adopt`
  # reads it.
  quarantine = import ./quarantine.nix;

  # Who the host talks to when it talks to a capsule. Named once: the git
  # channel needs it inside a URL, the other two as an ssh destination.
  guestHost = "agent@${net.guest}";

  # Where the guest's checkout is, as a URL.
  guestRepo = "ssh://${guestHost}${target.guestPath}";

  # Where `capsule-baseline` writes its record. Beside the checkout, never inside
  # it: a record in the worktree is a dirty worktree, and that is what the next
  # `capsule-provision` refuses on.
  #
  # Exported, because `capsule status` reads the same record from the other side
  # (host/observe.nix) and two spellings of one path is how the two ends drift.
  # Well-defined even when `baseline` below is `null` — a target with no baseline
  # has no records, which is what a status reporting `none` forever means.
  baselineRecord = "${target.volumePath}/baseline";

  # The guest half of a collect's sideband — a store path, like `observe` below
  # and for the same reasons, pushed on stdin at each collect rather than baked
  # into a guest that would have to be restarted to carry it (NOTES item 32).
  # `null` when the target declares no out-of-band state, which is what makes
  # `capsule-collect` degrade to the code-only program it used to be rather than
  # grow a flag nobody sets.
  stateSnapshot =
    if (target.statePaths or []) == []
    then null
    else
      import ./state-snapshot.nix {
        inherit pkgs lib;
        workdir = target.guestPath;
        inherit (target) statePaths stateMaxBytes;
      };

  # How anything host-authored runs *inside* a live capsule: the build-time lint
  # both guest runners get, and the login-shell rule a second hand-written
  # invocation would get wrong (host/guest-exec.nix, NOTES item 24).
  guestExec = import ./guest-exec.nix {inherit pkgs;};

  # The third step of a provision — regenerate what the push cannot carry, in the
  # checkout the push just made (host/refresh.nix, NOTES item 33). `null` when
  # the target derives nothing from its checkout, which is what keeps the
  # two-step provision available rather than adding a flag nobody sets.
  #
  # The other end of `stateSnapshot` above, and the two are one decision: what a
  # collect must not carry out is what a provision regenerates in.
  refreshHook =
    if (target.refresh or null) == null
    then null
    else
      import ./refresh.nix {
        inherit pkgs lib guestExec guestHost transport;
        command = target.refresh;
        workdir = target.guestPath;
      };

  gitChannel = import ./git-channel.nix {
    inherit pkgs target workBranch guestRepo guestHost transport quarantine;
    snapshot = stateSnapshot;
    # The command line, not the module: the git channel runs a refresh and has no
    # business knowing what one is built out of.
    refresh =
      if refreshHook == null
      then null
      else refreshHook.invoke;
  };
in {
  inherit guestHost guestRepo baselineRecord;

  # The one thing here with no transport, built here anyway: the guest-side half
  # of a status is a *store path* the front end pushes over whichever door it
  # already has (host/observe.nix, host/cli.nix). It belongs beside the three
  # guest paths it reads — two of them are already named above, and
  # `baselineRecord` is exported for this reader specifically. The alternative
  # was building it at each of `capsule-cli`'s two call sites, which is how the
  # module path came to be missing an argument the devshell path had.
  observe = import ./observe.nix {
    inherit pkgs lib;
    workdir = target.guestPath;
    recordDir = baselineRecord;
    inherit (target) volumePath;
  };

  inherit (gitChannel) provision collect;

  # The second step out of quarantine, and the one with a security control in it:
  # the state half is a guest-authored tree, so what lands on a disk from it is
  # validated before anything is written (host/adopt.nix, NOTES item 34). `null`
  # on the same condition as the snapshot that produces the thing it reads — a
  # target with no `statePaths` never has a state ref, so an extractor for it is
  # a program that cannot work.
  adopt =
    if stateSnapshot == null
    then null
    else
      import ./adopt.nix {
        inherit pkgs selectCapsule quarantine;
      };

  # The same refresh `capsule-provision` runs, on its own: a human who has just
  # done a hand `git checkout` in the guest wants it and no push, and a provision
  # that failed *at* the refresh needs a way to retry only that half. `null` on
  # the same condition as the hook itself.
  refresh =
    if refreshHook == null
    then null
    else refreshHook.program;

  # The non-git half of provisioning: credentials, secrets and anything else a
  # fresh capsule needs that no repository carries. The list is ./setup.nix,
  # which is handed the volume's mount point — a payload's destination is in the
  # guest, and `/work` is `target.nix`'s to say. Its `tools` are nixpkgs attr
  # names, resolved here so that a declaration file stays data.
  inject = import ./inject.nix {
    inherit pkgs guestHost transport;
    injections =
      map (i: i // {tools = map (name: pkgs.${name}) i.tools;})
      (import ../setup.nix {inherit (target) volumePath;});
  };

  # The last step of making a fresh capsule usable, and the only one that
  # produces a figure: the target's own build-and-test, host-initiated, its
  # record written on the volume rather than to a terminal. `null` when the
  # target declares no baseline — a better absent path than a program that
  # cannot work.
  baseline =
    if target.baseline == null
    then null
    else
      import ./baseline.nix {
        inherit pkgs guestExec guestHost transport;
        command = target.baseline;
        workdir = target.guestPath;
        recordDir = baselineRecord;
        measure = [target.guestPath] ++ target.cachePaths;
      };
}
