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
  lib,
  # Which target this invocation is about, as a fragment that resolves
  # `--profile` and loads the document (host/profile.nix, NOTES item 51 step 4).
  # `path` — what `capsule-provision` pushes from — was the whole of what this
  # file wanted from a target, and it is `$profile_path` now, so neither program
  # here is a function of which project the host confines. What a fetch may write
  # is not the project's to say either way (NOTES item 36) — see `policies`.
  profileSelect,
  # The host's policy vocabulary (policies.nix): each entry's `collectMaxPackBytes`
  # and `mayCollect` are the two ingestion limbs, and a collect selects one by
  # name at run time. Baked as a case rather than taken as a byte count, for the
  # reason the whole item exists: a caller selects from a declared set and does
  # not author a bound, so `--policy sealed` is a choice and `--max-bytes 10G`
  # would be an authority. `capsule-host` resolves its allowlist the same way
  # (flake.nix).
  policies,
  # Where to ssh, e.g. `agent@10.99.0.2` — for the *state* half of a collect
  # only, which is a script pushed at the guest rather than a question git can
  # answer (`snapshot` below). The code half still knows only a URL.
  guestHost,
  # The guest-side snapshot as `{script, argsFragment}` (host/state-snapshot.nix,
  # NOTES item 32): a store path pushed on stdin at each collect and never baked
  # into the guest, plus the command line that points it at a checkout. Neither
  # this nor `refresh` below is nullable any more (NOTES item 51 step 6): the
  # code-only collect and the two-step provision are still here and are branches
  # this program takes on the **document it loaded**, so that a host confining
  # two projects gets each one's answer rather than the build's.
  snapshot,
  # The third step of a provision, as a fragment defining `refreshInvoke`
  # (host/refresh.nix): regenerate the derived state the push cannot carry, in
  # the checkout the push just made.
  refresh,
  # The branch a capsule's work lives on inside the guest — a constant, and not
  # the target's to name (docs/contract-target.md). The guest's seed sets the
  # same one; they must agree or a provision moves a ref and checks nothing out,
  # which is why it is threaded from one place rather than spelled here.
  workBranch,
  # The guest's checkout as a git URL: a **fragment** defining `guestRepoUrl`,
  # since step 4 — the host half is `net.nix`'s and the path half is the
  # profile's, so it is built at run time (host/programs.nix). Jail-shaped, so
  # injected.
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
  # implementation capsule was working on.
  brief,
}: let
  inherit (pkgs) lib;

  # The vocabulary as a shell case: a policy name in, its two ingestion limbs
  # out. Generated rather than spelled, so adding a policy is one entry in
  # `policies.nix` and nothing here.
  policyCase = lib.concatMapStringsSep "\n" (n: let
    p = policies.policies.${n};
  in ''
    ${n})
      maxBytes=${toString p.collectMaxPackBytes}
      may=${
      if p.mayCollect
      then "yes"
      else "no"
    }
      ;;'')
  policies.everything;

  policyNames = lib.concatStringsSep " " policies.everything;

  provision = pkgs.writeShellApplication {
    name = "capsule-provision";
    runtimeInputs = [pkgs.git pkgs.openssh];
    text = ''
      ${gitSsh}
      ${profileSelect}
      ${guestRepo}
      ${refresh}
      ${brief.fragment}
      guestUrl=$(guestRepoUrl)
      # The `--unit` half is the profile's to decide and this is reached with one
      # loaded, so it is asked rather than baked: a program holds exactly one
      # target and may be honest about it, which is the boundary item 51's
      # decision 3 draws around the front end's table.
      usage() {
        local unitFlag=""
        if profileNeedsUnit; then unitFlag=" [--unit <token>]"; fi
        echo "usage: capsule-provision [--capsule <name>] <ref> [--force] [--state <capsule>[:<stage>] | --state-from-host [--stage <name>]$unitFlag]" >&2
      }
      # `CAPSULE_REPO` over the document, which is the shape this whole item
      # generalises (NOTES item 51): what the lookup replaced is the *baked
      # default*, and the environment still wins over both.
      src="''${CAPSULE_REPO:-$profile_path}"
      ref=""
      force=""
      stateSpec=""
      stateFromHost=""
      stateStage=""
      stateUnit=""
      # A loop rather than positional tests, so `--force` may go either side of
      # the ref and an unrecognised flag is refused rather than taken for a ref.
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --force) force="+" ;;
          --state)
            shift
            [ "$#" -gt 0 ] || {
              echo "--state needs <capsule>[:<stage>]" >&2
              exit 1
            }
            stateSpec="$1"
            ;;
          --state=*) stateSpec="''${1#--state=}" ;;
          # The composite [item 42](../docs/ledger/042-a-state-half-no-capsule-has-held.md)
          # declined to build until somebody wanted it, and
          # [items 45](../docs/ledger/045-a-brief-is-an-origin-not-a-top-up.md)
          # and 47 both do, for different reasons that meet here. 45: the window in
          # which a capsule can be briefed is the window before its agent starts,
          # and a step of a sequence that is easy to forget and impossible to take
          # late wants to be part of the step before it. 47: on a target whose
          # refresh writes tracked files there is no such thing as *after* a
          # provision — the refresh either commits, moving HEAD off the commit
          # `code-oid` compares against, or leaves the tree dirty, which the brief
          # refuses. Between the push and the refresh is the only moment both
          # preconditions hold, and it is a moment no separate command can name.
          --state-from-host) stateFromHost=yes ;;
          # `briefHostState`'s two arguments, and they belong to this origin alone
          # for the reason `capsule-brief` refuses them beside a source: a capsule's
          # stage rides its name and its unit is whatever its exhibit was collected
          # under, both readings of a quarantine rather than choices.
          --stage)
            shift
            [ "$#" -gt 0 ] || {
              echo "--stage needs <name>" >&2
              exit 1
            }
            stateStage="$1"
            ;;
          --stage=*) stateStage="''${1#--stage=}" ;;
          --unit)
            shift
            [ "$#" -gt 0 ] || {
              echo "--unit needs <token>" >&2
              exit 1
            }
            stateUnit="$1"
            ;;
          --unit=*) stateUnit="''${1#--unit=}" ;;
          -*)
            usage
            exit 1
            ;;
          *) ref="$1" ;;
        esac
        shift
      done

      # Before anything is pushed. `briefState` would check the same two tokens
      # itself, but it runs after the code has landed, and an argument error
      # that leaves a half-provisioned capsule behind is an argument error the
      # program made worse (host/brief.nix).
      if [ -n "$stateSpec" ]; then
        briefCheckSpec "$stateSpec" --state || exit 1
      fi
      # Two origins, and naming both says nothing about which one wins. Refused
      # rather than ordered, on `capsule-brief`'s own rule for the same pair.
      if [ -n "$stateSpec" ] && [ -n "$stateFromHost" ]; then
        echo "capsule-provision: --state names a capsule to take state from and" >&2
        echo "  --state-from-host takes it from this host's checkout. Pick one." >&2
        exit 1
      fi
      # The flags of an origin that was not selected are an argument error and
      # not a no-op, for `capsule-brief --from-host`'s reason: a stage or a unit
      # silently ignored is a scoping the caller believes they asked for.
      if [ -z "$stateFromHost" ] && { [ -n "$stateStage" ] || [ -n "$stateUnit" ]; }; then
        echo "capsule-provision: --stage and --unit scope the state taken from" >&2
        echo "  this host, so they need --state-from-host. A brief from a capsule" >&2
        echo "  is scoped by the exhibit it reads." >&2
        exit 1
      fi
      # And the scope itself, which used to be a flag that only existed where
      # *this host's* target had a hole for one (item 51 step 6). Asked of the
      # document now, and refused rather than ignored for the reason above: a
      # token that substitutes nowhere is a scoping the caller believes they
      # asked for.
      if [ -n "$stateUnit" ] && ! profileNeedsUnit; then
        echo "capsule-provision: --unit, but profile '$profile_name' declares no" >&2
        echo "  state paths with a place for one, so it would scope nothing." >&2
        exit 1
      fi
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
      if ! advertised=$(git ls-remote --symref "$guestUrl" HEAD); then
        echo "capsule-provision: cannot reach $guestUrl" >&2
        echo "  — is the VM up, has it finished booting, and is that the" >&2
        echo "  checkout its image made? (profile '$profile_name')" >&2
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

      echo "capsule-provision: $src $ref ($(git -C "$src" rev-parse --short "$commit")) -> $guestUrl"
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
      if ! git -C "$src" push "$guestUrl" \
             "$force$commit:refs/heads/${workBranch}"; then
        echo "capsule-provision: push refused. Either the guest's worktree is" >&2
        echo "  dirty (finish or collect first), or this would discard commits" >&2
        echo "  the guest has made — 'capsule-provision $ref --force' to insist." >&2
        exit 1
      fi
      echo "capsule-provision: guest is at $commit on ${workBranch}"
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
      # The same step from the other origin, at the same point in the sequence
      # and for one more reason than the paragraph above gives: this is the only
      # moment the guest's HEAD is the commit this host's checkout is on *and*
      # its worktree is clean, which are `briefHostState`'s two preconditions
      # and are exactly what the refresh below is about to end (NOTES item 47).
      #
      # The remedy in the failure message is deliberately not "run it again":
      # after the refresh there may be no way to, which is the whole reason this
      # flag exists rather than two commands.
      if [ -n "$stateFromHost" ]; then
        if ! briefHostState "$stateStage" "$stateUnit"; then
          echo "capsule-provision: the code landed and the state did not." >&2
          echo "  The checkout is at $commit with none of this host's state for" >&2
          echo "  it. Fix the cause and provision again — the refresh below may" >&2
          echo "  leave no later moment a brief can land in." >&2
          exit 1
        fi
      fi
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
      # Asked of the document rather than assumed from the build: this
      # program exists in a shape that runs a refresh because *this host's*
      # target declares one, and the profile it was pointed at may not. A
      # target that derives nothing from its checkout is a working absent
      # path, so this is a step to skip rather than a provision to fail.
      if [ -z "$profile_refresh" ]; then
        echo "capsule-provision: profile '$profile_name' derives nothing from"
        echo "  its checkout, so there is nothing to regenerate."
      else
        echo "capsule-provision: regenerating derived state"
        if ! refreshInvoke; then
          echo "capsule-provision: the code landed and the refresh did not." >&2
          echo "  The checkout is at $commit; what it derives is stale or absent." >&2
          echo "  Fix the cause, then 'capsule-refresh --capsule $capsule" >&2
          echo "  --profile $profile_name'." >&2
          exit 1
        fi
      fi
    '';
  };

  collect = pkgs.writeShellApplication {
    name = "capsule-collect";
    runtimeInputs = [pkgs.git pkgs.openssh pkgs.coreutils];
    text = ''
      ${gitSsh}
      ${profileSelect}
      ${guestRepo}
      ${snapshot.argsFragment}
      ${quarantine.fragment}
      guestUrl=$(guestRepoUrl)
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
      # Which policy this collect ingests under, and there is no default: the two
      # limbs it resolves are *whether* anything may come back and *how much*, and
      # both used to be the target's (NOTES item 36). A name rather than a number,
      # so a caller selects from what this host declared and cannot author a bound.
      policy=""
      # `--unit` names the work this capsule was assigned, and it is the scope
      # of the exhibit rather than a label on it: the target's state paths are
      # templates, and this is what fills their hole (NOTES item 32). Opaque
      # here — a token, never a path and never a glob — so nothing in this
      # program learns what a unit of work is for the target it collects from.
      unit=""
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
          --policy)
            shift
            [ "$#" -gt 0 ] || {
              echo "--policy needs a name" >&2
              exit 1
            }
            policy="$1"
            ;;
          --policy=*) policy="''${1#--policy=}" ;;
          --unit)
            shift
            [ "$#" -gt 0 ] || {
              echo "--unit needs a token" >&2
              exit 1
            }
            unit="$1"
            ;;
          --unit=*) unit="''${1#--unit=}" ;;
          *)
            unitFlag=""
            if profileNeedsUnit; then unitFlag=" [--unit <token>]"; fi
            echo "usage: capsule-collect [--capsule <name>] --policy <name> [--stage <name>]$unitFlag" >&2
            echo "  the capsule names its own quarantine — refs/capsule/<name>/*." >&2
            exit 1
            ;;
        esac
        shift
      done
      ${quarantine.checkStage}

      # Both ingestion limbs, resolved before the door is opened — which is the
      # whole of what "refuses before" buys: a capsule that may not send anything
      # back is not asked to build a snapshot first.
      #
      # No policy is a refusal and never a fallback, for `--unit`'s reason at the
      # sharper end (item 28): the value a missing bound would fall back to is the
      # unbounded ingest the bound exists to prevent, so the worst possible default
      # is the old behaviour under the new name.
      if [ -z "$policy" ]; then
        echo "capsule-collect: no policy, so no ingestion bound and nothing that" >&2
        echo "  says this capsule may send anything back at all. What comes out of" >&2
        echo "  a capsule is host policy, not the project's (NOTES item 36)." >&2
        echo "  'capsule $capsule collect' fills it from the slot, or --policy" >&2
        echo "  <name> for this collect alone. Declared: ${policyNames}." >&2
        exit 1
      fi
      case "$policy" in
      ${policyCase}
        *)
          echo "capsule-collect: no policy named '$policy'." >&2
          echo "  declared: ${policyNames}" >&2
          exit 1
          ;;
      esac
      if [ "$may" != yes ]; then
        echo "capsule-collect: policy '$policy' does not permit collecting, so" >&2
        echo "  nothing leaves this capsule. That is the policy holding rather" >&2
        echo "  than a failure — 'capsule $capsule policy <name>' selects another" >&2
        echo "  from the set the slot declares." >&2
        exit 1
      fi
      # `ulimit -f` counts 512-byte blocks. RLIMIT_FSIZE, so this bounds the size
      # of any *one* file the fetch writes — the packfile — and nothing else. It
      # is a backstop, not a bound on the transfer: a pack of a million small
      # objects never trips it and still fills the disk, and a delta bomb never
      # trips it and still eats index-pack's memory. Do not read it as the ceiling
      # the design needs; NOTES item 18 lists what a real one costs.
      maxBlocks=$((maxBytes / 512))
      # The scope, and it is the last thing item 51 had to move (step 6). This
      # was **two texts and a build-time choice between them**: `stateNeedsUnit`
      # over `target.nix`'s templates decided which of the pair a host shipped,
      # so a program pointed at any other document got this host's target's
      # answer. Both are here now and the fork is `profileNeedsUnit`, which asks
      # the document this run loaded.
      if profileNeedsUnit; then
        # Item 28's rule at the sharpest place there is one. A template with a
        # hole and no unit does **not** degrade to the unscoped list: the
        # unscoped list is the failure this exists to fix — 1886 entries where
        # 41 name the work, three unrelated units each larger than the driven
        # one (docs/probes.md) — so the worst possible default is the old
        # behaviour under the new name.
        #
        # Refused here rather than in the guest, before the door is opened: the
        # token goes into the middle of a path, and an argument error that has
        # already crossed into a capsule is one this program made worse.
        if [ -z "$unit" ]; then
          echo "capsule-collect: profile '$profile_name' scopes its state paths to" >&2
          echo "  one unit of work, and nothing said which. A collect brings back" >&2
          echo "  the out-of-band state of the work the capsule was assigned, and" >&2
          echo "  none that is not — so there is no unscoped fallback." >&2
          echo "  Either 'capsule $capsule unit <token>' to record what this" >&2
          echo "  slot is driving, or --unit <token> for this collect alone." >&2
          exit 1
        fi
        ${quarantine.checkToken ''"$unit"'' "'--unit $unit'"}
      else
        # A flag that scopes nothing is a flag that lies about what landed.
        if [ -n "$unit" ]; then
          echo "capsule-collect: --unit, but profile '$profile_name' declares no" >&2
          echo "  state paths with a place for one, so it would scope nothing." >&2
          echo "  Collect without it." >&2
          exit 1
        fi
      fi
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
      # always taken; the state half is added only when the **document** declares
      # any (NOTES item 32) — which used to be a property of the build and is
      # this run's question since step 6, so a target with no `statePaths` gets
      # exactly the program it got before and a host with two gets each answer.
      refspecs=("+refs/heads/*:${quarantine.codeRefs}/*")
      if [ "''${#profile_state_paths[@]}" -gt 0 ]; then
        # The state half is built *in the guest*, first, so that it and the code
        # refs come back in one fetch. A script pushed on stdin, never a program
        # in the guest's closure — host-side policy about what leaves a capsule,
        # and a live capsule cannot be rebuilt without a restart
        # (host/state-snapshot.nix).
        #
        # Its failure is not the collect's: a state half that cannot be taken
        # leaves that ref where it was, and the commits are still worth having.
        refspecs+=("+refs/capsule/state/*:${quarantine.stateRefs}/*")
        # The scope goes on the line as well as into the commit message, because
        # the count beside it means nothing without it: `41 files` is a correct
        # collect or a broken one depending on what it was scoped by.
        scope=""
        if profileNeedsUnit; then scope=" (unit $unit)"; fi
        # `all`: this origin is a capsule, so uncommitted work anywhere in the
        # checkout is the one agent's and is the point (NOTES item 32). Spelled
        # at the call site rather than defaulted in the script, because the other
        # origin is a human's desk and a default would make that one the quiet
        # case (NOTES item 42).
        # The tail of that command line, off the loaded profile and escaped
        # once — an array element is parsed by the guest's shell and by no
        # other (host/profile.nix, host/state-snapshot.nix).
        mapfile -t snapArgs < <(snapshotArgs "$profile_guest_path" | profileQuote)
        if line=$("''${ssh_cmd[@]}" ${guestHost} 'bash -s' -- "$stage" "$unit" all "''${snapArgs[@]}" < ${snapshot.script}); then
          IFS=$'\t' read -r oid stateBytes stateFiles <<<"$line"
          if [ "$oid" = - ]; then
            echo "capsule-collect: no state snapshot this run (see above)."
          else
            echo "capsule-collect: state/$stage$scope $oid — $stateFiles files, $stateBytes bytes"
          fi
        else
          echo "capsule-collect: the state snapshot failed — collecting code only." >&2
        fi
      fi
      # The policy on the line for the reason the unit's scope is: a byte count
      # that trips means nothing without the bound it tripped against, and a
      # collect that succeeded says which perimeter let it.
      echo "capsule-collect: policy $policy — $guestUrl -> $quarantine"
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
        ulimit -f "$maxBlocks"
        git -C "$quarantine" -c transfer.fsckObjects=true \
          fetch --no-tags --atomic "$guestUrl" "''${refspecs[@]}"
      ) || {
        echo "capsule-collect: fetch failed — a malformed object, or a packfile" >&2
        echo "  over $maxBytes bytes (policy $policy's collectMaxPackBytes)." >&2
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
      if [ "''${#profile_state_paths[@]}" -gt 0 ]; then
        # The two halves leave by different doors, and saying so here is where a
        # human finds out: the code half is a branch to fetch, the state half is
        # a tree an extractor validates before it touches a disk (NOTES item 34).
        echo "  code:  capsule $capsule fetch"
        echo "  state: capsule $capsule adopt <dir>   (--list to look first)"
      fi
    '';
  };
in {
  inherit provision collect;
}
