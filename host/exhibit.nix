# Whether a guest-authored tree may be written to a disk. One check, and now two
# directions over it.
#
# [Item 34](../docs/ledger/034-adopting-a-guest-authored-tree.md) found what the
# checks actually are, by extracting a real capsule's tree by hand first, and the
# finding was that they are not the ones that would have been written blind:
#
#   - **paths** — absolute, or with a `..` or `.git` component. **Already refused
#     twice, and neither of them here.** `capsule-collect` fetches with
#     `transfer.fsckObjects=true`, which errors `hasDotdot`/`hasDotgit` at
#     index-pack time, so a collected quarantine cannot hold the class at all;
#     and `git read-tree` refuses it again at extraction. The loop below keeps
#     its own check as a third line, because a quarantine is a directory and a
#     human may have fetched into one without that config.
#   - **modes** — fsck passes a gitlink, and `checkout-index` writes it as an
#     **empty directory** with no message: evidence silently replaced by a
#     plausible absence. Refused here and nowhere else.
#   - **symlink targets** — the one nothing else does. `verify_path` bounds an
#     entry's own path and says nothing about what a `120000` blob contains; fsck
#     passes `-> /etc/passwd`; a checkout writes the link without following it.
#     The escape is the next thing that greps, copies or opens the tree. Refused
#     here and nowhere else.
#
# It lived inside `capsule-adopt`, which was then the only program that wrote a
# state tree anywhere. `capsule-brief` is the second
# ([item 35](../docs/ledger/035-briefing-a-capsule-with-state.md)): the inbound
# direction pushes a state commit *into* a capsule, and the decision recorded
# there is that the **host** validates and the guest only lays out, because
# validation belongs where the policy is. Two programs over one check is where a
# comment stops being enough — **anything built at two call sites needs one
# construction, not two careful ones** (CLAUDE.md), and this is the construction
# whose second copy would have been a security control.
#
# A shell fragment rather than a value, for `host/quarantine.nix`'s reason:
# nothing here is known at eval. The caller passes a git-dir and a commit and
# reads the counts back out of the variables the fragment sets.
{
  # `withinExhibit`, `readExhibit`, `refuseExhibit`. The last two are separate
  # because the summary between them differs — an adoption prints what it is
  # about to lay out, a brief prints what it is about to push — and because a
  # caller that read but did not refuse would be a silent hole. Every caller does
  # both, adjacently.
  fragment = ''
    # Does a symlink stay inside the exhibit? Resolved lexically, against the
    # tree rather than the filesystem: the target does not exist yet, and
    # `realpath` would answer a question about this host instead. 0 contained,
    # 1 above the root, 2 absolute.
    #
    # Depth, not a path, because the answer is the whole use: whether the walk
    # ever goes above where it started. `$dir` is the link's own directory, which
    # is what makes per-link containment enough for a *chain* of links — each one
    # resolves against its own position, so following a contained link lands
    # somewhere contained, and composing two cannot arrive anywhere a single one
    # could not.
    #
    # **`..` in a target is not the test**, which is the finding that paid for
    # doing one adoption by hand: doctrine's
    # `.doctrine/slice/254/phases -> ../../state/slice/254/phases` is inside the
    # root and load-bearing, so a rule refusing `..` refuses the very tree this
    # was built for.
    withinExhibit() {
      local dir="$1" target="$2" part depth=0
      local -a parts
      case "$target" in /*) return 2 ;; esac
      IFS=/ read -ra parts <<<"''${dir:+$dir/}$target"
      for part in ''${parts[@]+"''${parts[@]}"}; do
        case "$part" in
          "" | .) ;;
          ..)
            depth=$((depth - 1))
            [ "$depth" -ge 0 ] || return 1
            ;;
          *) depth=$((depth + 1)) ;;
        esac
      done
      return 0
    }

    # Reads one state commit out of a bare repository and sets `bad`, `total`,
    # `blobs`, `links` and `bytes`. Every refusal, not the first: an operator
    # deciding whether an exhibit is readable at all wants the whole picture, and
    # a program that stops at entry 1 of 1886 turns one look into N looks.
    readExhibit() {
      local q="$1" commit="$2"
      local entry meta path mode oid size c dir target rc _
      local -a comps
      bad=()
      total=0
      blobs=0
      links=0
      bytes=0
      while IFS= read -r -d "" entry; do
        total=$((total + 1))
        meta="''${entry%%$'\t'*}"
        path="''${entry#*$'\t'}"
        # `ls-tree -l` pads the size field, so this splits on whitespace rather
        # than at a fixed offset. A gitlink's size is `-`.
        read -r mode _ oid size <<<"$meta"
        case "$size" in
          "" | *[!0-9]*) ;;
          *) bytes=$((bytes + size)) ;;
        esac

        case "$path" in
          /*) bad+=("$path — an absolute path") ;;
        esac
        IFS=/ read -ra comps <<<"$path"
        for c in ''${comps[@]+"''${comps[@]}"}; do
          case "$c" in
            . | .. | .git)
              bad+=("$path — a '$c' component: it would write outside the exhibit, or into the repository holding it")
              break
              ;;
          esac
        done

        case "$mode" in
          100644 | 100755) blobs=$((blobs + 1)) ;;
          120000)
            links=$((links + 1))
            # One `cat-file` per link — 253 of them on the first real tree, which
            # is a fraction of a second and not worth a `--batch` pipeline and the
            # second parse that comes with it.
            target=$(git --git-dir="$q" cat-file blob "$oid")
            dir=""
            case "$path" in */*) dir="''${path%/*}" ;; esac
            rc=0
            withinExhibit "$dir" "$target" || rc=$?
            case "$rc" in
              0) ;;
              2) bad+=("$path -> $target — an absolute target: it points at this host's filesystem, not into the exhibit") ;;
              *) bad+=("$path -> $target — resolves above the exhibit root") ;;
            esac
            ;;
          160000)
            bad+=("$path — a gitlink: a commit this quarantine may not have, and an empty directory if it were extracted")
            ;;
          *)
            bad+=("$path — mode $mode, which is neither a file nor a symlink")
            ;;
        esac
      done < <(git --git-dir="$q" ls-tree -r -l -z "$commit")
    }

    # Nothing has been written when this refuses, on either side: an adoption has
    # not made its destination and a brief has not pushed. That ordering is the
    # control — the check is not a warning beside a write, it is upstream of one.
    refuseExhibit() {
      local q="$1" commit="$2"
      if [ ''${#bad[@]} -eq 0 ]; then
        return 0
      fi
      echo "''${0##*/}: refusing ''${#bad[@]} of $total entries — this tree is" >&2
      echo "  guest-authored, and these would not stay inside the directory named:" >&2
      printf '  %s\n' "''${bad[@]}" >&2
      echo "  Nothing was written. 'git --git-dir=$q ls-tree -r -l $commit' is the" >&2
      echo "  whole tree, if this is a capsule worth looking at by hand." >&2
      exit 1
    }
  '';
}
