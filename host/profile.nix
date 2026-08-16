# The target's run-time half, as a document — NOTES item 51 step 3.
#
# `host/programs.nix` builds every host-side program with `target.nix`'s values
# **interpolated into their text**, so each program's store path is a function of
# which project this host confines. One target makes that invisible; two make it
# four programs per target, which is [item 20](../docs/ledger/020-which-capsule-a-program-means.md)
# one level up. This file is the other end of that fix: the values are rendered
# once, to `<name>.json`, and a program looks one up at run time the way it
# already resolves `--capsule`.
#
# **Step 4 is what reads it.** Every host-side program that used to carry a
# target's values in its text now takes `--profile <name>` and loads one here,
# right where `transport` already resolves `--capsule` — so `select` below is
# `selectCapsule`'s shape (host/guest-ssh.nix) one axis over, and neither of them
# has a default. Which *name* a verb on a slot means is the front end's to
# resolve, never a program's ([item 20](../docs/ledger/020-which-capsule-a-program-means.md)).
#
# **Per target, not per host** (item 51, decision 1). `<dir>/<name>.json`, with
# the slot's assignment record naming which — the shape `policyDir` already pays
# for. One document for the whole host would be less work today and a second
# thing to migrate the moment a host confines two projects.
#
# **A store path, to start** (decision 2). The two properties cannot both hold:
# a store path is checked at build for free and puts two targets a rebuild apart;
# a plain file outside the store reaches a controller that never runs
# `nixos-rebuild`, and is then validated by nobody unless somebody writes the
# validator. `perimeter/egress-allow.txt` is the standing precedent for the
# second and `policies.nix` says why. So: rendered here, read through
# **one** function, and `CAPSULE_PROFILE_DIR` is where that function looks — the
# switch is a change to this file rather than to every caller.
#
# **The document's keys are `target.nix`'s field names.** Identity, on purpose:
# a renamed key is a second vocabulary and a place the two can disagree. `path`
# is therefore the *host* checkout and reads oddly beside `guestPath` — it is
# the field `target.nix` documents and `CAPSULE_REPO` already overrides, and one
# awkward name is cheaper than two spellings of it.
#
# **What is not here.** `toolsPackage`, `extraTools`, `caches`, `guestConfig` and
# `commands` are the *build-time* half: they are inputs to the guest image, and a
# document naming them would describe an image the running slot may not be. The
# sharp edge that leaves is item 51's own — `guestPath` has two producers, this
# document and `vm/capsule.nix`'s seed, and they can disagree the moment the
# document is edited after a slot booted. The assertion below is half an answer:
# it pins the derivation (`guestPath` *is* `volumePath`/`name`) so the two cannot
# drift by construction here. Pinning a *slot* to the profile it was built with
# is `profile_snapshot` in the assignment record (host/record.nix), and step 4
# did **not** fill it: what step 4 pins is the *name*, which the record has
# carried since item 29 and which nothing read until now. Bytes in a record would
# be a second place `profileLoad` looks, which is the one thing decision 2 bought.
{
  pkgs,
  lib,
  target,
}: let
  # Bumped when a field changes meaning or leaves, never when one is added: a
  # reader that refuses an unknown schema and accepts an unknown key is a reader
  # a new field does not have to be switched into.
  schemaVersion = 1;

  document = {
    schema = schemaVersion;
    inherit (target) name path guestPath volumePath cachePaths sizes;
    baseline = target.baseline or null;
    refresh = target.refresh or null;
    statePaths = target.statePaths or [];
    stateMaxBytes = target.stateMaxBytes or 0;
  };

  # ------------------------------------------------------------------ checks
  #
  # Free, because nix is what renders this — which is exactly the property
  # decision 2 says a plain file gives up, and the reason this half of the item
  # starts in the store. Every one of these is a refusal the reader cannot make
  # cheaply or at all: it sees one document and cannot know what the guest image
  # was built from.
  absolute = p: lib.hasPrefix "/" p;

  # A value crossing this boundary is read back a line at a time (`mapfile`) and
  # a column at a time, so a newline or a tab inside one is a value that comes
  # back as two. Forbidden here rather than escaped there: the reader stays
  # simple because the render is strict.
  oneLine = s: !(lib.hasInfix "\n" s || lib.hasInfix "\t" s);

  # The one hole a state path may hold, and it is `host/state-snapshot.nix`'s
  # spelling. Named again rather than imported because that file takes it as a
  # convention of this repo and not as a value of the target's; what is checked
  # here is only that a template holds at most one, since the substitution is a
  # single pass.
  hole = "{unit}";
  holes = p: builtins.length (lib.splitString hole p) - 1;

  strings = [target.name target.path target.guestPath target.volumePath];

  checks =
    [
      {
        ok = target.name != "" && !(lib.hasInfix "/" target.name);
        why = "`name` is a document's filename, so it must be a name and not a path";
      }
      {
        ok = lib.all absolute [target.path target.guestPath target.volumePath];
        why = "`path`, `guestPath` and `volumePath` are absolute paths";
      }
      {
        ok = target.guestPath == "${target.volumePath}/${target.name}";
        why = "`guestPath` must stay derived from `volumePath` and `name` — the guest's seed builds that directory from the same two values, and a document that spells a third answer names a checkout the running image never made (item 51)";
      }
      {
        ok = lib.all (p: absolute p && lib.hasPrefix "${target.volumePath}/" p) document.cachePaths;
        why = "every `cachePaths` entry lives under `volumePath`, because that is the only writable filesystem a capsule has";
      }
      {
        ok = lib.all (p: !(absolute p)) document.statePaths;
        why = "`statePaths` are templates relative to the checkout, never absolute";
      }
      {
        ok = lib.all (p: !(builtins.elem ".." (lib.splitString "/" p))) document.statePaths;
        why = "no `statePaths` template escapes the checkout with `..`";
      }
      {
        ok = lib.all (p: holes p <= 1) document.statePaths;
        why = "a `statePaths` template holds at most one `${hole}`, since the substitution is one pass";
      }
      {
        ok = document.statePaths == [] || document.stateMaxBytes > 0;
        why = "a target that declares `statePaths` declares a `stateMaxBytes` ceiling over them";
      }
      {
        ok = lib.all (n: builtins.isInt document.sizes.${n} && document.sizes.${n} > 0) ["vcpu" "mem" "volume"];
        why = "`sizes.vcpu`, `sizes.mem` and `sizes.volume` are positive integers";
      }
      {
        ok = document.baseline != "" && document.refresh != "";
        why = "`baseline` and `refresh` are a command line or `null` — an empty string is a command that silently succeeds";
      }
    ]
    ++ map (s: {
      ok = oneLine s;
      why = "no value carries a newline or a tab: `${s}` does, and the reader takes them a line at a time";
    }) (strings
      ++ document.cachePaths
      ++ document.statePaths
      ++ lib.optional (document.baseline != null) document.baseline
      ++ lib.optional (document.refresh != null) document.refresh);

  failed = builtins.filter (c: !c.ok) checks;

  checked =
    if failed == []
    then document
    else throw "host/profile.nix: ${(builtins.head failed).why}";

  file = pkgs.writeText "${target.name}.json" (builtins.toJSON checked);

  dir = pkgs.runCommand "capsule-profiles" {nativeBuildInputs = [pkgs.jq];} ''
    mkdir -p "$out"
    # Pretty-printed and key-sorted, so a human can read the thing a program
    # resolves — and parsed by jq at build, which is the render asserting for
    # itself that the reader's parser will accept it.
    jq -S . ${file} > "$out/${target.name}.json"
  '';
in {
  inherit dir document;
  inherit (target) name;

  # The same predicate as `profileNeedsUnit` below, at eval, and it has **one
  # caller**: `probe/two-capsules.sh`'s command line in `flake.nix`. A probe is
  # evidence about the real capsule on this host, so it is allowed to know this
  # host's real target — `probe/netns-boot.sh` is the standing exception for the
  # same reason. No *program* reads this, which is the whole of step 6; it lives
  # here so the probe's spelling of `${hole}` is this file's and not a third one
  # ([item 38](../docs/ledger/038-a-probe-that-became-a-borrower.md) is what a
  # separately-maintained copy of a live value costs).
  needsUnit = lib.any (lib.hasInfix hole) document.statePaths;

  # Callers add these to their own `runtimeInputs`, so the dependency is visible
  # at each call site rather than assumed — `host/record.nix`'s arrangement, for
  # its reason.
  inputs = [pkgs.jq pkgs.coreutils];

  # **A fragment, not a program**, and the same argument `host/record.nix` makes:
  # the programs that will read this are already separate store paths for reasons
  # that have nothing to do with profiles, and a profile *program* would be one
  # more thing to install that each of them would still have to call. One
  # definition of where the documents are, what a name may be, and what a valid
  # one holds.
  #
  # **One function, because the switch to a plain file is a change to where it
  # looks.** `profileLoad <name>` validates once and sets every value; there is
  # no per-field accessor, so no caller can read a field this file has not
  # checked, and a document is opened once per invocation instead of once per
  # value.
  fragment = ''
    # `CAPSULE_PROFILE_DIR` over a baked default: exactly `CAPSULE_REPO`'s shape
    # (host/git-channel.nix), which item 51 names as the precedent this
    # generalises from an override to a lookup. The default is what this host
    # rendered, so the devshell path needs no environment at all and the module
    # path can point at a directory it owns.
    profileDir() { printf '%s' "''${CAPSULE_PROFILE_DIR:-${dir}}"; }

    profileFail() { echo "capsule-profile: $1" >&2; }

    # Sets, on success: profile_name, profile_path, profile_guest_path,
    # profile_volume_path, profile_baseline, profile_refresh,
    # profile_state_max_bytes, profile_vcpu, profile_mem, profile_volume_size,
    # and the arrays profile_cache_paths and profile_state_paths.
    #
    # An absent optional (`baseline`, `refresh`) arrives as the empty string and
    # is not a failure; an absent *required* field is, because the two are
    # different documents and only one of them is broken.
    profileLoad() {
      local n="''${1:-}" pdir file doc f
      pdir=$(profileDir)

      # The name reaches a path, so it is checked before the filesystem is
      # touched — a policy's allowlist is a filename and never a path for the
      # same reason (policies.nix), one directory up.
      case "$n" in
        "")
          profileFail "no profile name. A profile is named, never defaulted (item 28)."
          return 1
          ;;
        */* | . | ..)
          profileFail "profile name '$n' is a path, and a name is not one"
          return 1
          ;;
      esac

      file="$pdir/$n.json"
      if [ ! -f "$file" ]; then
        profileFail "no profile named '$n' in $pdir"
        profileFail "  A profile is <name>.json there, rendered from target.nix"
        profileFail "  (host/profile.nix). CAPSULE_PROFILE_DIR chooses the directory."
        return 1
      fi

      if ! doc=$(jq -e 'if type == "object" then . else null end' "$file" 2>/dev/null); then
        profileFail "$file is not a readable JSON object"
        return 1
      fi

      f=$(printf '%s' "$doc" | jq -r '.schema // "-"')
      if [ "$f" != ${toString schemaVersion} ]; then
        profileFail "$file declares schema $f; this host reads ${toString schemaVersion}"
        return 1
      fi

      # One spelling of the required list, so a field cannot be validated here
      # and read below under another name.
      for f in name path guestPath volumePath sizes.vcpu sizes.mem sizes.volume; do
        if [ "$(printf '%s' "$doc" | jq -r --arg f "$f" 'getpath($f | split(".")) != null')" != true ]; then
          profileFail "$file has no '$f', and every profile names one"
          return 1
        fi
      done

      # One jq call, one line per value, because a tab-separated row loses an
      # empty column: bash treats tab as IFS *whitespace*, so two adjacent
      # separators collapse and every later field shifts up by one. No value
      # holds a newline — host/profile.nix refuses one at render.
      local -a scalars
      mapfile -t scalars < <(printf '%s' "$doc" | jq -r '
        [ .name, .path, .guestPath, .volumePath,
          (.baseline // ""), (.refresh // ""), (.stateMaxBytes // 0),
          .sizes.vcpu, .sizes.mem, .sizes.volume ] | .[] | tostring')
      if [ "''${#scalars[@]}" -ne 10 ]; then
        profileFail "$file holds a value with a newline in it, which cannot be read back"
        return 1
      fi

      profile_name=''${scalars[0]}
      profile_path=''${scalars[1]}
      profile_guest_path=''${scalars[2]}
      profile_volume_path=''${scalars[3]}
      profile_baseline=''${scalars[4]}
      profile_refresh=''${scalars[5]}
      profile_state_max_bytes=''${scalars[6]}
      profile_vcpu=''${scalars[7]}
      profile_mem=''${scalars[8]}
      profile_volume_size=''${scalars[9]}

      mapfile -t profile_cache_paths < <(printf '%s' "$doc" | jq -r '.cachePaths[]? // empty')
      mapfile -t profile_state_paths < <(printf '%s' "$doc" | jq -r '.statePaths[]? // empty')

      # A ceiling that is not a byte count would make the comparison below a
      # `[: integer expression expected` under `set -e` — a bash diagnostic
      # about a document, where a refusal naming the document is wanted.
      case "$profile_state_max_bytes" in
        "" | *[!0-9]*)
          profileFail "$file declares a stateMaxBytes that is not a byte count"
          return 1
          ;;
      esac

      # The same guard over the three sizes, and for one more reason than the
      # ceiling has: `host/cli.nix` builds the assignment record's `class` out of
      # two of them, so a size that is not a number would reach jq as malformed
      # JSON *after* a provision had already landed — a record that cannot be
      # written about work that did.
      for f in "$profile_vcpu" "$profile_mem" "$profile_volume_size"; do
        case "$f" in
          "" | *[!0-9]* | 0)
            profileFail "$file declares a size that is not a positive integer: '$f'"
            return 1
            ;;
        esac
      done

      # The pairing, checked here as well as at render: a ceiling is what keeps
      # an over-budget state half from taking a collect's code refs down with it
      # (host/state-snapshot.nix), so declared paths with no ceiling is a
      # document to refuse rather than a default to invent.
      if [ "''${#profile_state_paths[@]}" -gt 0 ] && [ "$profile_state_max_bytes" -le 0 ]; then
        profileFail "$file declares state paths and no stateMaxBytes over them"
        return 1
      fi
    }

    # Whether this target scopes its out-of-band state by a unit of work — the
    # host-side half of item 32's invariant, and since item 51 step 6 the
    # **only** host-side spelling of it. It was `stateNeedsUnit`, an eval-time
    # predicate over `target.nix`'s list threaded into `host/cli.nix` and
    # `host/git-channel.nix`, which made "does this target need a unit?" a
    # property of which flake the host had built rather than of the document a
    # run was pointed at.
    #
    # The guest half asks the same question of the argv it was handed
    # (host/state-snapshot.nix's `perUnit`) and that is deliberate rather than a
    # duplicate: one end reads a document and the other reads its own arguments,
    # which is the pair that has to agree. What must not exist is a *third*
    # spelling of `${hole}`, so this reads the one above.
    #
    # SC2329, `profileQuote`'s reason exactly: a program that reads a profile and
    # has no scope to decide — `capsule-baseline`, `capsule-refresh` — never calls
    # this. (Being called from `profileShow` does not count: shellcheck reaches
    # for *invoked* functions, and that one is a library's too.)
    # shellcheck disable=SC2329
    profileNeedsUnit() {
      local p
      for p in ''${profile_state_paths[@]+"''${profile_state_paths[@]}"}; do
        case "$p" in
          *"${hole}"*) return 0 ;;
        esac
      done
      return 1
    }

    # What was loaded, one `key<TAB>value` per line, arrays one line per entry.
    # For a human and for the suite beside this file — and it is also what keeps
    # every variable above referenced within the fragment, since a library
    # spliced into a program that uses three of them is otherwise SC2034 seven
    # times over. (A comment whose first word is the linter's name is a
    # *directive* to it, and an unparseable one is a build failure: this
    # paragraph cost one.)
    # SC2329: a library's function is not called by every program that splices
    # the library. This one is read by the suite beside this file and by a human;
    # what it is *for* inside a program is keeping every variable above
    # referenced, which is the SC2034 half of the same problem (item 51 step 3).
    # shellcheck disable=SC2329
    profileShow() {
      printf 'name\t%s\n' "$profile_name"
      printf 'path\t%s\n' "$profile_path"
      printf 'guestPath\t%s\n' "$profile_guest_path"
      printf 'volumePath\t%s\n' "$profile_volume_path"
      printf 'baseline\t%s\n' "$profile_baseline"
      printf 'refresh\t%s\n' "$profile_refresh"
      printf 'stateMaxBytes\t%s\n' "$profile_state_max_bytes"
      printf 'vcpu\t%s\n' "$profile_vcpu"
      printf 'mem\t%s\n' "$profile_mem"
      printf 'volume\t%s\n' "$profile_volume_size"
      # Derived rather than read, and the one line here that is: it is what a
      # program branches on, so it belongs in the picture of what was loaded.
      if profileNeedsUnit; then printf 'needsUnit\tyes\n'; else printf 'needsUnit\tno\n'; fi
      local p
      for p in "''${profile_cache_paths[@]}"; do printf 'cachePath\t%s\n' "$p"; done
      for p in "''${profile_state_paths[@]}"; do printf 'statePath\t%s\n' "$p"; done
    }

    # Which documents this host has rendered, one name per line. Read by the
    # **front end** and by nothing else: resolving what an *unassigned* slot
    # means is an answer about host state, which is a front end's latitude and
    # never a program's (item 20, host/cli.nix). A program that listed this
    # directory to pick a name would be probing for which target it means.
    #
    # SC2329, and the honest reason: exactly one caller, in the shared fragment
    # because it is `profileDir`'s directory and no second definition of that may
    # drift from this one.
    # shellcheck disable=SC2329
    profileNames() {
      local f n
      for f in "$(profileDir)"/*.json; do
        [ -e "$f" ] || continue
        n=''${f##*/}
        printf '%s\n' "''${n%.json}"
      done
    }

    # A filter, one value per line in and one per line out, for values on their
    # way into a guest-pushed script's argument list. The rule is
    # host/guest-exec.nix's and the arithmetic is one lower than it used to be: a
    # value **spliced into a program's text** crossed two shells and was escaped
    # twice, and a value that is an *array element* at run time is not parsed by
    # this host's shell at all — so ssh's join and the guest's re-parse are the
    # only parse left, and one `%q` is exactly right. Two would arrive
    # backslashed.
    #
    # Line-based, which is sound only because the render refuses a newline in any
    # value — the same fact `profileLoad`'s `mapfile` rests on, read at the other
    # end.
    #
    # SC2329: a program that reads a profile and pushes nothing into a guest —
    # `capsule-provision`, whose values all stay on this host — has nothing to
    # quote.
    # shellcheck disable=SC2329
    profileQuote() {
      local v
      while IFS= read -r v; do printf '%q\n' "$v"; done
    }
  '';

  # Which profile, spliced where `transport` already resolves which capsule — and
  # the same shape for the same reason (`selectCapsule`, host/guest-ssh.nix):
  # `--profile <name>`, else `CAPSULE_PROFILE`, else a **refusal**. It strips
  # itself out of `"$@"` before a program's own flag loop runs, so a target's name
  # cannot be confused with a ref or a payload.
  #
  # **No default, and (item 51, decision 4) not even this host's own target.** A
  # baked fallback is the one thing that fails silently: on a host with two
  # documents it makes a collect run against the wrong project's `guestPath` and
  # `statePaths` and report success having taken nothing, which is
  # [item 47](../docs/ledger/047-a-script-on-stdin-and-the-command-that-eats-it.md)'s
  # shape with a bigger blast radius. Item 28's rule applies unchanged: the value
  # a missing one would fall back to is the failure.
  select = ''
    profileName="''${CAPSULE_PROFILE:-}"
    unprofiled=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --profile)
          shift
          [ "$#" -gt 0 ] || {
            echo "--profile needs the name of a profile" >&2
            exit 1
          }
          profileName="$1"
          ;;
        --profile=*) profileName="''${1#--profile=}" ;;
        *) unprofiled+=("$1") ;;
      esac
      shift
    done
    set -- ''${unprofiled[@]+"''${unprofiled[@]}"}

    if [ -z "$profileName" ]; then
      echo "''${0##*/}: which target? '--profile <name>', or CAPSULE_PROFILE in" >&2
      echo "  the environment. The values this program is about arrive at run" >&2
      echo "  time rather than in its text, so there is nothing to fall back to" >&2
      echo "  — or say it once, as 'capsule <name> <verb>', which fills it from" >&2
      echo "  the slot's assignment record." >&2
      exit 1
    fi
    profileLoad "$profileName" || exit 1
  '';
}
