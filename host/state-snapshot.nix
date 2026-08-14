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
{
  pkgs,
  lib,
  # The guest's checkout.
  workdir,
  # What the target declares as its out-of-band state (`target.nix`'s
  # `statePaths`). An explicit allowlist and never "the ignored files": a
  # `.gitignore` routinely covers credentials, machine-local config and caches,
  # and `git add -f` over one is a loaded gun pointed wherever that list faces.
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
}:
pkgs.writeText "capsule-state-snapshot" ''
  set -euo pipefail

  work=${lib.escapeShellArg workdir}
  max=${toString stateMaxBytes}
  stage=''${1:-implementation}
  declared=(${lib.escapeShellArgs statePaths})

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

  # What exists of the declared set. A path a target declares and this capsule
  # does not have is normal — the target says what its state *is*, not what any
  # one run produced — so it is a line on stderr and not a refusal.
  take=()
  for p in "''${declared[@]}"; do
    if [ -e "$p" ]; then
      take+=("$p")
    else
      echo "capsule-state: no $p in this checkout — skipped" >&2
    fi
  done

  # Untracked-but-not-ignored: work the agent has not committed. Generic — "not
  # yet committed" is nobody's project's concept — and precisely the class a
  # `refs/heads/*` collect drops without saying so.
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
  # parent makes the chain across stages append-only.
  commit=$(
    printf '%s\n' \
      "capsule state: $stage" \
      "" \
      "stage: $stage" \
      "code-oid: $head" \
      "dirty: $dirty" |
      git commit-tree "$tree" "''${parentarg[@]}"
  )
  git update-ref "$ref" "$commit"

  files=$(git ls-tree -r --name-only "$tree" | wc -l)
  printf '%s\t%s\t%s\n' "$commit" "$bytes" "$files"
''
