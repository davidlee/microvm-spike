# The inbound direction of the sideband: putting one capsule's collected state
# *into* another one.
#
# [Item 32](../docs/ledger/032-the-sideband-channel.md) built the outbound half
# and reserved this one — "the ref name and the `-p` parent are here to reserve
# it" — for the case it named: a fresh audit capsule that must see the
# implementation capsule's phase sheets. `capsule-collect` takes that state out,
# `capsule-adopt` lays it on this host's disk, and neither of them puts it
# anywhere a second agent can read it
# ([item 35](../docs/ledger/035-briefing-a-capsule-with-state.md)).
#
# **The host validates and the guest only lays out**, which is the decision this
# file is shaped around. `host/exhibit.nix` is the same check `capsule-adopt`
# runs, spliced here rather than copied, because validation belongs where the
# policy is: the guest is the confined side, and a control that runs there is a
# control the confined thing could be made not to run. What crosses the door is
# a commit the host has already refused to send if it was refusable.
#
# **`code-oid` becomes a control here, and this is the first thing that reads
# it.** The commit message says which code the state was the state *of*, and the
# guest refuses unless its own HEAD is that commit. That refusal is what makes
# the rest safe: `git add -f -- <dir>` stages *worktree* content, so a state tree
# carries the other agent's uncommitted edits to tracked files under
# `statePaths`, and laying those over the same code reproduces the worktree that
# existed while laying them over different code composes a worktree that never
# did. It also teaches the flow rather than merely refusing — collect the source,
# `capsule <src> fetch` to bring the commit into the target repo, provision this
# capsule at it.
#
# Jail-agnostic like its neighbours: a git URL, an ssh destination, a fragment
# that reaches either, and one guest path.
{
  pkgs,
  lib,
  # The push-on-stdin seam and its build-time lint (host/guest-exec.nix).
  guestExec,
  # Where to ssh, e.g. `agent@10.99.0.2`. Jail-shaped, so injected.
  guestHost,
  # The guest's checkout as a git URL — this pushes the state commit in over the
  # same channel `capsule-provision` pushes code over. Jail-shaped, so injected,
  # and a **fragment** rather than a string since item 51 step 4: the host half
  # of the URL is `net.nix`'s and the path half is the profile's, so it is built
  # at run time by `guestRepoUrl` (host/programs.nix).
  guestRepo,
  # Which capsule, how to reach it, and git's own view of that: a fragment
  # setting `$capsule`, `ssh_cmd` and `GIT_SSH_COMMAND` (host/programs.nix).
  gitSsh,
  # Where a collected exhibit lives and what its refs are called
  # (host/quarantine.nix). Read at two names here, not one: the source capsule's
  # quarantine and the destination capsule's identity.
  quarantine,
  # Whether a guest-authored tree may be written at all (host/exhibit.nix).
  exhibit,
  # Which *target*, and the same shape `transport` has one axis over: a fragment
  # resolving `--profile` and loading the document (host/profile.nix, NOTES item
  # 51 step 4). It replaces three nix arguments here — the guest's checkout, this
  # host's, and the snapshot's command line — with `profile_guest_path`,
  # `profile_path` and a call to `snapshotArgs`.
  profileSelect,
  # ---------------------------------------------------------------- host origin
  #
  # The three below are [item 42](../docs/ledger/042-a-state-half-no-capsule-has-held.md):
  # a capsule taking on a *fresh* unit of work needs state that has never been
  # inside a capsule, so this verb grows an origin that is not one. Everything
  # downstream of "which commit, and what code was it of" is the sequence that
  # already existed.
  #
  # The guest's snapshot, verbatim — the same store path, not a second
  # instantiation of the same text (host/state-snapshot.nix, NOTES item 51). Run
  # locally rather than pushed on stdin, because there is no door in front of
  # this one.
  snapshotScript,
  # What points it at a checkout: a fragment defining `snapshotArgs <work>`,
  # which prints the ceiling and the declared templates off the loaded profile in
  # the order that script reads them (host/state-snapshot.nix). A fragment rather
  # than a string since step 4 — it used to be a nix function of the checkout,
  # which is one store path per project.
  snapshotArgs,
  # Every slot this host declares, for one refusal: a source that is not one of
  # them is not briefable, because **a quarantine is what a capsule sent back**
  # and not a place state lives. That is the reading item 42 had to choose
  # between, and choosing it is what makes a host origin need somewhere else to
  # be rather than a name in `collect/`.
  slots,
}: let
  # Pushed at each call rather than baked into the guest's closure, for
  # `host/guest-exec.nix`'s three reasons — and for this file's own: a capsule
  # briefed with another's state is one that has been running, and rebuilding it
  # to teach it how to receive would be the restart the whole sideband exists to
  # avoid.
  #
  # **No login shell**, like `observe` and `state-snapshot`: nothing here reads
  # the guest's `environment.variables`, so item 24's trap cannot arise.
  #
  # **One line, tab-separated, fixed order:** `<files>\t<dirty>`. Diagnostics go
  # to stderr. Unlike the outbound snapshot there is no `-` case — a brief that
  # cannot happen is a failure rather than a skip, because the caller asked for
  # this state specifically and a capsule that silently did not get it is one an
  # agent will answer from anyway.
  #
  # **The checkout it runs in is its third argument**, which is the seam that
  # makes it testable at all — the same one `host/guard.nix` takes its `tools`
  # through and `perimeter/` takes its fragments through. The interesting branches
  # here (a code-oid that does not match, a worktree somebody else has dirtied) are
  # ones a live host can only reach by having two capsules and dirtying one, so
  # `briefCases` runs this store path against a throwaway checkout in a build
  # sandbox. It used to be a function of the checkout and is one text with no
  # instantiations now (NOTES item 51): a value the script is *about* travels on
  # its command line, so a second project needs a second argument and not a second
  # program.
  runText = pkgs.writeText "capsule-brief-run" ''
    # Deliberately not `set -e`: every exit below is chosen, and each one says
    # which of the three preconditions failed rather than vanishing at the first
    # non-zero.
    set -uo pipefail

    commit=''${1:-}
    codeOid=''${2:-}
    work=''${3:-}

    if [ -z "$commit" ] || [ -z "$codeOid" ] || [ -z "$work" ]; then
      echo "capsule-brief: usage: <commit> <code-oid> <work>" >&2
      exit 2
    fi

    cd "$work" 2>/dev/null || {
      echo "capsule-brief: no checkout at $work" >&2
      exit 2
    }

    head=$(git rev-parse --verify --quiet HEAD) || {
      echo "capsule-brief: $work has no commit — capsule-provision first" >&2
      exit 2
    }

    # The control, and the reason this is git rather than tar at both ends. See
    # the header: a state tree carries worktree content, so it is only ever the
    # state of one commit and laying it over another makes a checkout that never
    # existed anywhere — which then gets read as one.
    if [ "$head" != "$codeOid" ]; then
      echo "capsule-brief: that state was the state of $codeOid, and this checkout" >&2
      echo "  is at $head. Refusing: the tree carries the other capsule's" >&2
      echo "  uncommitted work, and over different code that composes a worktree" >&2
      echo "  nobody ever had." >&2
      echo "  Provision this capsule at $codeOid first — if that commit is not in" >&2
      echo "  the target repo yet, it is the source capsule's collected code half." >&2
      exit 3
    fi

    # A brief overwrites tracked files, and that is intended — see above. What it
    # must not do is overwrite an agent's *own* uncommitted work, which is
    # exactly what it cannot tell apart afterwards. Immediately after a provision
    # this is empty by construction, because `updateInstead` only lets a push
    # land on a clean tree; a second brief onto an already-briefed capsule is
    # what this refuses, deliberately and with no override.
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
      echo "capsule-brief: this checkout has uncommitted changes to tracked files," >&2
      echo "  and a brief overwrites tracked files with another capsule's worktree" >&2
      echo "  content. There would be no way to tell the two apart afterwards, so" >&2
      echo "  nothing was written. Commit or discard them, or re-provision." >&2
      exit 3
    fi

    git rev-parse --verify --quiet "$commit^{commit}" >/dev/null || {
      echo "capsule-brief: $commit is not in this guest's repository — the push" >&2
      echo "  that should have put it there did not land." >&2
      exit 2
    }

    # An index of ours, never the agent's. The symmetry runs the whole length of
    # this channel: the source guest built the tree in a temporary index so its
    # agent's index never learned the paths (host/state-snapshot.nix), the host
    # reads it back through one (host/adopt.nix), and this writes it through one.
    # No repository anywhere has an index worth contaminating.
    #
    # Explicit per call rather than exported, which is not fastidiousness: with
    # `GIT_INDEX_FILE` in the environment, the `git status` below would compare
    # the worktree against the *state tree* and rewrite that index on the way
    # past — silently, and with a plausible wrong answer (the same trap
    # `host/state-snapshot.nix` orders itself around).
    idx=$(mktemp -u "''${TMPDIR:-/tmp}/capsule-brief-index.XXXXXX")
    trap 'rm -f "$idx"' EXIT
    gidx() { GIT_INDEX_FILE="$idx" git "$@"; }

    # git's own writer rather than a second one made of shell and tar. It also
    # refuses the path class independently of the host's check
    # (`error: invalid path '.git/…'`), which is the arrangement to want when the
    # other refusal is upstream and out of sight from here.
    gidx read-tree "$commit" || {
      echo "capsule-brief: read-tree refused $commit — see its message above." >&2
      exit 1
    }

    # `.capsule/` is *this system's* namespace inside a state tree, not the
    # target's: `dirty.diff` is a record *of* a worktree rather than part of one.
    # Writing it here would put it on disk as untracked content, which the next
    # collect from this capsule would pick up and carry again as though this
    # agent had written it. Dropped from the index and not from the tree, so the
    # exhibit in quarantine keeps it and `capsule <src> adopt` still hands it
    # over.
    while IFS= read -r -d "" p; do
      gidx update-index --force-remove -- "$p"
    done < <(gidx ls-files -z -- .capsule)

    files=$(gidx ls-files | wc -l)

    # `-f`, and the two refusals above are what earn it: same code, clean tree.
    gidx checkout-index -a -f || {
      echo "capsule-brief: checkout-index refused — see its message above." >&2
      exit 1
    }

    printf '%s\t%s\n' "$files" "$(git status --porcelain | wc -l)"
  '';

  script = guestExec.checked runText;
  # `rec`, so the standalone program is the fragment plus an argument parse
  # rather than a second spelling of the same sequence.
in rec {
  # The very store path a capsule runs, for `briefCases` in `flake.nix` — lint
  # included, since a case suite running an unlinted render would be asserting
  # about a program this repo does not ship. Not a render *for* the suite: there
  # is nothing left to render (NOTES item 51).
  runner = script;

  # `briefCheckSpec` on its own, for `briefCases`. The rest of this file needs a
  # guest, a door and a quarantine; **which names may be a source** needs none of
  # them, and it is the half item 42 decided — so it is the half worth pinning in
  # a build rather than on a host. The fragment's own text, called with the
  # caller's argument: a suite asserting about a re-spelling of it would be
  # asserting about a program this repo does not ship.
  specChecker = pkgs.writeText "capsule-brief-spec-check" ''
    set -uo pipefail
    capsule=''${CAPSULE_NAME:-dest}
    ${fragment}
    briefCheckSpec "$1" "''${2:---state}"
  '';
  # The whole of it as one shell function, so `capsule-provision --state` and
  # `capsule-brief` are one construction and not two careful ones. It needs
  # `$capsule` and `ssh_cmd` in scope, which every transport fragment sets, the
  # `profile_*` variables `profileSelect` sets, and `guestRepoUrl`, which the
  # call site's own `guestRepo` fragment defines — spliced there rather than here
  # because `capsule-provision` pushes over the same URL and would otherwise
  # define it twice. It brings its own quarantine, exhibit and snapshot-argument
  # fragments so that a call site has exactly one thing to splice.
  fragment = ''
    ${quarantine.fragment}
    ${exhibit.fragment}
    ${snapshotArgs}

    # `<capsule>[:<stage>]` — the source, and which link of its chain. Two tokens
    # on one argument, each bounded before it reaches a ref or a path, and both
    # bounded **separately from the work**: `capsule-provision` calls this while
    # parsing its arguments and calls `briefState` after the push, so a misspelt
    # `--state` is refused before any code lands rather than after it. An
    # argument error is not a partial result.
    #
    # `$2` is what the operator actually typed it after, because this runs under
    # two spellings — `capsule-provision --state a` and `capsule-brief a` — and a
    # refusal that quotes the wrong one sends the reader looking in the wrong
    # place. That is the whole reason `checkToken` takes a `shown` at all.
    briefSlots=(${lib.escapeShellArgs slots})

    briefCheckSpec() {
      local spec="$1" flag="''${2:---state}" d found=no
      briefSrc="''${spec%%:*}"
      briefStage=implementation
      case "$spec" in *:*) briefStage="''${spec#*:}" ;; esac
      ${quarantine.checkToken ''"$briefSrc"'' "'$flag $spec'"}
      ${quarantine.checkToken ''"$briefStage"'' "'$flag $spec'"}

      if [ "$briefSrc" = "$capsule" ]; then
        echo "capsule-brief: '$briefSrc' is this capsule. A brief moves state" >&2
        echo "  between two of them; what puts a capsule's own state back is a" >&2
        echo "  provision." >&2
        return 1
      fi

      # **A quarantine is what a capsule sent back** (NOTES item 42). Without
      # this, a directory of the right shape and any name at all is briefable,
      # which is a forgery of provenance with nothing to notice it by — and the
      # check is cheap only because the alternative reading was rejected: if a
      # quarantine were *a place state lives*, this refusal would be the seam a
      # host origin was built on instead of the thing that sends it elsewhere.
      for d in "''${briefSlots[@]}"; do
        [ "$briefSrc" = "$d" ] && found=yes
      done
      if [ "$found" = no ]; then
        echo "capsule-brief: '$briefSrc' is not a capsule on this host, and a" >&2
        echo "  quarantine is what a capsule sent back rather than a place state" >&2
        echo "  lives — so a source here names a slot that has collected, and" >&2
        echo "  nothing else. This host's own checkout is '--from-host'." >&2
        echo "  declared: ''${briefSlots[*]}" >&2
        return 1
      fi
    }

    # Which code a state commit was the state *of*, out of the message the
    # snapshot wrote (host/state-snapshot.nix). Read with the shell rather than
    # with `sed`, so a refusal never depends on a tool being on PATH. Sets
    # `codeOid`, which every caller declares `local`.
    briefCodeOid() {
      local q="$1" commit="$2" l
      codeOid=""
      while IFS= read -r l; do
        case "$l" in "code-oid: "*) codeOid="''${l#code-oid: }" ;; esac
      done < <(git --git-dir="$q" show -s --format='%B' "$commit")
      if [ -z "$codeOid" ] || [ "$codeOid" = - ]; then
        echo "capsule-brief: that state commit names no code-oid, so there is" >&2
        echo "  nothing to check this capsule's checkout against — and the check is" >&2
        echo "  the whole reason a tree of someone else's worktree may land here." >&2
        return 1
      fi
    }

    # Validate, push, lay out — everything downstream of *which commit*, which is
    # the only thing the two origins differ in. One construction rather than two
    # careful ones, and emphatically so here: the thing being factored is a
    # security control, which is what `host/exhibit.nix` exists to say.
    #
    # `origin` and `hand` are display only, and `hand` is a second argument
    # rather than a clause because the closing sentence is a claim: from a
    # capsule the difference is *the other agent's uncommitted work*, and from
    # this host it is the operator's own — the same count meaning two things.
    briefDeliver() {
      local q="$1" commit="$2" codeOid="$3" stage="$4" origin="$5" hand="$6"
      local line files dirty

      # Before the push, not after it: the check is upstream of every write on
      # both sides of the door.
      readExhibit "$q" "$commit"
      refuseExhibit "$q" "$commit"
      echo "capsule-brief: $origin $(git --git-dir="$q" rev-parse --short "$commit") -> $capsule"
      echo "  $total entries ($blobs files, $links symlinks), $bytes bytes, of code $codeOid"

      # Into the guest's own outbound namespace, under the stage it already had.
      # Not forced: a destination that has collected at this stage has its own
      # commit there, and overwriting one capsule's chain with another's is not
      # something a flag should make easy. It also means a later collect from
      # this capsule at this stage chains onto what it was given, which is the
      # provenance record item 32 described and reserved.
      if ! git --git-dir="$q" push --quiet "$(guestRepoUrl)" \
        "$commit:refs/capsule/state/$stage"; then
        echo "capsule-brief: could not push that commit into $capsule — is the VM" >&2
        echo "  up, and has it already got a commit at '$stage'? A collect of its" >&2
        echo "  own puts one there, and so does an earlier brief the guest then" >&2
        echo "  refused. The second kind is cleared by deleting" >&2
        echo "  refs/capsule/state/$stage in the guest's checkout." >&2
        return 1
      fi

      # One `%q`, because an array element is parsed by the guest's shell and by
      # no other (host/profile.nix).
      if ! line=$("''${ssh_cmd[@]}" ${lib.escapeShellArg guestHost} 'bash -s' -- \
        "$commit" "$codeOid" "$(printf '%q' "$profile_guest_path")" < ${script}); then
        echo "capsule-brief: the guest refused to lay that state out (above)." >&2
        return 1
      fi
      IFS=$'\t' read -r files dirty <<<"$line"
      echo "capsule-brief: $files files into $capsule's checkout, which now differs"
      echo "  from its HEAD in $dirty paths — that difference is $hand uncommitted"
      echo "  work, and it is the point rather than a mess."
    }

    briefState() {
      local spec="$1" flag="''${2:---state}"
      local src stage q commit codeOid
      briefCheckSpec "$spec" "$flag" || return 1
      src="$briefSrc"
      stage="$briefStage"

      q=${quarantine.repoOf "$src"}
      if [ ! -d "$q" ]; then
        echo "capsule-brief: nothing has been collected for '$src' — there is no" >&2
        echo "  quarantine at $q. 'capsule $src collect' first." >&2
        return 1
      fi

      if ! commit=$(git --git-dir="$q" rev-parse --verify --quiet \
        "${quarantine.stateRefsOf "$src"}/$stage^{commit}"); then
        echo "capsule-brief: $src has no state at stage '$stage'." >&2
        echo "  collected stages:" >&2
        git --git-dir="$q" for-each-ref --format='    %(refname:lstrip=4)' \
          "${quarantine.stateRefsOf "$src"}/" >&2 || true
        return 1
      fi

      briefCodeOid "$q" "$commit" || return 1

      briefDeliver "$q" "$commit" "$codeOid" "$stage" \
        "$src state/$stage" "the other agent's"
    }

    # The other origin, and the whole of what is new (NOTES item 42): a unit of
    # work whose out-of-band state has never been inside a capsule, because no
    # capsule has driven it yet. The tree is built by the same text the guest
    # runs, at `target.path` instead of the guest's checkout.
    #
    # **No archive.** A capsule's exhibit is kept because it is evidence of what
    # a confined thing did; a tree authored here is evidence of nothing that is
    # not still on this host's disk, and the original is the checkout it was read
    # from. So the ref the snapshot writes is dropped either side of the delivery
    # and nothing persists — which is also what keeps `collect/` meaning exactly
    # one thing, and what lets `briefCheckSpec` refuse every name that is not a
    # slot. Deleting it *before* is not tidiness: a leftover from an interrupted
    # run would become this commit's parent, and an accidental chain is an
    # archive nobody decided to keep.
    #
    # The objects it writes into the human's repository are garbage the moment
    # the ref goes, and `git gc` reaps them. The index is never touched — the
    # snapshot builds in one of its own, which is the contamination item 32
    # actually guarded against.
    briefDropHostRef() {
      git -C "$profile_path" update-ref -d \
        "refs/capsule/state/$1" 2>/dev/null || true
    }

    briefHostState() {
      local stage="''${1:-implementation}" unit="''${2:-}"
      local q line commit bytes files codeOid guestHead hostHead rc=0
      local -a snapArgs
      ${quarantine.checkToken ''"$stage"'' "'--stage $stage'"}
      # The same rule as `capsule-collect --unit`, refused here for the same
      # reason and one step earlier: an empty token substitutes into the middle
      # of every declared path and collapses it onto its parent, so the unscoped
      # tree would wear the scoped one's name (NOTES items 28, 32). Asked of the
      # loaded document since step 6, where it used to be a property of the
      # build — so a host with two targets gets each one's answer, and both
      # refusals name the profile they are about.
      if profileNeedsUnit; then
        if [ -z "$unit" ]; then
          echo "capsule-brief: profile '$profile_name' scopes its state paths to" >&2
          echo "  one unit of work, so a host origin has to say which. 'capsule" >&2
          echo "  $capsule unit <token>' records it, or pass --unit." >&2
          return 1
        fi
        ${quarantine.checkToken ''"$unit"'' "'--unit $unit'"}
      elif [ -n "$unit" ]; then
        # A flag that scopes nothing is a flag that lies about what landed.
        echo "capsule-brief: --unit, but profile '$profile_name' declares no state" >&2
        echo "  paths with a place for one, so it would scope nothing." >&2
        return 1
      fi

      if ! q=$(git -C "$profile_path" rev-parse --absolute-git-dir 2>/dev/null); then
        echo "capsule-brief: $profile_path is not a git repository, so there is" >&2
        echo "  no checkout here to take a unit's state out of." >&2
        return 1
      fi

      # The `code-oid` mismatch, refused **here** and not only in the guest —
      # which is not a second copy of the control but a fix for an ordering this
      # origin makes reachable. `briefDeliver` pushes before the guest speaks,
      # because the guest needs the commit to lay it out; from a capsule a
      # refused brief is retried with the *same* commit, so the stranded ref is
      # the same object and the second push is a no-op. A host origin mints a
      # **new root commit every run**, so a refused attempt leaves a ref the
      # retry cannot fast-forward, and the retry fails naming a cause that is not
      # the cause. Cheapest fix is to not push a doomed commit: one round trip,
      # ahead of the snapshot, so a mismatch writes nothing anywhere.
      #
      # Advisory, and the guest's refusal stays the control: this reads HEAD
      # twice — here and in the snapshot — and a HEAD that moves between them is
      # exactly what the confined side is there to catch. A guest that cannot be
      # asked falls through to the push, which has its own message.
      if guestHead=$("''${ssh_cmd[@]}" ${lib.escapeShellArg guestHost} \
        "git -C $(printf '%q' "$profile_guest_path") rev-parse HEAD" 2>/dev/null); then
        hostHead=$(git -C "$profile_path" rev-parse HEAD 2>/dev/null || echo -)
        if [ "$guestHead" != "$hostHead" ]; then
          echo "capsule-brief: this checkout is at $hostHead and $capsule is at" >&2
          echo "  $guestHead. A state tree is worktree content, so it is only ever" >&2
          echo "  the state of one commit; laying it over different code composes a" >&2
          echo "  worktree nobody ever had. Nothing was taken and nothing was" >&2
          echo "  pushed." >&2
          echo "  Provision $capsule at $hostHead first — 'capsule $capsule" >&2
          echo "  provision $hostHead' — then brief it." >&2
          return 1
        fi
      fi

      briefDropHostRef "$stage"
      # `declared`: this origin is a human's desk, so nothing outside the
      # target's declared paths travels (host/state-snapshot.nix, NOTES item 42).
      mapfile -t snapArgs < <(snapshotArgs "$profile_path")
      if ! line=$(bash ${snapshotScript} "$stage" "$unit" declared "''${snapArgs[@]}"); then
        echo "capsule-brief: no state snapshot of this host's checkout (above)." >&2
        briefDropHostRef "$stage"
        return 1
      fi
      IFS=$'\t' read -r commit bytes files <<<"$line"
      if [ "$commit" = - ]; then
        echo "capsule-brief: there is nothing to brief $capsule with — see above." >&2
        echo "  A brief that cannot happen is a failure and not a skip: the caller" >&2
        echo "  asked for this state, and a capsule that silently did not get it is" >&2
        echo "  one an agent will answer from anyway." >&2
        briefDropHostRef "$stage"
        return 1
      fi

      # A reading of HEAD and never a claim about it. Passing the provisioned
      # commit in here instead would turn the guest's check into one that passes
      # on the false case too — the price being the sequencing this verb inherits:
      # provision at the commit this checkout is on, then brief (NOTES item 42).
      if ! briefCodeOid "$q" "$commit"; then
        briefDropHostRef "$stage"
        return 1
      fi

      briefDeliver "$q" "$commit" "$codeOid" "$stage" \
        "this host's checkout state/$stage" "this checkout's own" || rc=$?
      briefDropHostRef "$stage"
      return "$rc"
    }
  '';

  # Separately invocable for `host/refresh.nix`'s reasons, which are the same
  # ones a step of a sequence always has: a provision that failed *at* this step
  # needs a way to retry only it, and a human who has provisioned by hand wants
  # this and no push. It is also how the thing is exercised without a provision.
  program = pkgs.writeShellApplication {
    name = "capsule-brief";
    # `bash` explicitly: the host origin runs the snapshot text here rather than
    # pushing it through a door, and a program that resolves its own interpreter
    # off an ambient PATH is one that works until it is run from a unit.
    runtimeInputs = [pkgs.git pkgs.openssh pkgs.coreutils pkgs.bash];
    text = ''
      ${gitSsh}
      ${profileSelect}
      ${guestRepo}
      ${fragment}

      # The `--unit` half is this profile's to decide, and a program holds
      # exactly one — the boundary item 51's decision 3 draws around the front
      # end's fleet table (docs/ledger/051-…).
      usage() {
        local unitFlag=""
        if profileNeedsUnit; then unitFlag=" [--unit <token>]"; fi
        echo "usage: capsule-brief [--capsule <name>] <source>[:<stage>]"
        echo "       capsule-brief [--capsule <name>] --from-host [--stage <name>]$unitFlag"
        echo
        echo "  Puts <source>'s collected state into this capsule's checkout, so a"
        echo "  second agent can read the first one's working state. Both capsules"
        echo "  must be at the same commit; the stage defaults to 'implementation'."
        echo
        echo "  --from-host takes the same state out of $profile_path instead,"
        echo "  for a unit of work no capsule has driven yet. Nothing is archived:"
        echo "  the checkout it came from is the original."
      }

      spec=""
      fromHost=no
      stage=implementation
      unit=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --from-host) fromHost=yes ;;
          --stage)
            shift
            [ "$#" -gt 0 ] || {
              echo "--stage needs a name" >&2
              exit 1
            }
            stage="$1"
            ;;
          --stage=*) stage="''${1#--stage=}" ;;
          --unit)
            shift
            [ "$#" -gt 0 ] || {
              echo "--unit needs a token" >&2
              exit 1
            }
            unit="$1"
            ;;
          --unit=*) unit="''${1#--unit=}" ;;
          -*)
            usage >&2
            exit 1
            ;;
          *)
            [ -z "$spec" ] || {
              echo "capsule-brief: one source, and '$spec' was already it." >&2
              exit 1
            }
            spec="$1"
            ;;
        esac
        shift
      done

      # Two origins, and naming both is two answers to one question. The capsule
      # form carries its stage in the spec (`a:audit`), so the flags belong to
      # the other one and saying so is cheaper than a flag that is silently
      # ignored.
      if [ "$fromHost" = yes ] && [ -n "$spec" ]; then
        echo "capsule-brief: '--from-host' and '$spec' are two origins. State comes" >&2
        echo "  from one capsule or from this host's checkout, not from both." >&2
        exit 1
      fi
      if [ "$fromHost" = no ]; then
        if [ -z "$spec" ]; then
          echo "capsule-brief: which state? A capsule that has collected, by name," >&2
          echo "  or '--from-host' for a unit no capsule has driven yet." >&2
          usage >&2
          exit 1
        fi
        if [ "$stage" != implementation ] || [ -n "$unit" ]; then
          echo "capsule-brief: a capsule's stage rides its name ('$spec:<stage>')," >&2
          echo "  and its unit is whatever that exhibit was collected under — both" >&2
          echo "  are readings of what is in the quarantine, not choices to make" >&2
          echo "  here. --stage and --unit are '--from-host' arguments." >&2
          exit 1
        fi
        briefState "$spec" capsule-brief
      else
        briefHostState "$stage" "$unit"
      fi
    '';
  };
}
