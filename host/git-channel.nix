# The git channel, host-initiated in both directions.
#
# The host used to serve a mirror and wait for the guest to push to it. It now
# does the initiating: `capsule-provision` pushes history in, `capsule-collect`
# fetches work out. Neither is a service, nothing listens, and the guest cannot
# start either one. NOTES item 18 is why, with the measurement.
#
# Two properties this shape has and the served mirror could not:
#
#   - The host's git only ever runs in a repository the host authored — the
#     target repo it pushes from, and the quarantine repo it fetches into. The
#     guest's repo is only ever the guest's. No repository is written by two
#     uids, so there is nothing to share, no setgid, no `sharedRepository`, and
#     nothing a compromised guest can leave in a repo the human's git will read.
#   - The base commit is an argument, not a value baked into the guest's
#     closure. That was one of the two things NOTES item 17 needed out of the
#     closure for a single guest image; the other is the address, which netns
#     handles.
#
# Jail-agnostic in the same sense as perimeter/: it knows a git URL and,
# optionally, the ssh command that reaches it. No tap, no namespace, no
# hypervisor. Under netns the URL is unchanged and `sshCommand` grows a
# `ProxyCommand` against the capsule's unix socket (NOTES item 17) — that is the
# whole difference, and it is at the call site.
{
  pkgs,
  # Which repo is confined: `path` to push from, `defaultBranch` to land on,
  # `collectMaxBytes` as the ceiling on what a fetch may write.
  target,
  # The guest's checkout as a git URL. Jail-shaped, so injected.
  guestRepo,
  # Value for GIT_SSH_COMMAND, or null for plain ssh. Jail-shaped, so injected.
  sshCommand ? null,
}: let
  inherit (pkgs) lib;

  # Same two variables `perimeter/default.nix` defines, deliberately spelled the
  # same way: `CAPSULE_ROOT` and `CAPSULE_STATE` mean one thing per capsule, and
  # both files document them. Change one, change the other.
  statePaths = ''
    root="''${CAPSULE_ROOT:-''${MICROVM_SPIKE_ROOT:-$PWD}}"
    state="''${CAPSULE_STATE:-$root/.vm/host}"
  '';

  ssh = lib.optionalString (sshCommand != null) ''
    export GIT_SSH_COMMAND=${lib.escapeShellArg sshCommand}
  '';

  # `ulimit -f` counts 512-byte blocks. RLIMIT_FSIZE, so this bounds the size of
  # any *one* file the fetch writes — the packfile — and nothing else. It is a
  # backstop, not a bound on the transfer: a pack of a million small objects
  # never trips it and still fills the disk, and a delta bomb never trips it and
  # still eats index-pack's memory. Do not read this as the ceiling the design
  # needs; NOTES item 18 lists what a real one costs.
  maxBlocks = target.collectMaxPackBytes / 512;

  provision = pkgs.writeShellApplication {
    name = "capsule-provision";
    runtimeInputs = [pkgs.git pkgs.openssh];
    text = ''
      ${ssh}
      src="''${CAPSULE_REPO:-${target.path}}"
      ref=""
      force=""
      # A loop rather than positional tests, so `--force` may go either side of
      # the ref and an unrecognised flag is refused rather than taken for a ref.
      for arg in "$@"; do
        case "$arg" in
          --force) force="+" ;;
          -*)
            echo "usage: capsule-provision <ref> [--force]" >&2
            exit 1
            ;;
          *) ref="$arg" ;;
        esac
      done

      # Required, deliberately not defaulted to ${target.defaultBranch}: the base
      # commit is the one thing a capsule is pinned to, and it should be stated
      # at every provision rather than inherited from whatever the branch happens
      # to be pointing at today.
      if [ -z "$ref" ]; then
        echo "usage: capsule-provision <ref> [--force]" >&2
        echo "  <ref> is any commit-ish in $src — a branch, a tag or a sha." >&2
        exit 1
      fi

      if ! commit=$(git -C "$src" rev-parse --verify --quiet "$ref^{commit}"); then
        echo "capsule-provision: $src has no commit at '$ref'" >&2
        exit 1
      fi

      # Whose HEAD is it? `receive.denyCurrentBranch=updateInstead` only governs
      # a push to the branch the guest's HEAD names, so a guest sitting on any
      # other branch takes the push as an ordinary ref update: history lands, the
      # worktree is untouched, and nothing says so. Reproduced, and it is the
      # reason the seed sets --initial-branch explicitly.
      #
      # Over the git transport rather than a second injected ssh command, so this
      # file still knows only a URL. An empty repo advertises no symref at all,
      # so no answer means unborn — which is the seed's case, and the seed is
      # what guarantees it there.
      if ! advertised=$(git ls-remote --symref "${guestRepo}" HEAD); then
        echo "capsule-provision: cannot reach ${guestRepo}" >&2
        echo "  — is the VM up, and has it finished booting?" >&2
        exit 1
      fi
      guestHead=""
      case "$advertised" in
        "ref: "*)
          guestHead=''${advertised#ref: }
          guestHead=''${guestHead%%$'\t'*}
          ;;
      esac
      if [ -n "$guestHead" ] && [ "$guestHead" != refs/heads/${target.defaultBranch} ]; then
        echo "capsule-provision: the guest has HEAD at $guestHead, not" >&2
        echo "  refs/heads/${target.defaultBranch}. A push would move the ref and leave the" >&2
        echo "  worktree alone. Collect anything worth keeping, then in the guest:" >&2
        echo "  git checkout ${target.defaultBranch}" >&2
        exit 1
      fi

      echo "capsule-provision: $src $ref ($(git -C "$src" rev-parse --short "$commit")) -> ${guestRepo}"
      # Always onto the guest's own default branch, whatever the source ref was
      # called: `receive.denyCurrentBranch=updateInstead` only checks out a push
      # to the branch the guest has checked out, and a provision that moved a
      # ref without touching the worktree would be a silent no-op.
      #
      # Not forced by default, which is the guard on the agent's committed work:
      # a non-fast-forward push is refused rather than discarding it. `--force`
      # is the deliberate override. The guest also refuses either way while its
      # worktree is dirty — that is `updateInstead`, and it is the behaviour we
      # want.
      if ! git -C "$src" push "${guestRepo}" \
             "$force$commit:refs/heads/${target.defaultBranch}"; then
        echo "capsule-provision: push refused. Either the guest's worktree is" >&2
        echo "  dirty (finish or collect first), or this would discard commits" >&2
        echo "  the guest has made — 'capsule-provision $ref --force' to insist." >&2
        exit 1
      fi
      echo "capsule-provision: guest is at $commit on ${target.defaultBranch}"
    '';
  };

  collect = pkgs.writeShellApplication {
    name = "capsule-collect";
    runtimeInputs = [pkgs.git pkgs.openssh pkgs.coreutils];
    text = ''
      ${ssh}
      ${statePaths}
      name="''${1:-capsule}"
      quarantine="$state/collect/$name.git"

      # Host-created, host-configured, and never writable by the guest: the
      # host's git must not run in a repository the guest could have put config
      # or hooks into. Bare, because nothing is ever checked out of it — it is a
      # landing area, and the second step into the real repo is yours.
      #
      # Kept rather than recreated per collect, which is a deliberate deviation
      # from what doctrine accepted (NOTES item 18): persistence is what makes a
      # second collect incremental, and it is the retained exhibit. The
      # execution-context rule is unaffected — only freshness is.
      if [ ! -d "$quarantine" ]; then
        mkdir -p "$(dirname "$quarantine")"
        git init --bare --quiet "$quarantine"
        echo "capsule-collect: new quarantine at $quarantine"
      fi

      echo "capsule-collect: ${guestRepo} -> $quarantine"
      # --no-tags is load-bearing, not tidiness: tag auto-following writes
      # refs/tags/* outside the namespace this refspec names, which is the one
      # way the guest could otherwise choose where its refs land.
      #
      # fsck on the way in, because index-pack parses guest-authored bytes
      # host-side whatever the transport. The ulimit is the byte ceiling: no
      # config knob bounds a fetch, so bound the file it writes.
      (
        ulimit -f ${toString maxBlocks}
        git -C "$quarantine" -c transfer.fsckObjects=true \
          fetch --no-tags "${guestRepo}" \
          "+refs/heads/*:refs/capsule/$name/*"
      ) || {
        echo "capsule-collect: fetch failed — a malformed object, or a packfile" >&2
        echo "  over ${toString target.collectMaxPackBytes} bytes (target.nix collectMaxPackBytes)." >&2
        exit 1
      }

      # What landed, by sha. The sha is the *pin*: durable, cheap, and enough to
      # name this result forever. The exhibit is this quarantine repository,
      # which is why it is kept — and which makes its reaping the moment the
      # exhibit expires. Nothing here sets that retention.
      git -C "$quarantine" for-each-ref \
        --sort=-committerdate \
        --format='  %(objectname:short)  %(refname:short)  %(committerdate:relative)  %(subject)' \
        "refs/capsule/$name/"
      echo "capsule-collect: $quarantine"
    '';
  };
in {
  inherit provision collect;
}
