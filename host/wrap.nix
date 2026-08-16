# What the module path hands a host-side program before it starts, and the one
# rule it follows: **the module supplies defaults, it imposes nothing.**
#
# Its own file since `ISS-004`, for the reason `host/guard.nix`'s `tools` and
# `host/cli.nix`'s `moduleState` are: the thing tying this to a host is an
# argument, so `wrapCases` can build the *shipped* builder against a fixture
# instead of re-rendering five export lines that would then agree with
# themselves while disagreeing with `host/services.nix`.
#
# **Why it is wrapped at all.** These programs' own defaults are relative to
# `CAPSULE_ROOT`, which is right for the foreground path and wrong for a program
# on `$PATH` — run from anywhere, `capsule-collect` would quarantine into
# `$PWD/.vm/host` instead of this host's state directory. The devshell's copies
# come first on PATH inside the repo, so that path is unaffected and each keeps
# its own state. (The same trap `capsule-sync` fell into; NOTES item 11.)
#
# **Why a default and not an assignment.** A bare `export` here is the last line
# before the program starts, so it defeats *any* caller that set the variable
# deliberately — including the caller this module installs. `host/cli.nix`'s
# `slotProfileName` resolves which document a verb on a slot reads and exports
# `CAPSULE_PROFILE_DIR` for it; until `ISS-004` the wrapper overwrote that with
# the host's directory, which made the profile pin inert for `collect`,
# `provision`, `brief` and `adopt` while `baseline` and `refresh` — unwrapped,
# and so inheriting the export — read the pin. Two verbs on one slot disagreed
# about which document that slot runs, and nothing said so.
#
# The programs one layer down are all written for the override already —
# `profileDir()` is `''${CAPSULE_PROFILE_DIR:-<baked>}` (host/profile.nix),
# `capsule-provision`'s `src` is `''${CAPSULE_REPO:-$profile_path}`
# (host/git-channel.nix), `quarantineOf` reads `''${CAPSULE_STATE:-…}`
# (host/quarantine.nix) — so this file taking a value away was the only thing
# stopping a caller from being heard.
#
# **All five, and no exception table.** The alternative considered and rejected
# was to make `CAPSULE_PROFILE_DIR` and `CAPSULE_REPO` defaults and leave the
# other three imposed. It needs a defensible reason per variable and a
# maintained exception, and the two hazards it was for dissolve on inspection:
# `CAPSULE_STATE` already moves the quarantine and not the record on the
# devshell path, deliberately (`mem.fact.oubliette.capsule-state-moves-the-quarantine-not-the-record`),
# so one rule makes that one behaviour instead of a path-dependent one; and an
# overridden `CAPSULE_ALLOWLIST_DIR` makes a policy verb write a symlink the
# proxy does not read, which fails *closed* — the perimeter is unchanged, since
# the proxy unit takes its allowlist from `cfg.allowlistDir` at build
# (host/services.nix) and no environment reaches it. Both are reached only by a
# deliberate export, and both are pinned as cases.
{
  pkgs,
  lib,
  # Where this host keeps each of the five, from the module's own options. Not
  # five positional arguments: they are all directories and a caller that
  # ordered two of them wrong would build a wrapper that ran.
  paths,
}: let
  # The variable a program reads, and what this host defaults it to. One
  # attribute set rather than five lines of text, so "which variables does the
  # module path supply" has a single answer that `wrapCases` reads from the
  # same place this builds from.
  defaults = {
    CAPSULE_STATE = paths.stateDir;
    CAPSULE_REPO = paths.repo;
    CAPSULE_POLICY_DIR = paths.policyDir;
    CAPSULE_ALLOWLIST_DIR = paths.allowlistDir;
    CAPSULE_PROFILE_DIR = paths.profileDir;
  };

  # `export V=''${V:-<default>}` and not `export V="''${V:-<default>}"`: the
  # right-hand side of an assignment is not word-split, so `escapeShellArg` is
  # the whole of the quoting and a path with a space survives it. One shell, so
  # one `%q` — this text is built by nix and read by the wrapper's shell, and
  # the value never reaches a second parse (CLAUDE.md's escaping rule, at the
  # count of one).
  exports =
    lib.concatStringsSep "\n"
    (lib.mapAttrsToList
      (v: d: "export ${v}=\${${v}:-${lib.escapeShellArg d}}")
      defaults);
in {
  inherit defaults;

  wrap = name: program:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        ${exports}
        exec ${lib.getExe program} "$@"
      '';
    };
}
