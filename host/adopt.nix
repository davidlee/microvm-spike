# Taking the sideband half out of quarantine, with the check that makes it safe.
#
# [Item 32](../docs/ledger/032-the-sideband-channel.md) built the channel and
# stopped one step short on purpose: extraction stayed a human running
# `git ls-tree -r --long` and reading it before archiving with explicit
# pathspecs. One hand adoption first, so the program is written against what the
# job turned out to be — and it turned out to be a different job from the one
# that would have been written blind
# ([item 34](../docs/ledger/034-adopting-a-guest-authored-tree.md)).
#
# **The tree is guest-authored data**, and that is the whole of why this exists.
# The quarantine repository is host-owned and its refs land where the host says,
# but what is *inside* a state commit is whatever a confined agent's checkout
# held — including, if a capsule were compromised, entries chosen to be
# extracted. Three classes matter, and only one of them was on the list before a
# real tree was read:
#
#   - **paths** — absolute, or with a `..` or `.git` component. **Already held,
#     twice, and neither of them here.** `capsule-collect` fetches with
#     `transfer.fsckObjects=true`, which refuses `hasDotdot` and `hasDotgit` at
#     index-pack time, so a collected quarantine cannot contain the class at all;
#     and `read-tree` below refuses it again through `verify_path`. Both verified
#     against hand-built trees. The loop keeps its own check because a quarantine
#     is a directory and a human may have fetched into one without that config —
#     but it is a third line, and it says so.
#   - **modes** — a gitlink (`160000`) names a commit this quarantine may not
#     even have. fsck passes it, and `checkout-index` writes it as an **empty
#     directory** with no message: evidence silently replaced by a plausible
#     absence. Refused here, and nowhere else.
#   - **symlink targets** — the one nothing else does. `verify_path` bounds an
#     entry's own path and says nothing about what a `120000` blob contains; fsck
#     passes `-> /etc/passwd`; a checkout writes the link without following it.
#     So the danger is not during extraction at all, it is the next thing that
#     greps, copies or opens the tree afterwards. Refused here, and nowhere else.
#
# So the two checks item 32 named — "modes and prefixes" — turned out to be one
# already-held and one half-needed, and the check it *discovered*, by extracting
# a real tree by hand, is the one nothing anywhere held.
#
# **`..` in a target is not the test**, which is the finding that paid for doing
# one adoption by hand. 253 of the first real tree's 1886 entries are symlinks —
# doctrine mints a title-slug symlink beside every entity — and one of them is
# `.doctrine/slice/254/phases -> ../../state/slice/254/phases`, which is inside
# the extraction root and load-bearing: it is how a slice's phase sheets are
# reachable from the slice. A rule that refuses `..` refuses the very tree this
# was built for. The test is **resolution within the root**, lexically, against
# the tree rather than against this host's filesystem.
#
# **It does not archive, and it does not untar.** Item 32 predicted
# `git archive … | tar -x` with pathspecs — run against the hostile tree, that
# plants `absolute -> /etc/passwd` and `escape -> ../../../../etc/passwd` in the
# destination and turns the gitlink into an empty directory, exit 0, no output.
# The shape that survived contact is
# `read-tree` into a temporary index and `checkout-index` out of it, which is
# git's own hardened writer rather than a second one made of shell. The symmetry
# is worth seeing: the guest builds this tree in a temporary index so the agent's
# real index never learns the paths (host/state-snapshot.nix), and the host reads
# it back through a temporary index so no repository of ours learns them either.
# Neither end has an index worth contaminating.
#
# **No transport, and it is the first program here with none.** Adoption never
# touches a capsule: it reads a bare repository this host owns and writes a
# directory this host names. That matters beyond tidiness — the capsule whose
# exhibit is most worth adopting is a finished one, and every transport fragment
# refuses when there is no way in to the guest (host/guest-ssh.nix). So this
# takes `selectCapsule` alone, which is the half of that fragment answering
# *which* capsule rather than *how to reach* one.
{
  pkgs,
  # Which capsule, from `--capsule <name>` or `CAPSULE_NAME`, stripped out of
  # `"$@"` before this program's own parse runs (host/guest-ssh.nix). The naming
  # half only — see above.
  selectCapsule,
  # Where the exhibit lives and what its refs are called (host/quarantine.nix).
  quarantine,
  # Whether a guest-authored tree may be written at all (host/exhibit.nix). Lived
  # here until `capsule-brief` needed the same three functions for the inbound
  # direction, which is where a check with two callers becomes a construction
  # rather than a copy (NOTES item 35).
  exhibit,
}:
pkgs.writeShellApplication {
  name = "capsule-adopt";
  runtimeInputs = [pkgs.git pkgs.coreutils];
  text = ''
    ${selectCapsule}
    ${quarantine.fragment}
    ${exhibit.fragment}

    usage() {
      echo "usage: capsule-adopt [--capsule <name>] [--stage <name>] <dir>"
      echo "       capsule-adopt [--capsule <name>] [--stage <name>] --list"
      echo
      echo "  Lays a collected state commit out in <dir>, which must be empty or"
      echo "  absent. --list validates and reports without writing anything."
      echo "  The code half is a branch: 'capsule <name> branches | fetch'."
    }

    stage=implementation
    dest=""
    list=no
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --stage)
          shift
          [ "$#" -gt 0 ] || {
            echo "--stage needs a name" >&2
            exit 1
          }
          stage="$1"
          ;;
        --stage=*) stage="''${1#--stage=}" ;;
        --list) list=yes ;;
        -*)
          usage >&2
          exit 1
          ;;
        *)
          [ -z "$dest" ] || {
            echo "capsule-adopt: one destination, and '$dest' was already it." >&2
            exit 1
          }
          dest="$1"
          ;;
      esac
      shift
    done

    ${quarantine.checkStage}

    if [ "$list" = yes ] && [ -n "$dest" ]; then
      echo "capsule-adopt: --list writes nothing, so '$dest' would be ignored." >&2
      exit 1
    fi
    if [ "$list" = no ] && [ -z "$dest" ]; then
      echo "capsule-adopt: where to? An exhibit is laid out somewhere." >&2
      usage >&2
      exit 1
    fi

    # ------------------------------------------------------------- the exhibit
    q=${quarantine.repo}
    [ -d "$q" ] || {
      echo "capsule-adopt: nothing has been collected for '$capsule' — there is no" >&2
      echo "  quarantine at $q. 'capsule $capsule collect' first." >&2
      exit 1
    }
    # Absolute from here on: the extraction runs with its cwd inside the
    # destination, and `$state` may have come from a relative CAPSULE_ROOT.
    q=$(cd "$q" && pwd)

    ref="${quarantine.stateRefs}/$stage"
    if ! commit=$(git --git-dir="$q" rev-parse --verify --quiet "$ref^{commit}"); then
      echo "capsule-adopt: $capsule has no state at stage '$stage'." >&2
      echo "  collected stages:" >&2
      git --git-dir="$q" for-each-ref --format='    %(refname:lstrip=4)' \
        "${quarantine.stateRefs}/" >&2 || true
      echo "  (a capsule whose target declares no statePaths never has one —" >&2
      echo "   the code half is 'capsule $capsule branches'.)" >&2
      exit 1
    fi

    # What the tree cannot say. `code-oid` is the whole reason this is git rather
    # than tar — it names the commit this state was the state *of* — so it is
    # printed before anything is written rather than left in a log.
    echo "capsule-adopt: $capsule stage '$stage' at $(git --git-dir="$q" rev-parse --short "$commit")"
    git --git-dir="$q" show -s --format='%B' "$commit" | sed 's/^/  /'

    # -------------------------------------------------------------- the check
    #
    # Three classes, one of which nothing else anywhere holds — and the summary
    # below is printed *after* the refusal rather than before, because the whole
    # arrangement is that the check is upstream of the write and not beside it
    # (host/exhibit.nix).
    readExhibit "$q" "$commit"
    refuseExhibit "$q" "$commit"

    echo "capsule-adopt: $total entries ($blobs files, $links symlinks), $bytes bytes"
    echo "  top level:"
    git --git-dir="$q" ls-tree --name-only "$commit" | sed 's/^/    /'
    if [ "$list" = yes ]; then
      exit 0
    fi

    # ------------------------------------------------------------- the layout
    #
    # **Empty or absent, and no `--force` to say otherwise.** The obvious shape is
    # to lay this over the audit worktree the code half is checked out in, and the
    # state tree does overlap one — doctrine declares `.doctrine/slice`, which
    # holds authored content as well as ignored research. So an over-the-top
    # adoption overwrites tracked files with guest-authored ones, and deciding
    # which of those the auditor wanted is a judgement this program has no
    # standing to make. It lays out an exhibit; combining it with anything is for
    # the hand that has the context — the same narrowing item 32 made one layer up
    # when it refused to let a project name its own allowlist.
    if [ -e "$dest" ]; then
      [ -d "$dest" ] || {
        echo "capsule-adopt: '$dest' exists and is not a directory." >&2
        exit 1
      }
      [ -z "$(ls -A "$dest")" ] || {
        echo "capsule-adopt: '$dest' is not empty, and an exhibit is laid out rather" >&2
        echo "  than merged: what a state tree overlaps in a worktree is authored" >&2
        echo "  content, and which copy you wanted is not this program's call." >&2
        echo "  Name an empty directory, then merge it yourself." >&2
        exit 1
      }
    else
      mkdir -p "$dest"
    fi
    dest=$(cd "$dest" && pwd)

    # git's own writer, through an index of ours. `read-tree` refuses the path
    # class independently of the loop above (`error: invalid path '.git/…'`,
    # verified), which is the arrangement to want when the other refusal is a
    # shell script reading attacker-chosen bytes. What it does *not* refuse is a
    # symlink target or a gitlink — checked above, because nothing below checks
    # them. `checkout-index` writes relative to the cwd, hence the subshell.
    idx=$(mktemp -u "''${TMPDIR:-/tmp}/capsule-adopt-index.XXXXXX")
    trap 'rm -f "$idx"' EXIT
    if ! (
      cd "$dest"
      export GIT_INDEX_FILE="$idx"
      git --git-dir="$q" --work-tree="$dest" read-tree "$commit"
      git --git-dir="$q" --work-tree="$dest" checkout-index -a
    ); then
      echo "capsule-adopt: git refused to lay the tree out, and it is the second of" >&2
      echo "  the two checks rather than the first — so this is a path the loop" >&2
      echo "  above passed and git did not. Read its message before overriding" >&2
      echo "  anything; nothing here is a formality." >&2
      exit 1
    fi

    echo "capsule-adopt: $dest"
    echo "  the code it was the state of:"
    echo "    capsule $capsule fetch   # then check out the code-oid above"
  '';
}
