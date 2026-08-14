# Everything the human runs *at* a capsule, built once for both paths — plus the
# one script a capsule runs *about itself*, which is here for the same reason:
# built once, so neither path can be built without it.
#
# There are two of them and there must not be two implementations: the devshell
# builds these to reach the guest straight over the tap, and `host/services.nix`
# builds the same four to reach it through the capsule's relay socket, because
# under netns the guest is not routable from the root namespace at all. The only
# difference between the two is `transport`, which is why that is the argument.
#
# `transport` is a shell fragment (`host/guest-ssh.nix`), not a value, and one
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
  transport,
}: let
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

  gitChannel = import ./git-channel.nix {
    inherit pkgs target workBranch guestRepo guestHost transport;
    snapshot = stateSnapshot;
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
        inherit pkgs guestHost transport;
        command = target.baseline;
        workdir = target.guestPath;
        recordDir = baselineRecord;
        measure = [target.guestPath] ++ target.cachePaths;
      };
}
