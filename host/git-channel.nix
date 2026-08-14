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
# Jail-agnostic in the same sense as perimeter/: it knows a git URL, an ssh
# destination and a shell fragment that reaches either. No tap, no namespace, no
# hypervisor. Under netns the URL is unchanged and the fragment grows a
# `ProxyCommand` against the capsule's unix socket (NOTES item 17) — that is the
# whole difference, and it is at the call site.
{
  pkgs,
  # Which repo is confined: `path` to push from, `collectMaxBytes` as the
  # ceiling on what a fetch may write.
  target,
  # Where to ssh, e.g. `agent@10.99.0.2` — for the *state* half of a collect
  # only, which is a script pushed at the guest rather than a question git can
  # answer (`snapshot` below). The code half still knows only a URL.
  guestHost,
  # The guest-side snapshot script as a store path, pushed on stdin at each
  # collect and never baked into the guest (host/state-snapshot.nix, NOTES item
  # 32). `null` for a target that declares no `statePaths`, which degrades to the
  # code-only collect this program used to be.
  snapshot,
  # The third step of a provision, as one shell command line (host/refresh.nix):
  # regenerate the derived state the push cannot carry, in the checkout the push
  # just made. `null` for a target that derives nothing from its checkout, which
  # degrades to the two-step provision this program used to be (NOTES item 33).
  refresh ? null,
  # The branch a capsule's work lives on inside the guest — a constant, and not
  # the target's to name (docs/contract-target.md). The guest's seed sets the
  # same one; they must agree or a provision moves a ref and checks nothing out,
  # which is why it is threaded from one place rather than spelled here.
  workBranch,
  # The guest's checkout as a git URL. Jail-shaped, so injected.
  guestRepo,
  # Which capsule, how to reach it, and git's own view of that: a shell fragment
  # that sets `$capsule` and `ssh_cmd`, consumes `--capsule` out of `"$@"`
  # (host/guest-ssh.nix) and exports `GIT_SSH_COMMAND`. Jail-shaped, so injected
  # — and required, because without it neither program knows which capsule it is
  # for. Built in `host/programs.nix` because `capsule-brief` pushes over the
  # same door and a second spelling of one conversion is a second thing to keep
  # right.
  gitSsh,
  # Where the quarantine is and what its refs are called (host/quarantine.nix).
  # Its own file since `capsule-adopt` reads what this writes: a convention with
  # two programs over it is a construction, not a note saying don't spell it
  # twice.
  quarantine,
  # The *inbound* state half, as `{fragment, …}` (host/brief.nix, NOTES item 35):
  # one capsule's collected state pushed into another's checkout, which is step
  # (2) of a provision and the reason an audit capsule can read what an
  # implementation capsule was working on. `null` for a target that declares no
  # `statePaths`, which drops the flag rather than shipping one that refuses.
  brief ? null,
}: let
  inherit (pkgs) lib;

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
      ${gitSsh}
      ${lib.optionalString (brief != null) brief.fragment}
      usage() {
        echo "usage: capsule-provision [--capsule <name>] <ref> [--force]${lib.optionalString (brief != null) " [--state <capsule>[:<stage>]]"}" >&2
      }
      src="''${CAPSULE_REPO:-${target.path}}"
      ref=""
      force=""
      ${lib.optionalString (brief != null) ''stateSpec=""''}
      # A loop rather than positional tests, so `--force` may go either side of
      # the ref and an unrecognised flag is refused rather than taken for a ref.
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --force) force="+" ;;
          ${lib.optionalString (brief != null) ''
        --state)
          shift
          [ "$#" -gt 0 ] || {
            echo "--state needs <capsule>[:<stage>]" >&2
            exit 1
          }
          stateSpec="$1"
          ;;
        --state=*) stateSpec="''${1#--state=}" ;;
      ''}
          -*)
            usage
            exit 1
            ;;
          *) ref="$1" ;;
        esac
        shift
      done

      ${lib.optionalString (brief != null) ''
        # Before anything is pushed. `briefState` would check the same two tokens
        # itself, but it runs after the code has landed, and an argument error
        # that leaves a half-provisioned capsule behind is an argument error the
        # program made worse (host/brief.nix).
        if [ -n "$stateSpec" ]; then
          briefCheckSpec "$stateSpec" --state || exit 1
        fi
      ''}
      # Required, and there is nothing left to default it to: `<ref>` is a ref in
      # the *target repo* and `${workBranch}` is the guest's, which is the whole
      # separation that let the target's branch field be deleted. The base commit
      # is the one thing a capsule is pinned to, so it is stated at every
      # provision rather than inherited from whatever a branch points at today.
      if [ -z "$ref" ]; then
        usage
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
      if [ -n "$guestHead" ] && [ "$guestHead" != refs/heads/${workBranch} ]; then
        echo "capsule-provision: the guest has HEAD at $guestHead, not" >&2
        echo "  refs/heads/${workBranch}. A push would move the ref and leave the" >&2
        echo "  worktree alone. Collect anything worth keeping, then in the guest:" >&2
        echo "  git checkout ${workBranch}" >&2
        exit 1
      fi

      echo "capsule-provision: $src $ref ($(git -C "$src" rev-parse --short "$commit")) -> ${guestRepo}"
      # Always onto the guest's `${workBranch}`, whatever the source ref was
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
             "$force$commit:refs/heads/${workBranch}"; then
        echo "capsule-provision: push refused. Either the guest's worktree is" >&2
        echo "  dirty (finish or collect first), or this would discard commits" >&2
        echo "  the guest has made — 'capsule-provision $ref --force' to insist." >&2
        exit 1
      fi
      echo "capsule-provision: guest is at $commit on ${workBranch}"
      ${lib.optionalString (brief != null) ''
        # Step (2) of three, and the order is the whole of item 33's reading of a
        # provision: push the code, materialise the state half, then regenerate
        # what neither may carry. The state has to be in before the refresh
        # because a refresh derives from the checkout, and a checkout missing
        # half of what it is supposed to hold derives from half of it — silently,
        # and looking exactly like state that was derived from all of it.
        #
        # Its failure is the provision's, for the same reason the refresh's is:
        # the code landed, so this is a capsule that will answer questions from a
        # checkout nobody finished furnishing.
        if [ -n "$stateSpec" ]; then
          if ! briefState "$stateSpec"; then
            echo "capsule-provision: the code landed and the state did not." >&2
            echo "  The checkout is at $commit with none of $stateSpec's state in" >&2
            echo "  it. Fix the cause, then 'capsule-brief --capsule $capsule" >&2
            echo "  $stateSpec'." >&2
            exit 1
          fi
        fi
      ''}
      ${lib.optionalString (refresh != null) ''
        # A provision is not finished when the push lands (NOTES item 33). What
        # the target derives *from* its checkout cannot travel in a commit and
        # must not travel in a collect — a copy is stale authority in whatever
        # tree it lands in — so it is regenerated here, after the push, from the
        # code the push just delivered.
        #
        # Its failure is the provision's, and that is the one place this differs
        # from the collect's state half: there, a state half that cannot be taken
        # still leaves code worth having. Here, code without its derived state is
        # the trap — and it fails by *absence*, which reads as fine until
        # something answers from it.
        echo "capsule-provision: regenerating derived state"
        if ! ${refresh}; then
          echo "capsule-provision: the code landed and the refresh did not." >&2
          echo "  The checkout is at $commit; what it derives is stale or absent." >&2
          echo "  Fix the cause, then 'capsule-refresh --capsule $capsule'." >&2
          exit 1
        fi
      ''}
    '';
  };

  collect = pkgs.writeShellApplication {
    name = "capsule-collect";
    runtimeInputs = [pkgs.git pkgs.openssh pkgs.coreutils];
    text = ''
      ${gitSsh}
      ${quarantine.fragment}
      # The capsule names its own quarantine, and that used to be a separate
      # positional argument — so `capsule-collect faux` meant a directory while
      # `capsule-provision` meant a ref and neither meant a capsule. One
      # identity: whatever a capsule is called is what its refs and its
      # quarantine are called, which is what every caller already passed.
      #
      # `--stage` names which link of the sideband chain this collect appends
      # to: an implementation capsule and the audit capsule that judges it are
      # two stages of one story, and overwriting one ref with the other would
      # lose the half that says what was seen (NOTES item 32).
      stage=implementation
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
          *)
            echo "usage: capsule-collect [--capsule <name>] [--stage <name>]" >&2
            echo "  the capsule names its own quarantine — refs/capsule/<name>/*." >&2
            exit 1
            ;;
        esac
        shift
      done
      ${quarantine.checkStage}
      quarantine=${quarantine.repo}

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

      # One refspec per half of a result. The code half is what every collect has
      # always taken; the state half is added only when the target declares any
      # (NOTES item 32), so a target with no `statePaths` gets exactly the
      # program it got before.
      refspecs=("+refs/heads/*:${quarantine.codeRefs}/*")
      ${lib.optionalString (snapshot != null) ''
        # The state half is built *in the guest*, first, so that it and the code
        # refs come back in one fetch. A script pushed on stdin, never a program
        # in the guest's closure — host-side policy about what leaves a capsule,
        # and a live capsule cannot be rebuilt without a restart
        # (host/state-snapshot.nix).
        #
        # Its failure is not the collect's: a state half that cannot be taken
        # leaves that ref where it was, and the commits are still worth having.
        refspecs+=("+refs/capsule/state/*:${quarantine.stateRefs}/*")
        if line=$("''${ssh_cmd[@]}" ${guestHost} 'bash -s' -- "$stage" < ${snapshot}); then
          IFS=$'\t' read -r oid stateBytes stateFiles <<<"$line"
          if [ "$oid" = - ]; then
            echo "capsule-collect: no state snapshot this run (see above)."
          else
            echo "capsule-collect: state/$stage $oid — $stateFiles files, $stateBytes bytes"
          fi
        else
          echo "capsule-collect: the state snapshot failed — collecting code only." >&2
        fi
      ''}
      echo "capsule-collect: ${guestRepo} -> $quarantine"
      # --no-tags is load-bearing, not tidiness: tag auto-following writes
      # refs/tags/* outside the namespace this refspec names, which is the one
      # way the guest could otherwise choose where its refs land. The second
      # refspec is the state half and obeys the same rule: the guest chooses
      # what is in its refs, never where they land.
      #
      # `heads/` and `state/` are siblings rather than the second nested under
      # the first: a guest branch literally named `state` would otherwise be a
      # directory/file ref-lock collision, which is loud but timed by the guest.
      #
      # --atomic buys the invariant the whole sideband exists for — nobody
      # observes a result commit without the capsule state that goes with it.
      #
      # fsck on the way in, because index-pack parses guest-authored bytes
      # host-side whatever the transport. It turns out to buy more than object
      # integrity, and `capsule-adopt` leans on it: `hasDotdot` and `hasDotgit`
      # are fsck errors, so a tree with a `..` or `.git` path component is
      # refused *here* and a collected quarantine cannot hold one (verified
      # against hand-built trees, NOTES item 34). What fsck passes without a
      # murmur is a symlink pointing at `/etc/passwd` and a gitlink — which is
      # exactly what the extractor has to check, and all it has to check.
      #
      # The ulimit is the byte ceiling: no config knob bounds a fetch, so bound
      # the file it writes.
      (
        ulimit -f ${toString maxBlocks}
        git -C "$quarantine" -c transfer.fsckObjects=true \
          fetch --no-tags --atomic "${guestRepo}" "''${refspecs[@]}"
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
        "refs/capsule/$capsule/"
      echo "capsule-collect: $quarantine"
      ${lib.optionalString (snapshot != null) ''
        # The two halves leave by different doors, and saying so here is where a
        # human finds out: the code half is a branch to fetch, the state half is
        # a tree an extractor validates before it touches a disk (NOTES item 34).
        echo "  code:  capsule $capsule fetch"
        echo "  state: capsule $capsule adopt <dir>   (--list to look first)"
      ''}
    '';
  };
in {
  inherit provision collect;
}
