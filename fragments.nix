# The fragment vocabulary — what a guest may be composed out of, and the only
# place a tool that belongs to no project is allowed to be named.
#
# [docs/contract-flavour.md](./docs/contract-flavour.md) is the design and this
# is its build-time half: a flavour is `compose(floor, extras)`, the **floor** is
# the project's (`target.nix`'s `toolsPackage` and `extraTools`, threaded through
# `vm/capsule.nix` as it always was) and the **extras** are the host operator's,
# drawn from a vocabulary the host declares. This file is that vocabulary;
# `extras` in `flake.nix` is the selection. Neither owner can quietly become the
# other, which is the whole reason the two lists are separate files.
#
# Three rules it exists to keep, all of them the contract's:
#
#   - **Convenience is declared, never inherited.** A fragment that copied this
#     human's dotfiles would describe a machine the capsule is not, and would be
#     a channel for host state into a confinement whose claim is that no host
#     directory gets in. Everything below is spelled out here or it does not
#     exist in the guest.
#   - **A fragment source is a flake input of this repo**, pinned in a lock this
#     host owns, so adding a tool source is a deliberate act with a rebuild
#     behind it (NOTES item 26).
#   - **A tool that is target-shaped does not come here.** The smell is the same
#     one CLAUDE.md names: a toolchain's name outside `target.nix`. `rg` and
#     `tmux` are nobody's project, which is exactly why `target.nix` was the
#     wrong home for them.
#
# Two things deliberately absent, so neither reads as an oversight:
#
#   - **Capability fragments.** The contract's fragment is packages *plus*
#     guest capability, and `programs.nix-ld` is the standing example — but that
#     one is already decided the other way: every non-nix-native toolchain needs
#     it identically, so it belongs in what the capsule *supplies*, beside
#     `TMPDIR` and the caches (NOTES item 23). Nothing else has asked, so the
#     shape here is `{packages = …;}` — an attrset rather than a bare list,
#     which is where a `guestModule` goes the day something wants one.
#   - **Per-slot selection.** `extras` is one list for the fleet, so every slot
#     arrives at one composition and the one-image lever is untouched (NOTES
#     item 21). Selection per assignment — and with it the record's `image`, the
#     gcroot that retains it, and the refusal to change a composition under a
#     dirty volume — is Plan D D7. This file is what that would select *from*.
{
  pkgs,
  inputs,
}: let
  inherit (pkgs.stdenv.hostPlatform) system;
  inherit (pkgs) lib;

  # The agent CLIs, from llm-agents rather than from nixpkgs. Same derivations
  # `~/flakes/pub`'s `unjailed` exports — that attrset is `inherit
  # (llm-agents.packages.${system}) claude-code pi` and nothing else — so this
  # is one input where going through pub would have been five, for the same
  # store paths. It supersedes `pkgs.claude-code` and the `allowUnfreePredicate`
  # that named it: the derivation is created in llm-agents' own eval, so this
  # repo's nixpkgs config no longer gates it (NOTES item 3).
  #
  # The jailed wrappers stay out, as they always have: they bind *host* paths
  # this guest does not have, and the capsule's confinement is the VM.
  llm = inputs.llm-agents.packages.${system};

  # Name -> fragment. Small on purpose: a fragment used by one slot is its own
  # 3.0 GiB image, so broad-and-few is arithmetic rather than taste
  # (docs/contract-flavour.md, docs/probes.md).
  vocabulary = {
    # What makes the capsule a place an agent can work at all. `bubblewrap`
    # because an agent that jails its own subprocesses needs one in the guest —
    # the guest's, over guest paths, which is a different thing from the host
    # wrappers above.
    agents = {
      packages =
        [llm.claude-code llm.pi]
        ++ (with pkgs; [ripgrep fd tree jq bubblewrap]);
    };

    # What makes it a place a human can look around in. `helix` rather than
    # neovim for the reason the convenience rule forces: a guest has no dotfiles
    # and may never be given this host's, so an editor that is useful unconfigured
    # is the one that survives the rule.
    dev-facilities = {
      packages = with pkgs; [helix tmux btop nushell];
    };
  };

  known = lib.concatStringsSep ", " (builtins.attrNames vocabulary);
in {
  inherit vocabulary;

  # `compose(floor, extras)`. Ordered for legibility only — nothing depends on
  # where in the list a fragment sits — and collisions are left to nix, which
  # fails the build rather than silently shadowing a toolchain. That failure is
  # the wanted behaviour, and `lib.hiPrio` at the call site is its deliberate
  # override.
  #
  # An unknown name is refused rather than resolving to nothing, because a
  # fragment that silently does not exist is a guest quietly missing its tools.
  compose = {
    floor,
    extras,
  }:
    floor
    ++ lib.concatMap (
      name:
        (
          vocabulary.${name}
          or (throw "fragments.nix: no fragment named '${name}' — the vocabulary is ${known}")
        )
        .packages
    )
    extras;
}
