# Everything the human runs *at* a capsule, built once for both paths.
#
# There are two of them and there must not be two implementations: the devshell
# builds these to reach the guest straight over the tap, and `host/services.nix`
# builds the same four to reach it through the capsule's relay socket, because
# under netns the guest is not routable from the root namespace at all. The only
# difference between the two is `sshArgs`, which is why that is the argument.
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
  sshArgs,
}: let
  # Who the host talks to when it talks to a capsule. Named once: the git
  # channel needs it inside a URL, the other two as an ssh destination.
  guestHost = "agent@${net.guest}";

  # Where the guest's checkout is, as a URL.
  guestRepo = "ssh://${guestHost}${target.guestPath}";

  gitChannel = import ./git-channel.nix {
    inherit pkgs target guestRepo;
    # git parses GIT_SSH_COMMAND shell-style, so the argv has to survive being
    # re-split — a ProxyCommand has spaces in it and only quoting keeps them.
    sshCommand = lib.escapeShellArgs sshArgs;
  };
in {
  inherit guestHost guestRepo;

  inherit (gitChannel) provision collect;

  # The non-git half of provisioning: credentials and anything else a fresh
  # capsule needs that no repository carries. The list is ./setup.nix, whose
  # `tools` are nixpkgs attr names — resolved here so that a declaration file
  # stays data.
  inject = import ./inject.nix {
    inherit pkgs guestHost sshArgs;
    injections =
      map (i: i // {tools = map (name: pkgs.${name}) i.tools;})
      (import ../setup.nix);
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
        inherit pkgs guestHost sshArgs;
        command = target.baseline;
        workdir = target.guestPath;
        # Beside the checkout, never inside it: a record written into the
        # worktree is a dirty worktree, and a dirty worktree is what the next
        # `capsule-provision` refuses on.
        recordDir = "${target.volumePath}/baseline";
        measure = [target.guestPath] ++ target.cachePaths;
      };
}
