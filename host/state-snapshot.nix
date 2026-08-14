# The guest half of a collect's *sideband*: the state that is not a commit.
#
# A capsule's result has two halves with different lifecycles. The code half is
# `refs/heads/*` and `capsule-collect` has always fetched it. The other half —
# the target's gitignored runtime state, plus whatever the agent has not
# committed — exists only in the guest's worktree, and a collect that takes the
# first and drops the second reports a nine-phase run as one sha (NOTES item 32).
#
# So this builds a commit whose tree is *only* that state, under a ref namespace
# no branch ever occupies, and `capsule-collect` fetches it with a second
# refspec. Git's object model does the transport, the hashing and the
# deduplication; the commit message pins which code the state was the state of.
#
# **Pushed at each call, never baked into the guest's closure**, exactly as
# `host/observe.nix` is and for its two reasons — host-side policy about what
# leaves a capsule, and a copy on a volume from an older build is drift nothing
# reports — plus one this file learned the hard way: a capsule with a real
# workload in it cannot be rebuilt without a restart, and the first capsule that
# needed this was thirteen hours into a nine-phase slice.
#
# **No login shell**, like `observe`: nothing here reads the guest's
# `environment.variables`, so item 24's trap cannot arise.
#
# **One line, tab-separated, fixed order, defined here and nowhere else:**
# `<commit-or-dash>\t<bytes>\t<files>`. Diagnostics go to stderr, and a state
# half that cannot be taken is a `-` rather than a failure — the code refs are
# still worth collecting.
#
# **A function of the checkout it runs in**, for `brief.nix`'s reason and with
# the same seam: the branch that decides what an exhibit *contains* is one a live
# host reaches only by driving a real unit of work in a real capsule, so
# `snapshotCases` instantiates this same text against a throwaway checkout in a
# build sandbox. One text, two instantiations, no second copy of an invariant.
{
  pkgs,
  lib,
  # The guest's checkout.
  workdir,
  # What the target declares as its out-of-band state (`target.nix`'s
  # `statePaths`). An explicit allowlist and never "the ignored files": a
  # `.gitignore` routinely covers credentials, machine-local config and caches,
  # and `git add -f` over one is a loaded gun pointed wherever that list faces.
  #
  # A **template** list rather than a path list, since item 32's scope invariant:
  # each entry may hold one `${hole}`, filled at collect by the unit token the
  # assignment carries. What that buys is the difference between *the out-of-band
  # state of the work this capsule was assigned* and *every unit of work the
  # checkout has ever held* — 41 entries against 1886, measured
  # (docs/probes.md). A target whose state is not per-unit writes no hole and
  # nothing here changes for it.
  statePaths,
  # The ceiling, in bytes, on what one snapshot may carry. Refusing here rather
  # than letting `capsule-collect`'s `ulimit -f` catch it later is deliberate:
  # the fetch is atomic, so a packfile over that limit fails the *whole* collect
  # and loses the code refs too. This way an over-budget state half is skipped
  # and said, and the code still lands.
  stateMaxBytes,
  # The ref the chain lives on, minus its stage. Guest-side, and never
  # `refs/heads/*`: no branch ever contains this tree.
  refPrefix ? "refs/capsule/state",
}: let
  # The one hole a policy path may hold, spelled once. The predicate below and
  # the substitution in the script are the same fact read from two ends, and two
  # spellings of it is a template that silently never matches.
  hole = "{unit}";

  # Whether this target's policy is unit-scoped at all — known at eval, because
  # the templates are. `capsule-collect` reads it to decide whether a unit is
  # *required*, which is item 28's rule applied to the sharpest control here: a
  # template with a hole and no unit refuses, rather than degrading to the
  # unscoped list, because the unscoped list is the failure being fixed.
  needsUnit = lib.any (lib.hasInfix hole) statePaths;

  snapshotFor = work:
    pkgs.writeText "capsule-state-snapshot" ''
      set -euo pipefail

      work=${lib.escapeShellArg work}
      max=${toString stateMaxBytes}
      stage=''${1:-implementation}
      unit=''${2:-}
      declared=(${lib.escapeShellArgs statePaths})
      # A variable rather than a literal in the pattern below: `${hole}` contains
      # a `}`, and bash ends a parameter expansion at the first unquoted one — so
      # the literal spelling parses as `''${t//` followed by text, silently, and
      # every path comes out unsubstituted.
      hole=${lib.escapeShellArg hole}

      ${lib.optionalString needsUnit ''
        # Unreachable from `capsule-collect`, which refuses before it opens the
        # door and validates the token there (host/quarantine.nix's
        # `checkToken`). Kept because the alternative to an unreachable refusal
        # is a reachable substitution of the empty string — every scoped path
        # collapsing to its parent, which is the unscoped collect wearing the
        # scoped one's name.
        if [ -z "$unit" ]; then
          echo "capsule-state: these state paths are scoped to one unit and none" >&2
          echo "  was given. The host refuses before pushing this, so seeing it" >&2
          echo "  means capsule-collect and this script disagree." >&2
          exit 1
        fi
      ''}

      cd "$work" 2>/dev/null || {
        echo "capsule-state: no checkout at $work" >&2
        printf -- '-\t0\t0\n'
        exit 0
      }
      git rev-parse --git-dir >/dev/null 2>&1 || {
        echo "capsule-state: $work is not a repository — not provisioned yet" >&2
        printf -- '-\t0\t0\n'
        exit 0
      }

      # ---------------------------------------------------------------- read first
      #
      # Everything that consults the *real* index happens before GIT_INDEX_FILE is
      # exported, and the order is load-bearing rather than tidy: with a temporary
      # empty index in the environment, `git ls-files -o` calls the whole checkout
      # untracked and `git status` rewrites the index it was pointed at. Both are
      # silent, and both produce a plausible wrong answer.
      head=$(git rev-parse HEAD 2>/dev/null || echo -)
      dirty=$(git status --porcelain 2>/dev/null | wc -l)

      # The modified-tracked half, which no path list can carry: a file the agent
      # edited but did not commit is neither in a code ref nor untracked.
      tmpdiff=$(mktemp)
      trap 'rm -f "$tmpdiff" ''${GIT_INDEX_FILE:-}' EXIT
      git diff HEAD > "$tmpdiff" 2>/dev/null || : > "$tmpdiff"

      # What exists of the declared set, with the unit substituted in. A path a
      # target declares and this capsule does not have is normal — the target says
      # what its state *is*, not what any one run produced — so it is a line on
      # stderr and not a refusal. That covers the scoped case too: a unit with no
      # state under one of its paths is a run that did not produce that half.
      #
      # The token is `[A-Za-z0-9._-]+` minus `.` and `..`, checked host-side
      # before this is pushed, so the substitution cannot introduce a separator
      # and cannot climb: it names an instance and never widens the perimeter.
      take=()
      for t in "''${declared[@]}"; do
        p=''${t//"$hole"/"$unit"}
        if [ -e "$p" ]; then
          take+=("$p")
        else
          echo "capsule-state: no $p in this checkout — skipped" >&2
        fi
      done

      # Untracked-but-not-ignored: work the agent has not committed. Generic — "not
      # yet committed" is nobody's project's concept — and precisely the class a
      # `refs/heads/*` collect drops without saying so.
      #
      # Deliberately *not* scoped by the unit: this is the agent's uncommitted
      # work rather than the target's declared state, so there is no template to
      # put a hole in and no host policy that could say which of it belongs to
      # which unit. An agent working on one thing in one capsule is what makes
      # that sound, and it is the same assumption `dirty.diff` already rests on.
      while IFS= read -r f; do
        [ -n "$f" ] && take+=("$f")
      done < <(git ls-files -o --exclude-standard)

      if [ ''${#take[@]} -eq 0 ]; then
        echo "capsule-state: nothing declared is present and nothing is uncommitted" >&2
        printf -- '-\t0\t%s\n' 0
        exit 0
      fi

      bytes=$(du -sb -- "''${take[@]}" 2>/dev/null | awk '{t += $1} END {print t + 0}')
      if [ "$bytes" -gt "$max" ]; then
        echo "capsule-state: $bytes bytes of declared state, over the $max ceiling" >&2
        echo "  (target.nix statePaths / stateMaxBytes). Skipping the state half —" >&2
        echo "  the code refs still collect." >&2
        printf -- '-\t%s\t0\n' "$bytes"
        exit 0
      fi

      # ------------------------------------------------------------ then a temp index
      #
      # The agent is working in this checkout. Its index must never learn these
      # paths — a `git add -f` into it is a booby trap that goes off as somebody
      # else's commit — so the tree is built in an index of our own and thrown away.
      GIT_INDEX_FILE=$(mktemp -u "''${TMPDIR:-/tmp}/capsule-state-index.XXXXXX")
      export GIT_INDEX_FILE
      git read-tree --empty
      git add -f -- "''${take[@]}"

      diffblob=$(git hash-object -w --stdin < "$tmpdiff")
      git update-index --add --cacheinfo "100644,$diffblob,.capsule/dirty.diff"

      tree=$(git write-tree)
      ref=${refPrefix}/"$stage"
      parent=$(git rev-parse --verify --quiet "$ref" || true)
      parentarg=()
      [ -n "$parent" ] && parentarg=(-p "$parent")

      # What the tree cannot say, and the reason this is git rather than tar:
      # `code-oid` binds this state to the commit it was the state *of*, and the
      # parent makes the chain across stages append-only. `unit` is the third of
      # the same kind: the tree cannot say what it was scoped *by*, and an exhibit
      # whose scope is not on the record is one nobody can check the scope of.
      commit=$(
        printf '%s\n' \
          "capsule state: $stage" \
          "" \
          "stage: $stage" \
          "code-oid: $head" \
          "dirty: $dirty" \
          "unit: ''${unit:--}" |
          git commit-tree "$tree" "''${parentarg[@]}"
      )
      git update-ref "$ref" "$commit"

      files=$(git ls-tree -r --name-only "$tree" | wc -l)
      printf '%s\t%s\t%s\n' "$commit" "$bytes" "$files"
    '';
in {
  inherit needsUnit snapshotFor;
  script = snapshotFor workdir;
}
