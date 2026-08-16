# `capsule` — the human's front end, and nothing else.
#
# NOTES item 20 decided the naming ahead of this: which capsule a program means
# is `--capsule <name>`, else `CAPSULE_NAME`, and the transport is derived from
# the name rather than baked into a store path. That left a front end with
# exactly three jobs: resolve a name, pick the copy of a program that can reach
# it, and exec. It owns no transport, no socket path of its own and no second
# implementation of anything below it.
#
# Resolving is now slightly more than reading a value, and deliberately so: the
# declared default went with slots being abstract, so an unnamed verb here means
# *the capsule that is up*, refusing when none or several are. That is a
# host-state answer, which the four programs must not have — see below.
#
# Why a program rather than more `just` recipes: the recipes need this checkout
# and a devshell, and on the module path a capsule outlives both — the units are
# on the host and a human logged into it has no repo. So the run-time verbs live
# here and `just` delegates to them (`just up` keeps only what genuinely needs
# the flake: `microvm -c`, which resolves the instance name as a flake attribute,
# NOTES item 21). One implementation, two ways to say it.
#
# **Picking a copy is a front end's latitude, not a program's.** Two copies of
# each of the four programs exist by design and carry different transports, and
# inside the repo the devshell's shadow the module's on PATH (CLAUDE.md). They
# refuse rather than guess, which is item 20's decision and stands; choosing
# between them is what a human's front end is for, and `just _capsule` was
# already doing it. This inherits that, so it exists in one place instead of
# beside every recipe. Note what it is *not*: this picks between two copies of
# another program, it does not carry two transports of its own.
{
  pkgs,
  lib,
  net,
  capsules,
  # The host's policy vocabulary (policies.nix). Read for two things a program
  # may not do: validate a selection against the set the *slot* declares, and
  # name the file that slot's allowlist symlink must point at. Both copies of this
  # front end get the same declaration, so this adds no reason for them to be two
  # store paths.
  policies,
  # The host->guest ssh relaxation, for the *reachability probe* only
  # (host/guest-ssh.nix). The human's own door keeps the strict default, because a
  # human is there to read the warning; a probe asking "is anything listening"
  # would otherwise report a rotated host key as an unreachable guest.
  guestSsh,
  # Which `capsule-<verb>` programs this host actually has. `baseline` is absent
  # when the target declares none (host/programs.nix), and an unknown verb should
  # say so rather than exec a command that is not there.
  programVerbs,
  # Whether this target's state paths are scoped to a unit of work (NOTES item
  # 32). It decides two things here and nothing anywhere else: whether `unit` is
  # a verb at all, and whether a collect is handed the one the record holds. A
  # target with no hole in its policy gets neither, because a field nothing reads
  # is a field that will one day be believed.
  # The guest-side half of a status, as a store path pushed over the door
  # (host/observe.nix). A path and not a set of guest paths, deliberately: this
  # file asks a capsule what is true and does not know what `/work` is.
  observe,
  # What builds that program's command line, as **one opaque splice** for the
  # same reason (NOTES item 51 step 4): the profile reader, the record
  # convention and the argument order, composed in `host/programs.nix` beside the
  # paths they are about. The paths moved out of `observe`'s text and then off
  # `target.nix` entirely; they did not move into this file's vocabulary, and the
  # only thing this file spells about a target is a *name*.
  observeFragment,
  # Which verbs' programs read a profile, so this front end knows which ones to
  # fill a `--profile` in for (host/programs.nix). `inject` and `adopt` are not
  # among them, because neither is about a value the target supplies.
  profileVerbs,
  # Where the module keeps its state: quarantines and the assignment records. The
  # allowlist links are *not* in here — they are the one thing a proxy must read,
  # and this directory is the one place it may not (NOTES item 39,
  # host/services.nix's `allowlistDir`). On the module path this is not a guess at all —
  # that copy is wrapped with `CAPSULE_STATE` and `CAPSULE_REPO` from the host's
  # own options (host/services.nix), and `CAPSULE_STATE` is the first thing
  # `quarantineOf` tries. The literal is the *devshell* copy's guess at where the
  # module put things, and the record's root on both.
  #
  # **An argument with a default, and every real call site takes the default** —
  # so both copies are still one store path, and no run-time value can move a
  # record (CLAUDE.md: `CAPSULE_STATE` moves the quarantine and not the record,
  # deliberately, since a record for a devshell capsule would describe a slot that
  # does not exist). It is an argument for the reason `host/guard.nix`'s `tools`
  # is: the one thing tying this program to this host is what a case suite has to
  # substitute, and `policyCases` in flake.nix is what does.
  moduleState ? "/var/lib/capsule",
  # Under which ref a capsule's *own* outbound state chain sits, on its volume
  # (host/state-snapshot.nix's `refPrefix`, which is where it is declared). Two
  # verbs here need the name: `handoff` clears the destination's chain before
  # standing it up on somebody else's, and nothing else on this host may guess at
  # it — `capsule-brief` pushes into the same namespace and a second spelling
  # would be a second thing to keep true.
  stateRefPrefix,
  # How this front end asks a guest for its HEAD, and how it drops a stale link
  # of the chain above. The one thing tying `handoff`, `land` and the record's
  # `base.oid` to a live capsule, taken as an argument for exactly the reason
  # `proxyControl` is: `pkgs.openssh` is in `runtimeInputs`, so a case suite
  # cannot stub `ssh` by putting one in front of it (CLAUDE.md), and the
  # branches that matter here — an exhibit that lags its guest, a destination
  # whose stale ref would refuse the incoming chain — are reachable on a live
  # host only by driving two agents into disagreement.
  #
  # Two functions rather than two command strings, because each call needs a
  # *result*: what the guest's head is, and whether the drop happened. What is
  # **not** pinned by substituting them is the ssh argv itself — the same
  # boundary item 41's seam leaves around its sudo rule, and the reason
  # `gitChannelCases` exists one program over.
  #
  # An argument with a default, and every real call site takes the default, so
  # both shipped copies are still one store path.
  guestControl ? ''
    guestHead() { observed "$1" | cut -f1; }

    # Which links of the chain were dropped, one per line, so the caller reports
    # what happened rather than what it asked for. The guest decides what is
    # there: a stage in the quarantine that the guest no longer has is a forced
    # refspec's leftover, not a ref to delete.
    guestDropState() {
      local n="$1" ssh_argv=()
      local -a args
      shift
      door "$n" probe || return 1
      slotProfile "$n" >/dev/null || return 1
      mapfile -t args < <(printf '%s\n' "$profile_guest_path" "$@" | profileQuote)
      "''${ssh_argv[@]}" "agent@${net.guest}" 'bash -s' -- "''${args[@]}" <<'GUEST'
    set -eu
    work=$1
    shift
    for s in "$@"; do
      r=${stateRefPrefix}/$s
      if git -C "$work" rev-parse --verify --quiet "$r" > /dev/null; then
        git -C "$work" update-ref -d "$r"
        echo "$r"
      fi
    done
    GUEST
    }
  '',
  # How this front end asks after, and bounces, a slot's egress proxy — the last
  # step of `capsule <slot> policy <name>`, and the only one that needs a
  # privilege this program does not have (NOTES item 41).
  #
  # An argument for the same reason `moduleState` is, and a sharper one:
  # `pkgs.systemd` is in `runtimeInputs`, so `writeShellApplication` prepends it
  # to `PATH` and a case suite **cannot** stub `systemctl` by putting one in
  # front of it (CLAUDE.md). The branch this names had never run in the repo's
  # history — it needs a proxy that is up — and its failure path is the whole of
  # item 41, so both have to be reachable from a sandbox that has neither systemd
  # nor root.
  #
  # Two functions rather than two command strings, because each call needs a
  # *result*: whether the proxy is up, and whether the bounce worked.
  #
  # The restart is spelled by `./proxy-restart.nix` and not here, because the
  # rule permitting it is spelled in `host/services.nix`: sudo matches a command
  # by the path it resolves to, and with no `secure_path` on this host that is
  # the one `runtimeInputs` put on `PATH` — a store path, which no rule names
  # (NOTES item 44). The query beside it stays unqualified on purpose: it needs
  # no privilege, so nothing has to agree with it.
  proxyControl ? ''
    proxyActive() { systemctl is-active --quiet "$1"; }
    proxyRestart() { sudo ${import ./proxy-restart.nix "\"$1\""}; }
  '',
}: let
  # Verbs this file implements itself, as opposed to the ones it hands on.
  # `collect` stays a program's verb and is merely *intercepted* below, the way
  # `provision` is, to do the one thing a front end may do and a program may
  # not: read this host's record.
  #
  # **`unit` is unconditional since item 51 step 6.** It used to appear only
  # where *this host's target* had a hole for one, which made the set of verbs a
  # human may type a function of which project the host confines — and on a host
  # with two documents it would offer or withhold the verb for both according to
  # one of them. Decision 3's rule: the front end's shape is not a function of
  # any target, and what a slot's document has no place for is a refusal that
  # names it.
  ownVerbs = ["start" "stop" "created" "status" "ssh" "admin" "setup" "branches" "fetch" "record" "purpose" "policy" "unit" "handoff" "land"];

  # Verbs `all` may be applied to. A question aggregates: N answers on one screen,
  # and a failure on one capsule is a row rather than a decision. An *action* does
  # not, without a policy for the fourth of five failing — so `all start`, `all
  # stop` and `all setup` are refused until someone wants that policy decided,
  # rather than half-done by default.
  aggregable = ["status" "branches" "fetch"];

  verbs = ownVerbs ++ programVerbs;

  names = builtins.attrNames capsules.instances;

  # A leading argument is a capsule when it names one, and a verb otherwise —
  # decidable, because both lists are known here. A name that is also a verb, or
  # one called `all`, would make it a guess, so it is an eval error instead, in the
  # same spirit as `capsules.nix`'s own refusals.
  collide = lib.intersectLists (verbs ++ ["all"]) names;

  # microvm.nix's state directory. A created VM tracks it rather than the flake
  # (CLAUDE.md), and its `tap-up` is what both `microvm@<name>` and the tap unit
  # are conditioned on — so its absence is what "never created here" looks like,
  # and without asking, a start fails as a dependency error naming neither unit.
  # The justfile used to spell this; it asks `capsule <name> created` now.
  microvms = "/var/lib/microvms";

  # A capsule's identity and its way in are the same thing (NOTES item 17), and
  # the path is a pure function of a name known only at run time — so these are
  # `capsules.socketOf` applied to a shell expression and to the wildcard, and the
  # convention still has exactly one definition.
  sockOfArg = capsules.socketOf ''"$1"'';
  everySock = capsules.socketOf "*";

  # The assignment record's mechanism, injected rather than reimplemented
  # (host/record.nix). Desired state only — the observed half is `observe`.
  record = import ./record.nix {inherit pkgs;};

  # For `checkToken` alone, and it is the same bound `capsule-collect` applies to
  # the same value one layer down: a unit token written into the record here is
  # read back and substituted into a path there, so checking it in one place and
  # not the other would make the record the way round the check.
  quarantine = import ./quarantine.nix;
in
  assert collide == [] || throw "host/cli.nix: '${builtins.head collide}' is both a capsule and a verb (or `all`), so `capsule ${builtins.head collide} …` cannot be read either way";
    pkgs.writeShellApplication {
      name = "capsule";
      runtimeInputs =
        [pkgs.coreutils pkgs.systemd pkgs.openssh pkgs.socat pkgs.git pkgs.gnused]
        ++ record.inputs;
      text = ''
        declared=(${lib.concatMapStringsSep " " lib.escapeShellArg names})

        usage() {
          echo "capsule [<name>|all] <verb> [args…]"
          echo
          echo "  capsules:  ''${declared[*]}   (omitted: the one that is up)"
          echo "  lifecycle: start | stop | created       (start injects too)"
          echo "  ask:       status | branches | fetch     (these take 'all')"
          echo "  assigned:  record | purpose [text…] | policy [<name>] | unit [<token>]"
          echo "  in:        ssh [cmd…] | admin [cmd…]"
          echo "  work:      ${lib.concatStringsSep " | " programVerbs}"
          # The three coarse verbs on their own two lines, in the order they run:
          # they are one arc (NOTES item 53) and reading them beside `provision`
          # and `collect` says they are alternatives to them, which they are not.
          echo "  hand on:   setup <ref> [--unit <token>] [--purpose <text>]"
          echo "             handoff <source> --purpose <text> | land [--branch <name>]"
          echo
          echo "  status marks a slot's profile '*' where this host's document has"
          echo "  moved on from the one that slot was provisioned under, and '!'"
          echo "  where its pinned bytes are not the ones its record names."
        }

        case "''${1-}" in
          -h | --help | help)
            usage
            exit 0
            ;;
        esac

        # Name first, as everywhere here, so `capsule b provision main` cannot be
        # read the other way round (NOTES item 20). Omitted is resolved below,
        # once the helpers that can answer it exist — there is no declared
        # default any more, because a slot's name says nothing about what is in
        # it and a default is then a verb acting on a slot nobody chose.
        name=""
        if [ "$#" -gt 0 ]; then
          for d in "''${declared[@]}" all; do
            if [ "$1" = "$d" ]; then
              name="$1"
              shift
              break
            fi
          done
        fi

        # The one-off form, for a shell that is working in a capsule: same
        # variable the four programs read, checked here rather than passed on, so
        # a typo is a refusal and not a capsule this host does not have.
        if [ -z "$name" ] && [ -n "''${CAPSULE_NAME:-}" ]; then
          for d in "''${declared[@]}"; do
            [ "$CAPSULE_NAME" = "$d" ] && name="$CAPSULE_NAME"
          done
          if [ -z "$name" ]; then
            echo "capsule: CAPSULE_NAME='$CAPSULE_NAME' is not a capsule on this host." >&2
            echo "  declared: ''${declared[*]}" >&2
            exit 1
          fi
        fi

        if [ "$#" -eq 0 ]; then
          echo "capsule: no verb — what should ''${name:-a capsule} do?" >&2
          usage >&2
          exit 1
        fi
        verb="$1"
        shift

        known=no
        for v in ${lib.concatMapStringsSep " " lib.escapeShellArg verbs}; do
          [ "$verb" = "$v" ] && known=yes
        done
        if [ "$known" = no ]; then
          echo "capsule: '$verb' is neither a verb nor a capsule on this host." >&2
          usage >&2
          exit 1
        fi

        sockOf() { printf '%s' ${sockOfArg}; }
        unitOf() { printf 'microvm@%s' "$1"; }
        created() { [ -x "${microvms}/$1/current/bin/tap-up" ]; }

        # The host operator's declared choice for a slot nobody has assigned
        # (capsules.nix). Every declared slot has one — `capsules.nix` refuses at
        # eval otherwise — so there is no unmatched branch to write, and a slot
        # that is not declared never reaches here.
        slotPolicy() {
          case "$1" in
        ${lib.concatMapStringsSep "\n" (c: "    ${c.name}) echo ${
            if c.policy == null
            then "-"
            else c.policy
          } ;;")
          (builtins.attrValues capsules.instances)}
          esac
        }

        # The set an assigner may select within, per slot. The host operator's
        # other declaration, and the one that makes the verb below delegable: the
        # authority to say which project a slot holds stops short of saying what
        # it may talk to (NOTES item 36, item 25).
        slotPolicies() {
          case "$1" in
        ${lib.concatMapStringsSep "\n" (c: "    ${c.name}) echo ${lib.escapeShellArg (lib.concatStringsSep " " c.policies)} ;;")
          (builtins.attrValues capsules.instances)}
          esac
        }

        # A policy's allowlist *filename* (policies.nix). A filename and never a
        # path, so what the symlink below can be made to point at stays inside the
        # one directory the proxy has bound.
        policyFile() {
          case "$1" in
        ${lib.concatMapStringsSep "\n" (n: "    ${n}) echo ${lib.escapeShellArg policies.policies.${n}.allowlist} ;;")
          policies.everything}
          esac
        }

        # What this slot is actually running: its record when something has
        # assigned one, the operator's declaration when nothing has. The same two
        # steps the module's tmpfiles takes for the allowlist symlink, and the same
        # two `collect` fills its `--policy` from — one rule, three readers.
        effectivePolicy() {
          local p
          p=$(recordField "$1" policy)
          if [ "$p" = - ]; then slotPolicy "$1"; else echo "$p"; fi
        }

        # A unit's state in one word: `SubState` while it is active, since `running`
        # and `auto-restart` are the difference between a capsule and a crash loop,
        # and `ActiveState` otherwise. `--` for a unit this host does not have —
        # asked as `LoadState`, because `systemctl show` answers `inactive` for a unit
        # that does not exist and that would read as a stopped one.
        unitState() {
          local load
          load=$(systemctl show "$1" -P LoadState 2>/dev/null || true)
          if [ "$load" != loaded ]; then
            echo "--"
          elif [ "$(systemctl show "$1" -P ActiveState)" = active ]; then
            systemctl show "$1" -P SubState
          else
            systemctl show "$1" -P ActiveState
          fi
        }

        # What a unit said *about the thing just asked of it* — `unitTail <unit>
        # <epoch> <lines>`, printing to stderr and saying so when there is nothing.
        #
        # An unscoped `journalctl -u <unit> -n 15` is what both call sites used to
        # run, and it reports the wrong event whenever the request never reached
        # systemd: `just up a` with no tty for sudo printed `did not stay up`
        # followed by the *previous boot's* clean shutdown, which reads as a VMM
        # that crashed on this start. A stop of an already-stopped unit has the
        # same shape, and its comment calls the tail "the evidence" — of the last
        # stop, not this one. Since the moment of the request, then, and an
        # explicit sentence for empty rather than silence: **no lines is itself
        # the finding**, because a unit that logged nothing is a unit nothing was
        # done to.
        unitTail() {
          local tail
          tail=$(journalctl -u "$1" --since "@$2" -n "$3" --no-pager -o cat 2>/dev/null || true)
          if [ -n "$tail" ]; then
            printf '%s\n' "$tail" >&2
          else
            echo "  ($1 logged nothing since this was asked of it — so nothing" >&2
            echo "   happened to it: it was already in that state, or the request" >&2
            echo "   never reached systemd. That is not evidence of a failure here," >&2
            echo "   and the unscoped tail this replaced was evidence of an older one.)" >&2
          fi
        }

        # The module's copy when this capsule has a door and the host has one,
        # otherwise whatever PATH gives — which inside the repo is the devshell's,
        # the right answer for a capsule on a tap in this namespace.
        program() {
          local module="/run/current-system/sw/bin/$2"
          if [ -S "$(sockOf "$1")" ] && [ -x "$module" ]; then
            echo "$module"
          else
            echo "$2"
          fi
        }

        # `--capsule` is what this hands on, so a second one in the arguments is
        # two answers to one question — and the program's own parse takes the last,
        # which would make `capsule b provision --capsule a` succeed
        # against the wrong capsule quietly. Refuse rather than resolve.
        work() {
          local n="$1" v="$2" prog arg
          prog=$(program "$n" "capsule-$v")
          shift 2
          for arg in ''${1+"$@"}; do
            case "$arg" in
              --capsule | --capsule=*)
                echo "capsule: '$n' is already named, so drop the --capsule from here." >&2
                exit 1
                ;;
            esac
          done
          # The other half of what a front end is for, and the same shape as
          # `--policy` on a collect: the program refuses without a target and
          # this is where the host state that answers it lives (NOTES item 51,
          # decision 4). An explicit one is passed through untouched rather than
          # doubled.
          #
          # And the *bytes* that name reaches, which is item 52 step 3: a
          # provision is the act that pins a slot, so it reads what this host
          # declares now; every other verb reads what that slot was assigned
          # under. The program is handed a directory in the environment and
          # never asks which — a program that looked for a pin would be
          # choosing its own target (item 20).
          if profileVerb "$v"; then
            case "$v" in
              # A provision resolves a name and takes the directory it was
              # called in — `provisionSlot` points at the host's, because it
              # reads the same document itself for the record's `class` and for
              # the baseline question a `setup` asks after. One call sets it,
              # here and there both, and a second careful one is the thing that
              # drifts.
              provision) profileNameFor "$n" ''${1+"$@"} || exit 1 ;;
              *) slotProfileName "$n" ''${1+"$@"} || exit 1 ;;
            esac
            if [ "$profileGiven" = no ]; then
              set -- --profile "$profileName" ''${1+"$@"}
            fi
          fi
          "$prog" --capsule "$n" "$@"
        }

        # Which capsules have a way in at all. The answer to "why can I not reach
        # this one" is usually another capsule's name.
        doorsOpen() {
          shopt -s nullglob
          local s
          doors=()
          for s in ${everySock}; do
            s=''${s%/ssh.sock}
            doors+=("''${s##*/}")
          done
        }

        # Fills `ssh_argv` with the argv that reaches a capsule, and returns 1 when
        # nothing here can. Going direct reaches for `net.guest`, which is routable
        # only where the devshell shape has put a tap in *this* namespace — so that
        # tap is the question, its own precondition rather than an inference from
        # what is running. Under the module path every tap is inside somebody's
        # namespace and the attempt is a timeout that reads as a dead guest (NOTES
        # item 20).
        #
        # Asking instead whether any *other* capsule has a door is what made a status
        # cost a hundred seconds: a module-path host with every slot stopped has no
        # doors at all, which read as the devshell path, so each row bought a full
        # `ConnectTimeout` (10 s, host/guest-ssh.nix) against an address whose packets
        # leave by the default route and are never answered. The refusal below has
        # always said "the module path owns this host" and had never once fired.
        # `/sys/class/net` and not `ip link`: sysfs's net directory is per-namespace,
        # so it is the same answer with no runtime input and no fork.
        #
        # `human` keeps strict host-key checking and files each capsule's key under
        # its own name, since every guest is at the same address and would otherwise
        # fight over one `known_hosts` entry. `probe` uses the relaxation the git
        # channel uses (host/guest-ssh.nix) plus `BatchMode`, because it is asking
        # whether anything answers and must not stop for a key or a prompt.
        door() {
          local n="$1" mode="$2" sock
          sock=$(sockOf "$n")
          case "$mode" in
            human) ssh_argv=(ssh -o HostKeyAlias="capsule-$n") ;;
            probe) ssh_argv=(${lib.escapeShellArgs guestSsh.args} -o BatchMode=yes) ;;
          esac
          if [ -S "$sock" ]; then
            ssh_argv+=(-o "ProxyCommand=socat - UNIX-CONNECT:$sock")
            return 0
          fi
          doorsOpen
          [ -e /sys/class/net/${net.tap} ]
        }

        # Does the guest answer? The one per-capsule fact that is not a unit's
        # opinion of itself — every unit reported health through an evening when the
        # VM was crash-looping in the wrong namespace (CLAUDE.md), and this is the
        # question none of them can get wrong.
        answers() {
          local ssh_argv=()
          door "$1" probe || return 1
          "''${ssh_argv[@]}" "agent@${net.guest}" true >/dev/null 2>&1
        }

        # Bounded on wall clock rather than on attempts, because a failing attempt
        # costs anything from nothing (no route) to `ConnectTimeout`
        # (host/guest-ssh.nix), so N tries is not a duration. A boot to a guest
        # that answers is seconds (docs/probes.md); a minute is the generous end
        # of that, and past it something is wrong rather than slow.
        waitAnswers() {
          local deadline=$((SECONDS + 60))
          while [ "$SECONDS" -lt "$deadline" ]; do
            if answers "$1"; then return 0; fi
            sleep 1
          done
          return 1
        }

        # Where this capsule's collected work landed, if anywhere. A search rather
        # than a derivation, deliberately: which state directory holds it depends on
        # which shape did the collecting, and looking for the artefact answers that
        # without having to infer it from what is running now.
        quarantineOf() {
          local n="$1" state
          for state in "''${CAPSULE_STATE:-}" ${moduleState} "''${CAPSULE_ROOT:-$PWD}/.vm/host"; do
            [ -n "$state" ] || continue
            [ -d "$state/collect/$n.git" ] && {
              echo "$state/collect/$n.git"
              return 0
            }
          done
          return 1
        }

        refsIn() {
          git --git-dir="$1" for-each-ref --format='%(refname)' "refs/capsule/$2/" | wc -l
        }

        # **The record lives on the module path and only there.** A slot is a
        # `capsules.nix` declaration and the units around it are the module's, so an
        # assignment record for a devshell capsule would describe a slot that does
        # not exist. That is why this is `moduleState` and not `statePaths`' two
        # homes: `quarantineOf` has to *search* because either shape can write a
        # quarantine, and a record is written by exactly one.
        recordRoot=${moduleState}
        ${record.fragment}
        ${observeFragment}

        # ------------------------------------------ the pin, NOTES item 52 step 3
        #
        # A profile is **pinned** and a policy is **live**
        # (docs/contract-assignment.md): a tightened allowlist must reach a
        # running capsule, and an edit to a project's caches or its baseline must
        # *not* change what one is doing until a verb re-pins it. That distinction
        # could not fail while the documents were in the store, because nothing
        # could edit one; item 52 put them in a directory a human writes.
        #
        # What this host declares, read **once** and before anything points a
        # reader somewhere else — every slot-scoped read below moves
        # `CAPSULE_PROFILE_DIR` between two directories, so a second reading of it
        # afterwards would take a pin for the host's own. A human's override is
        # what this captures, which is the right answer: the host's documents are
        # wherever this program was told they are.
        hostProfileDir=$(profileDir)
        useHostProfiles() { export CAPSULE_PROFILE_DIR=$hostProfileDir; }

        # Where a slot's pinned bytes live: beside its record, under the same
        # root, because a pin is *desired state* — it is what this slot was
        # assigned under, and a document edited since is a different document.
        #
        # **One pin per slot**, so a re-provision onto another target leaves no
        # second document behind: retention is for the current assignment
        # (docs/contract-assignment.md), and a stale name sitting here would be
        # read the moment a record named it again.
        pinDirOf() { printf '%s/profile' "$(slotDir "$1")"; }
        pinFileOf() { printf '%s/%s.json' "$(pinDirOf "$1")" "$2"; }

        # Which directory a read about this slot comes out of: its pin when it
        # has one under that name, else what this host declares. A slot nothing
        # has assigned has none, and then the host's document *is* what it would
        # run — there is nothing to pin it against and nothing to say.
        profileDirFor() {
          if [ -f "$(pinFileOf "$1" "$2")" ]; then pinDirOf "$1"; else printf '%s' "$hostProfileDir"; fi
        }

        # `sha256:<hex>` over a file — the record's `profile_snapshot`, which is
        # the digest *of the bytes beside it*. Self-describing, because a field
        # outlives whatever wrote it.
        digestOf() { printf 'sha256:%s' "$(sha256sum < "$1" | cut -d' ' -f1)"; }

        # Copy the document a provision is taken under into the slot's own
        # directory, and answer with its digest. **Decision 3, and the whole of
        # why it costs no code**: the pin *is* a profile directory, so
        # `profileLoad` learns no second way to find bytes (item 52's own "one
        # reader, one lookup") — the second place it looks is the same place,
        # named differently.
        #
        # Aside and moved, and read-only once there: a dropped write must not
        # leave half a document that still parses (`capsule-inject`'s discipline),
        # and a pin somebody can edit in place is a pin that says nothing.
        pinProfile() {
          local n="$1" name="$2" src dir dst tmp
          src="$hostProfileDir/$name.json"
          dir=$(pinDirOf "$n")
          dst=$(pinFileOf "$n" "$name")
          [ -f "$src" ] || return 1
          mkdir -p "$dir"
          tmp="$dst.$$"
          install -m 0444 "$src" "$tmp" || return 1
          rm -f "$dir"/*.json
          mv -f "$tmp" "$dst" || return 1
          digestOf "$dst"
        }

        # Resolve which document a slot is about, and point every later reader at
        # the bytes it was assigned under — this program's own `profileLoad`, and
        # the program `work` execs, which inherits the variable.
        #
        # **The front end's act and never a program's** (item 20, and item 52's
        # own list of what must not drift): a program that went looking for a pin
        # would be choosing its own target. It is handed a directory and reads the
        # document in it that it was named. Sets `profileName`, `profileGiven` and
        # `CAPSULE_PROFILE_DIR`.
        slotProfileName() {
          local n="$1" dir
          shift
          useHostProfiles
          profileNameFor "$n" ''${1+"$@"} || return 1
          dir=$(profileDirFor "$n" "$profileName")
          export CAPSULE_PROFILE_DIR=$dir
        }

        # …and load it, which is what all but one caller wants.
        slotProfile() {
          slotProfileName "$@" || return 1
          profileLoad "$profileName"
        }

        # Which target a verb on this slot is about — the *only* place that
        # question is answered, and it is answered from host state, which is why
        # it is here (NOTES item 51, decision 4). Three sources, in the order
        # authority runs:
        #
        #   - an explicit `--profile` in the argv, which is the one-off form and
        #     wins, exactly as `--policy` does over a slot's declaration;
        #   - the slot's assignment record, written at every provision since
        #     item 29 and read by nothing until now;
        #   - and for a slot nothing has assigned, the one profile this host has
        #     rendered — refusing when there are none or several.
        #
        # That last is this front end's own latitude and not a default: it is the
        # same shape as resolving an unnamed verb to the slot that is *up*, one
        # axis over, and it degrades the right way — the moment this host renders
        # two documents, an unassigned slot has to say which. A **program** gets a
        # name or a refusal and never a guess (item 20); what a program must not
        # do is exactly what this does.
        #
        # Sets `profileName` and `profileGiven`.
        profileNameFor() {
          local n="$1"
          local -a rendered
          profileName=""
          profileGiven=no
          shift
          while [ "$#" -gt 0 ]; do
            case "$1" in
              --profile)
                profileGiven=yes
                if [ "$#" -gt 1 ]; then
                  profileName="$2"
                  shift
                fi
                ;;
              --profile=*)
                profileName="''${1#--profile=}"
                profileGiven=yes
                ;;
            esac
            shift
          done
          [ "$profileGiven" = yes ] && return 0

          profileName=$(recordField "$n" profile)
          [ "$profileName" != - ] && return 0

          mapfile -t rendered < <(profileNames)
          case "''${#rendered[@]}" in
            1) profileName=''${rendered[0]} ;;
            0)
              echo "capsule: nothing to be about — this host has rendered no" >&2
              echo "  profiles, so $(profileDir) holds no target for '$n'." >&2
              return 1
              ;;
            *)
              echo "capsule: '$n' has no assignment and this host declares more" >&2
              echo "  than one target: ''${rendered[*]}. A slot's name says nothing" >&2
              echo "  about which, so there is nothing to guess from — 'capsule $n" >&2
              echo "  provision <ref> --profile <name>' assigns it, or --profile" >&2
              echo "  for this one command." >&2
              return 1
              ;;
          esac
        }

        # Whether the target *this slot* is about scopes its out-of-band state by
        # a unit of work — `stateNeedsUnit` as a question about a document rather
        # than about the build (item 51 step 6). The predicate itself is
        # `profileNeedsUnit` and lives beside the field it reads
        # (host/profile.nix); this is only the resolution in front of it, which
        # is the part a program may not do (item 20).
        #
        # **Three answers, not two**, and the third is why this is a helper:
        #
        #   0  this slot's target scopes its state by a unit
        #   1  it does not, so a token here would scope nothing
        #   2  no target resolved at all
        #
        # A slot nothing has assigned on a host with two documents is (2), and it
        # has nothing for a token to be *wrong* against — so the callers below
        # treat it as "do not intervene" rather than as a no. Quiet, because
        # every one of them is deciding whether to fill a flag in, and the
        # program behind it makes the refusal with the better message.
        slotNeedsUnit() {
          local n="$1"
          shift
          slotProfile "$n" ''${1+"$@"} >/dev/null 2>&1 || return 2
          profileNeedsUnit
        }

        # The one interception, and it is the one thing item 20 keeps out of a
        # program: state that crosses between this host's checkout and a guest
        # is scoped by a unit of work, the program refuses without a token, and
        # reading this host's record is a front end's job (NOTES items 20, 32,
        # 42). Four verbs need it — `setup`, `provision`, `collect`, `brief` —
        # and the fourth is what made it a function rather than a fourth
        # careful copy (NOTES item 53).
        #
        # `carrier` is the argv word that means *this invocation carries state*:
        # `--state-from-host` for a provision, `--from-host` for a brief, and
        # `-` for a collect, where every invocation does. An explicit `--unit`
        # always wins, because a one-off under another unit's scope is a human's
        # call and re-recording an assignment as a side effect of reading it
        # would be this front end deciding something nobody asked it to.
        #
        # Conditioned on the *document* and never on the build (item 51 step 6):
        # filling it in for a target with no hole would hand the program a flag
        # it refuses, so a stale token on a record would make an unrelated
        # collect impossible. `slotNeedsUnit`'s third answer — no target
        # resolved at all — is "do not intervene" here, because the program
        # behind this makes that refusal with the better message.
        #
        # **Prints the two words rather than mutating argv**, so a caller that
        # must keep the argv it was given can have both: `provisionSlot` records
        # the ref that was *asked for*, and anything prepended for the program's
        # benefit would be recorded as the base a slot is pinned to.
        unitScope() {
          local n="$1" carrier="$2" a carries=no given=no token
          shift 2
          if [ "$carrier" = - ]; then carries=yes; fi
          for a in ''${1+"$@"}; do
            case "$a" in
              --unit | --unit=*) given=yes ;;
              "$carrier") carries=yes ;;
            esac
          done
          [ "$carries" = yes ] || return 0
          [ "$given" = no ] || return 0
          slotNeedsUnit "$n" ''${1+"$@"} || return 0
          token=$(recordField "$n" unit)
          [ "$token" = - ] || printf '%s\n' --unit "$token"
        }

        # The two assigner-owned fields, as writes rather than as jq spelled at
        # each call site. `unit` earns a function on its own: it is the one field
        # that is not free text — it fills a hole in the target's state paths, so
        # it is refused where the document has none and bounded where it has one
        # (NOTES item 32, host/quarantine.nix's `checkToken`) — and item 53's verb
        # 1 makes `setup` a second place both checks have to hold. Two copies of a
        # check is a check that goes on holding in one of them.
        #
        # Any argv after the token is the profile resolution's, so a `--profile`
        # on the command doing the assigning is the document asked about the hole.
        #
        # Prints the generation as `recordWrite` does, and **returns** non-zero on
        # the refusal rather than printing anything: a caller interpolating this
        # into a message would otherwise print `generation` and exit 0.
        recordUnit() {
          local n="$1" token="$2" needs=0
          shift 2
          slotNeedsUnit "$n" ''${1+"$@"} || needs=$?
          if [ "$needs" = 1 ]; then
            echo "capsule: '$n' is on profile $profileName, which declares no" >&2
            echo "  state paths with a place for one — so this token would scope" >&2
            echo "  nothing and no collect would ever read it. Nothing written." >&2
            return 1
          fi
          ${quarantine.checkToken ''"$token"'' "'unit $token'"}
          # shellcheck disable=SC2016  # `$u` is jq's, bound by --arg below
          recordWrite "$n" '.unit = $u' --arg u "$token"
        }

        # Free text, displayed and never parsed (docs/contract-assignment.md), so
        # there is nothing to check — only the one rule that it reaches jq as an
        # `--arg` value and never as filter text.
        recordPurpose() {
          # shellcheck disable=SC2016  # `$p` is jq's, bound by --arg below
          recordWrite "$1" '.purpose = $p' --arg p "$2"
        }

        # Whether a verb's program takes one at all (host/programs.nix).
        profileVerb() {
          case "$1" in
        ${lib.concatMapStringsSep "\n" (v: "    ${lib.escapeShellArg v}) return 0 ;;") profileVerbs}
            *) return 1 ;;
          esac
        }

        ${proxyControl}
        ${guestControl}

        # What the guest says about itself: one round trip, one line, the field
        # order defined in host/observe.nix and nowhere else. This *is* the
        # reachability probe — a line back is the proof — so a row costs one ssh
        # rather than one per column, which is what Plan D D5 asks for.
        observed() {
          local ssh_argv=()
          local -a args
          door "$1" probe || return 1
          # A slot with no resolvable target is a row of `-` rather than a
          # diagnostic per slot: `capsule all status` is one table, and a slot
          # nothing has assigned on a host with two targets has nothing to be
          # observed *about*. The `gen` column already says it is unassigned.
          #
          # The slot's pinned bytes, like every other read about a running
          # capsule: what is measured has to be measured against the document
          # that capsule was stood up under (item 52 step 3).
          slotProfile "$1" 2>/dev/null || return 1
          mapfile -t args < <(observeArgs | profileQuote)
          "''${ssh_argv[@]}" "agent@${net.guest}" 'bash -s' -- "''${args[@]}" < ${observe} 2>/dev/null
        }

        # A baseline stamp is **the host's** UTC, minted host-side so both ends
        # agree on the name of a run (host/baseline.nix). So this subtracts two
        # readings of one clock, and the guest-is-UTC-while-this-host-is-AEST trap
        # (CLAUDE.md) has no way in — no guest clock is involved.
        ageOf() {
          local s="$1" t0 now d
          [ "$s" = - ] && { echo -; return 0; }
          t0=$(date -u -d "''${s:0:8} ''${s:9:2}:''${s:11:2}:''${s:13:2}" +%s 2>/dev/null) \
            || { echo '?'; return 0; }
          now=$(date -u +%s)
          d=$((now - t0))
          if [ "$d" -lt 3600 ]; then echo "$((d / 60))m"
          elif [ "$d" -lt 86400 ]; then echo "$((d / 3600))h"
          else echo "$((d / 86400))d"
          fi
        }

        # Current and peak, MiB, from the unit's own cgroup — the instrument `just
        # load` settled on, for its reasons: per-process RSS double-counts the one
        # image every capsule maps, and a host-wide figure on a shared host is not
        # a capsule figure at all (docs/probes.md).
        #
        # **Peak is the column that earns its place.** Nothing hands memory back
        # until a stop — a built slot holds ~6.1 GiB whatever its ceiling
        # (docs/probes.md#the-first-cold-build-at-a-6144-ceiling) — so `stop` is a
        # resource verb and this is how a human picks which idle slot to reap.
        #
        # The empty-`ControlGroup` guard is not defensive noise: `systemctl show`
        # answers empty for a dead unit, and `/sys/fs/cgroup` + "" is the **root**
        # cgroup, whose `memory.current` is the whole host. A stopped capsule would
        # otherwise report 40 GiB of its own.
        memOf() {
          local cg cur peak
          cg=$(systemctl show "$(unitOf "$1")" -P ControlGroup 2>/dev/null || true)
          [ -n "$cg" ] || { echo -; return 0; }
          cg="/sys/fs/cgroup$cg"
          [ -r "$cg/memory.current" ] || { echo -; return 0; }
          cur=$(($(cat "$cg/memory.current") / 1048576))
          if [ -r "$cg/memory.peak" ]; then
            peak=$(($(cat "$cg/memory.peak") / 1048576))
          else
            peak='?'
          fi
          echo "$cur/$peak"
        }

        # One format, one header, one row, and **no column that comes and goes**
        # (item 51, decision 3): this is one table for N slots over M targets, so
        # a shape that were a function of any one of them would change between
        # two runs on one host, silently, with no rebuild to notice it.
        statusFmt='%-7s %-7s %-10s %-8s %-8s %-4s %-7s %-9s %-5s %-8s %-4s %-4s %-11s %-4s %-3s %-9s %-7s %-6s %s\n'

        statusHeader() {
          # shellcheck disable=SC2059
          printf "$statusFmt" \
            capsule created vm proxy relay door answers \
            head dirty baseline age disk 'mem cur/peak' refs gen profile policy unit purpose
        }

        yesno() { if "$@"; then echo yes; else echo no; fi; }

        # Which document this slot reads, and whether the host's copy has moved
        # on from it — item 52 step 3's marker, and the reader that makes
        # `profile_snapshot` worth writing. Bytes rather than a digest alone is
        # the contract's own decision: a digest detects a drift it cannot undo,
        # so the pin is what a slot runs and the digest is what says nobody has
        # been at it (docs/contract-assignment.md).
        #
        #   name    the bytes this slot reads are this host's document
        #   name*   pinned, and this host's document has changed since — an
        #           edit to target.nix that no verb has carried to this slot
        #   name!   pinned, and the bytes are not the ones the record names
        #
        # A column that is always printed, whatever any slot resolves to (item
        # 51, decision 3): a marker that appeared only on a host with a drifted
        # document would be the front end's shape changing with a file.
        profileCell() {
          local n="$1" pin host
          useHostProfiles
          profileNameFor "$n" 2>/dev/null || { echo -; return 0; }
          pin=$(pinFileOf "$n" "$profileName")
          if [ ! -f "$pin" ]; then
            echo "$profileName"
            return 0
          fi
          if [ "$(recordField "$n" profile_snapshot)" != - ] \
            && [ "$(recordField "$n" profile_snapshot)" != "$(digestOf "$pin")" ]; then
            echo "$profileName!"
            return 0
          fi
          # A document this host no longer renders is a drift like any other,
          # and the pin is why the slot keeps working through it.
          host=-
          if [ -f "$hostProfileDir/$profileName.json" ]; then
            host=$(digestOf "$hostProfileDir/$profileName.json")
          fi
          if [ "$host" != "$(digestOf "$pin")" ]; then echo "$profileName*"; else echo "$profileName"; fi
        }

        statusRow() {
          local n="$1" q refs=- line ans=no
          local head=- dirty=- baseline=- stamp=- disk=-
          if q=$(quarantineOf "$n"); then refs=$(refsIn "$q" "$n"); fi
          # A dead guest is a row of `-` and never a hang, which is the discipline
          # `answers` established and the reason every field has an unknown value.
          if line=$(observed "$n") && [ -n "$line" ]; then
            ans=yes
            IFS=$'\t' read -r head dirty baseline stamp disk <<<"$line"
          fi
          # `gen`, `unit` and `purpose` are the *desired* side, read from the record
          # rather than measured — the two objects stay apart on one row, which is the
          # whole point of keeping them apart in the first place
          # (docs/contract-assignment.md). `purpose` is last because it is free text
          # this repo never parses, so it is the one column with no width. `unit` sits
          # beside it and is not free text: it is what the next collect will scope
          # the exhibit by, so a `-` there is a collect that will refuse.
          # shellcheck disable=SC2059
          printf "$statusFmt" \
            "$n" \
            "$(yesno created "$n")" \
            "$(unitState "$(unitOf "$n")")" \
            "$(unitState "capsule-proxy-$n")" \
            "$(unitState "capsule-ssh-relay-$n")" \
            "$(yesno test -S "$(sockOf "$n")")" \
            "$ans" \
            "''${head:0:9}" "$dirty" "$baseline" "$(ageOf "$stamp")" "$disk" \
            "$(memOf "$n")" \
            "$refs" \
            "$(recordField "$n" generation)" \
            "$(profileCell "$n")" \
            "$(effectivePolicy "$n")" "$(recordField "$n" unit)" \
            "$(recordField "$n" purpose)"
        }

        # After a provision, and never instead of one: the record follows the fact,
        # so a failed provision leaves the previous base pinned rather than a claim
        # about work that did not land.
        #
        # The two halves of `base` come from different places on purpose. `base.ref`
        # is what was *asked for* and this front end has it in argv; `base.oid` is
        # what that ref *resolved to*, read back out of the guest rather than
        # resolved a second time here. That is the contract's rule — nothing
        # resolves against a ref twice — and it is also less code: the guest's HEAD
        # after a successful provision **is** that commit, and `observed` already
        # reads it, in full, for exactly this.
        #
        # **Written by the front end and never by `capsule-provision`.** That keeps
        # the program deterministic and free of host state, which is item 20's rule
        # and item 28's. The cost is real and stated rather than hidden: running
        # `capsule-provision --capsule a <ref>` directly provisions without
        # recording, the same way it bypasses every other thing a front end does.
        recordProvisioned() {
          local n="$1" prof="$2" ref="''${3--}" oid snap
          # The profile this provision was *taken under*, not one resolved a
          # second time: the caller has it, and re-resolving after the record has
          # been written would read the field this is about to set. Out of the
          # directory `provisionSlot` pointed at — this host's, because a
          # provision is the act that decides what the slot's own copy will be.
          profileLoad "$prof" || return 1
          # The pin, and it is written **before** the record and independently of
          # it: the bytes are what every later verb on this slot reads, and the
          # code has already landed under them, so a guest that has since gone
          # quiet must not leave the slot reading a document the host may edit
          # tomorrow. The digest goes into the record's own write below, which is
          # the half that follows the fact.
          snap=$(pinProfile "$n" "$prof") || {
            echo "capsule: provisioned, but '$prof' could not be pinned into" >&2
            echo "  $(pinDirOf "$n") — so this slot reads whatever $hostProfileDir" >&2
            echo "  holds at the time, which is the drift a pin exists to stop." >&2
            return 1
          }
          # `guestHead` and not a second `observed | cut`: the same question is
          # `verifyExhibit`'s, and it is the one thing here that needs a live
          # capsule, so it is asked in one place and substituted in one place.
          #
          # `|| oid=""` and not a bare assignment: `observed` returns 1 for a
          # guest that does not answer, `set -o pipefail` carries that out of the
          # pipeline, and `set -e` then killed this function — silently, since
          # `observed` sends the transport's own stderr to /dev/null. So the
          # branch below had never once been taken, and a provision whose code
          # landed against a guest that had since gone quiet exited 1 saying
          # nothing at all. Found by the first case ever to run this path
          # (host/policy-cases.nix); it needs a stub, which is why a live host
          # never found it.
          oid=$(guestHead "$n") || oid=""
          if [ -z "$oid" ] || [ "$oid" = - ]; then
            echo "capsule: provisioned, but the guest did not answer for its HEAD, so" >&2
            echo "  no base was recorded. 'capsule $n status', then provision again." >&2
            return 0
          fi
          # SC2016: `$ref`, `$oid`, `$profile`, `$class` and `$snap` are *jq*
          # variables, bound by the `--arg`/`--argjson` below. Not expanding in
          # the shell is the entire point — a value interpolated into a filter
          # would be jq code.
          # shellcheck disable=SC2016
          recordWrite "$n" \
            '.base = {ref: $ref, oid: $oid} | .profile = $profile | .class = $class
             | .profile_snapshot = $snap' \
            --arg ref "$ref" \
            --arg oid "$oid" \
            --arg profile "$prof" \
            --arg snap "$snap" \
            --argjson class "$(printf '{"mem":%s,"vcpu":%s}' "$profile_mem" "$profile_vcpu")" \
            > /dev/null
        }

        # What provisioning a slot is, in one place: the scope this host fills
        # in, the profile the push is taken under, the push, and the record.
        # `setup` is a provision with two more steps after it (NOTES item 53's
        # verb 1), so it calls this rather than repeating the four — which it
        # did, minus the scope, which is how `capsule <slot> setup <ref>
        # --state-from-host` came to be refused where the same flags on a
        # provision succeeded.
        #
        # Leaves the document loaded, because the caller's next question —
        # whether this target declares a baseline — is about that same document
        # and resolving it a second time would read the record this has just
        # written.
        provisionSlot() {
          local n="$1" prof
          local -a scope=()
          shift
          mapfile -t scope < <(unitScope "$n" --state-from-host ''${1+"$@"})
          # Resolved before the program runs and held in a local, because after
          # it the record this reads from is the record this provision writes.
          # Out of the host's directory and not the slot's pin: a provision is
          # what *sets* the pin, so reading the old one here would stand the new
          # assignment up on the document the last one was taken under (item 52
          # step 3).
          useHostProfiles
          profileNameFor "$n" ''${1+"$@"} || return 1
          prof=$profileName
          profileLoad "$prof" || return 1
          work "$n" provision ''${scope[@]+"''${scope[@]}"} ''${1+"$@"}
          # The profile this provision was taken under, then the *original*
          # argv: two readers of one argv, and only the program wanted the
          # addition.
          #
          # The profile argument is **not** optional and was missing here from
          # step 4 until step 6: `recordProvisioned` takes `<name> <profile>
          # <ref>`, so the ref was landing in the profile's place and every
          # `capsule <slot> provision <ref>` died on `no profile named '<ref>'`
          # after the code had already been pushed. Nothing caught it because
          # this path needs a guest and the step that added the parameter spent
          # its smoke test on a status and a collect.
          recordProvisioned "$n" "$prof" ''${1+"$@"}
        }

        # What collecting a slot is, in one place, for the same reason
        # `provisionSlot` exists: `handoff` and `land` both begin with one, and
        # the two flags a collect is filled with are host state a program may
        # not read (NOTES items 20, 32, 36).
        collectSlot() {
          local n="$1" given=no a
          local -a unitArgs
          shift
          for a in ''${1+"$@"}; do
            case "$a" in
              --policy | --policy=*) given=yes ;;
            esac
          done
          if [ "$given" = no ]; then
            set -- --policy "$(effectivePolicy "$n")" ''${1+"$@"}
          fi
          mapfile -t unitArgs < <(unitScope "$n" - ''${1+"$@"})
          work "$n" collect ''${unitArgs[@]+"''${unitArgs[@]}"} ''${1+"$@"}
        }

        # Which checkout a slot's work belongs to, and where a fetch puts it.
        # `CAPSULE_REPO` before the profile's `path` because that is what the
        # git channel's own lookup does (host/git-channel.nix). Sets `repo` and
        # leaves the document loaded.
        repoFor() {
          slotProfile "$1" || return 1
          repo=''${CAPSULE_REPO:-$profile_path}
        }

        # **Each half is fetched on its own and answered for on its own**, and
        # the reason is that they can disagree: a slot's second assignment
        # diverges from its first in the code half, while the state half
        # fast-forwards straight across the reassignment, because the guest
        # parents each snapshot on the ref on its own volume and a provision
        # does not touch it (NOTES item 50). One refspec is then refused and the
        # other taken, and one exit status for the pair says only that something
        # went wrong — so the repository is left holding one assignment's code
        # beside another's state, under two names that say they belong together,
        # by a verb that exited 1 and named neither.
        #
        # The remedy printed is the archive rather than a force: `+` here would
        # make the first assignment unreachable in the one place it is durable,
        # which is what the slot-keyed namespace already costs the quarantine
        # (NOTES item 50). `handoff` is the one caller that runs that remedy
        # itself, because it is the one that knows a reassignment is happening.
        fetchSlot() {
          local n="$1" q half ns
          local -a refused=()
          if ! q=$(quarantineOf "$n"); then
            echo "nothing collected yet — capsule $n collect" >&2
            return 1
          fi
          repoFor "$n" || return 1
          for half in code state; do
            case "$half" in
              code) ns=${quarantine.codeRefsOf ''"$n"''} ;;
              *) ns=${quarantine.stateRefsOf ''"$n"''} ;;
            esac
            if git -C "$repo" fetch "$q" "$ns/*:$ns/*"; then
              echo "capsule $n: $half: landed"
            else
              echo "capsule $n: $half: refused" >&2
              refused+=("$half")
            fi
          done
          [ "''${#refused[@]}" -eq 0 ] && return 0
          echo "  the quarantine's refs are not a descendant of this repo's, which is" >&2
          echo "  a second assignment to '$n' meeting the first one's (NOTES item 50)." >&2
          echo "  Archive what this repo holds under" >&2
          echo "  refs/capsule/$n/gen/$(recordField "$n" generation)/, then fetch again —" >&2
          echo "  forcing loses the first assignment where it is durable." >&2
          return 1
        }

        # Is the exhibit the guest? The whole of NOTES item 53: a quarantine is
        # a snapshot and nothing said how old one was against its source, so a
        # collect four hours stale and a current one were indistinguishable at
        # the point somebody merged. Sets `exhibitTip`.
        #
        # **No override.** A `--stale` for "I know it is behind" is the
        # remembered `--force` again, and believing an exhibit was current is
        # the failure this exists for; the remedy is a collect, which both
        # callers run themselves. The corollary is a real constraint and is
        # named rather than discovered: the comparison is against the guest's
        # own HEAD and there is nowhere else to get it, so a slot that has been
        # stopped since its last collect cannot be verified at all.
        #
        # Membership rather than a single named ref, because the branch a guest
        # commits on is the guest's business (NOTES item 18) and this file has
        # never held its name: what is asserted is that the head the guest is at
        # is a ref this collect took, which is the same fact without learning a
        # name.
        verifyExhibit() {
          local n="$1" q head oid
          exhibitTip=""
          q=$(quarantineOf "$n") || {
            echo "capsule: nothing has been collected from '$n', so there is no" >&2
            echo "  exhibit to check against it." >&2
            return 1
          }
          head=$(guestHead "$n") || head=""
          if [ -z "$head" ] || [ "$head" = - ]; then
            echo "capsule: '$n' did not answer for its HEAD, so nothing can say whether" >&2
            echo "  what was collected from it is what it holds now. Start it —" >&2
            echo "  'capsule $n start' — and run this again. There is no override:" >&2
            echo "  an exhibit believed current is NOTES item 53 itself." >&2
            return 1
          fi
          while read -r oid; do
            [ "$oid" = "$head" ] && exhibitTip="$oid"
          done < <(git --git-dir="$q" for-each-ref \
            --format='%(objectname)' ${quarantine.codeRefsOf ''"$n"''}/)
          if [ -z "$exhibitTip" ]; then
            echo "capsule: '$n' is at ''${head:0:9} and the collect that just ran did not" >&2
            echo "  take it — so the guest has moved since, or the collect did not" >&2
            echo "  reach it. What the quarantine holds:" >&2
            git --git-dir="$q" for-each-ref \
              --format='    %(objectname:short)  %(refname:short)  %(committerdate:relative)' \
              ${quarantine.codeRefsOf ''"$n"''}/ >&2
            return 1
          fi
        }

        # What the exhibit says about the worktree it was taken from, read from
        # the exhibit and never from the guest (NOTES item 53, decision 2): the
        # state commit's message carries the porcelain count and its tree
        # carries `.capsule/dirty.diff`, so this needs no second round trip and
        # gives the same answer if the source goes down in between.
        #
        # **Two classes with two fates, and only one of them is a refusal.**
        # Untracked-but-not-ignored files are staged as content into the state
        # tree, so they travel and a destination really holds them; a modified
        # *tracked* file is in no code ref and no path list, so it cannot
        # travel and is captured as a diff nobody applied. Sets `dirtyTracked`
        # (files in that diff) and `dirtyTotal` (the exhibit's own `dirty:`,
        # which counts both). A target that declares no state paths collects no
        # state half at all, and that is `-` rather than a zero.
        exhibitDirty() {
          local n="$1" q commit
          dirtyTracked=-
          dirtyTotal=-
          q=$(quarantineOf "$n") || return 0
          commit=$(git --git-dir="$q" for-each-ref --sort=-committerdate --count=1 \
            --format='%(objectname)' ${quarantine.stateRefsOf ''"$n"''}/)
          [ -n "$commit" ] || return 0
          dirtyTotal=$(git --git-dir="$q" log -1 --format=%B "$commit" \
            | sed -n 's/^dirty: //p')
          [ -n "$dirtyTotal" ] || dirtyTotal=-
          dirtyTracked=$(git --git-dir="$q" cat-file -p "$commit:.capsule/dirty.diff" 2>/dev/null \
            | grep -c '^diff --git ' || true)
        }

        # Rename a slot's refs in the human's repo out of the way of the
        # assignment about to replace them, keyed by the generation being
        # superseded (NOTES item 53, decision 3). The half a human still does by
        # hand after a `fetch` refuses — `handoff` is where it stops being a
        # thing somebody remembers.
        #
        # **In the repository and not in the quarantine**: the quarantine's copy
        # of a superseded assignment is lost to the next forced collect and that
        # is correct — a quarantine is what a capsule sent back, not a place
        # state lives (NOTES item 42) — so the durable copy belongs where the
        # human works.
        #
        # One transaction, and `create` refuses a name that is taken: a
        # generation is only superseded once, and two archives under one name
        # would be the collision this exists to avoid arriving by another door.
        archiveRefs() {
          local n="$1" g="$2" ref oid rest moved=0
          local -a plan=()
          while read -r ref oid; do
            [ -n "$ref" ] || continue
            rest=''${ref#refs/capsule/"$n"/}
            plan+=("create refs/capsule/$n/gen/$g/$rest $oid" "delete $ref $oid")
            moved=$((moved + 1))
          done < <(git -C "$repo" for-each-ref --format='%(refname) %(objectname)' \
            ${quarantine.codeRefsOf ''"$n"''}/ ${quarantine.stateRefsOf ''"$n"''}/)
          [ "$moved" -gt 0 ] || return 0
          if [ "$g" = - ]; then
            echo "capsule: '$n' holds $moved ref(s) in $repo and no record to key an" >&2
            echo "  archive by, so there is no name for them that cannot collide." >&2
            echo "  Move them by hand, under refs/capsule/$n/gen/<n>/." >&2
            return 1
          fi
          printf '%s\n' "''${plan[@]}" | git -C "$repo" update-ref --stdin || {
            echo "capsule: could not archive '$n' refs under refs/capsule/$n/gen/$g/ —" >&2
            echo "  nothing was moved, and nothing may be forced over them." >&2
            return 1
          }
          echo "capsule $n: archived $moved ref(s) under refs/capsule/$n/gen/$g/"
        }

        # What is inside a capsule's namespace — its own `ip_forward=0`, the tap's
        # input drop, the drops between capsules — cannot be read from here at all:
        # `ip netns exec` wants CAP_SYS_ADMIN and a status must not need root. So this
        # does not print "unknown"; it names the witness. `capsule-perimeter-guard`
        # audits every namespace every 10 s and exits — taking every proxy's egress
        # with it — the moment one of them stops holding, so its being active *is* the
        # per-namespace verdict, for all capsules at once.
        # `guard` and not `state`: the record's fragment reads a `$state` in this
        # scope (above), and a local of the same name here would shadow it for
        # anything this function later grew to call. Cheaper to rename than to
        # remember.
        perimeter() {
          local guard
          guard=$(unitState capsule-perimeter-guard)
          if [ "$guard" = "--" ]; then
            echo "perimeter: no guard unit — the module path is not installed on this host."
            echo "  The devshell shape's answer is 'capsule-net verify'."
            return 0
          fi
          echo "perimeter: capsule-perimeter-guard is $guard — it audits every namespace"
          echo "  every 10 s, and nothing else here can see inside one."
          journalctl -u capsule-perimeter-guard -n 1 --no-pager -o cat 2>/dev/null \
            | sed 's/^/  /' || true
        }

        # `capsule ssh a` is the transposition to expect, because verb-first is
        # what git and systemctl teach. It is also *legal*: `ssh` and the four
        # programs take a passthrough argument, so `a` is something a caller
        # could genuinely mean to run in the guest. So this says what it looks
        # like and never reorders — a front end that silently accepts both argv
        # shapes has both readings baked into it, which is the smell NOTES item
        # 20 is about. Always succeeds, so a call site is one word.
        nameFirstHint() {
          [ "$#" -gt 0 ] || return 0
          for d in "''${declared[@]}" all; do
            if [ "$1" = "$d" ]; then
              echo "  Name first: you may mean 'capsule $1 $verb'." >&2
              return 0
            fi
          done
        }

        # Which capsule an unnamed verb means: the one that is up, and only when
        # exactly one is. A slot's name carries no meaning, so there is nothing to
        # default to — but the capsule a human is working in is nearly always the
        # only one running, and asking the host is cheap. Resolving from host
        # state is a *front end's* latitude and belongs here rather than in the
        # four programs, for the same reason picking between their two copies
        # does: a program that guesses has the guess in its store path (NOTES item
        # 20). Up means a way in or a running VMM — the devshell shape has
        # neither, so there it is a refusal and `CAPSULE_NAME` is the answer.
        if [ -z "$name" ]; then
          up=()
          for d in "''${declared[@]}"; do
            if [ -S "$(sockOf "$d")" ] \
              || [ "$(unitState "$(unitOf "$d")")" = running ]; then
              up+=("$d")
            fi
          done
          case "''${#up[@]}" in
            1) name="''${up[0]}" ;;
            0)
              echo "capsule: no capsule is up, so an unnamed '$verb' means nothing here." >&2
              echo "  Name one — ''${declared[*]} — or set CAPSULE_NAME." >&2
              nameFirstHint ''${1+"$@"}
              exit 1
              ;;
            *)
              echo "capsule: ''${up[*]} are up, so an unnamed '$verb' is ambiguous." >&2
              echo "  Name one, or 'all' if it is a question." >&2
              nameFirstHint ''${1+"$@"}
              exit 1
              ;;
          esac
        fi

        targets=("$name")
        if [ "$name" = all ]; then
          aggregable=no
          for v in ${lib.concatMapStringsSep " " lib.escapeShellArg aggregable}; do
            [ "$verb" = "$v" ] && aggregable=yes
          done
          if [ "$aggregable" = no ]; then
            echo "capsule: 'all $verb' is an action on every capsule, not a question about" >&2
            echo "  them, and what to do when the third of five fails is undecided. Name one:" >&2
            echo "  ''${declared[*]}" >&2
            exit 1
          fi
          targets=("''${declared[@]}")
        fi

        case "$verb" in
          created) created "$name" ;;

          start)
            created "$name" || {
              echo "capsule '$name' has never been created on this host." >&2
              echo "  Creating resolves its name as a flake attribute (NOTES item 21), so it" >&2
              echo "  needs the flake: 'just up $name' in the checkout, or" >&2
              echo "  'sudo microvm -c $name -f <flake>'." >&2
              exit 1
            }
            unit=$(unitOf "$name")
            # A host rebuild that changes this unit's drop-ins does not reach a unit
            # that is already running or mid-restart: systemd keeps the loaded
            # fragment and only records NeedDaemonReload, and a reload cannot swap it
            # while a job is pending. What starts then is the *bare* microvm.nix
            # template — Restart=always, no namespace, the old ExecStop — so
            # firecracker runs in the root namespace, where its tap is not, and
            # EPERMs in a five-second loop (CLAUDE.md). Stop first, reload while it is
            # stopped, then start.
            if [ "$(systemctl show "$unit" -P NeedDaemonReload)" = yes ]; then
              echo "$name: unit changed on disk since it was loaded — reloading first"
              sudo systemctl stop "$unit"
              sudo systemctl daemon-reload
            fi
            # The status is kept rather than discarded: `|| true` alone made every
            # failure read as the VMM's, including the ones where systemd was never
            # reached at all — no tty for sudo is the one that costs a minute, since
            # the tail underneath then describes some earlier boot. The assertion is
            # still the better error when the start *did* run, so both are reported
            # and the epoch is taken first, to scope what follows to this attempt.
            asked=$(date +%s)
            rc=0
            sudo systemctl start "$unit" || rc=$?
            # A start returns once the VMM is exec'd, and a VMM that cannot open its
            # tap is gone again in milliseconds — which is how a crash loop reads as a
            # successful start. So ask again, after long enough for that to have
            # happened.
            sleep 2
            if [ "$(systemctl show "$unit" -P SubState)" != running ]; then
              if [ "$rc" -ne 0 ]; then
                echo "capsule $name: the start itself failed — systemctl exited $rc," >&2
                echo "  so this may be a request that never reached the unit rather than" >&2
                echo "  a VMM that died." >&2
              else
                echo "capsule $name: did not stay up —" >&2
              fi
              unitTail "$unit" "$asked" 15
              exit 1
            fi
            # A running VMM is not the promise. Credentials and secrets are a push
            # over ssh (host/inject.nix) and `$HOME` is on the volume that
            # freshness deletes, so a capsule that has only been *started* is one
            # nobody can work in — and at N that is a ritual per capsule rather
            # than a step someone forgets once (docs/plan-c-multi-capsule.md,
            # "Secrets and home at N"). Write-if-absent, so this is a no-op on a
            # capsule that already has them, and a payload with no source on this
            # host says so and is skipped.
            if ! waitAnswers "$name"; then
              echo "capsule $name: up, but the guest did not answer ssh within a minute," >&2
              echo "  so nothing was injected. 'capsule $name status' for what is running," >&2
              echo "  and 'capsule $name inject' once it answers." >&2
              exit 1
            fi
            work "$name" inject
            journalctl -u capsule-perimeter-guard -n 1 --no-pager -o cat 2>/dev/null || true
            ;;

          stop)
            # Not a power cut: the unit's `ExecStop` asks the guest to reboot, it
            # unmounts and then its reset exits the VMM (NOTES item 11). The journal
            # tail is the evidence — `reboot requested` and then a return, rather than
            # 120 s of TimeoutStopSec. Scoped to this stop, since a unit that was
            # already down logs nothing and the unscoped tail would hand back the
            # *previous* stop's evidence for this one.
            unit=$(unitOf "$name")
            asked=$(date +%s)
            sudo systemctl stop "$unit"
            unitTail "$unit" "$asked" 12
            ;;

          status)
            statusHeader
            for t in "''${targets[@]}"; do statusRow "$t"; done
            echo
            perimeter
            ;;

          branches)
            for t in "''${targets[@]}"; do
              if [ ''${#targets[@]} -gt 1 ]; then echo "== $t"; fi
              if q=$(quarantineOf "$t"); then
                git --git-dir="$q" for-each-ref \
                  --sort=-committerdate \
                  --format='%(objectname:short)  %(refname:short)  %(committerdate:relative)  %(subject)' \
                  "refs/capsule/$t/"
              else
                echo "nothing collected yet — capsule $t collect"
              fi
            done
            ;;

          # The second step: quarantine -> the repo you work in, once you have looked.
          # A capsule's refs are already namespaced by its name, so N quarantines
          # fetch into one repo without colliding, and **which** repo is a per-slot
          # answer: two slots on two targets fetch into two checkouts, which is the
          # whole of item 51. Both of those, and the two halves, are `fetchSlot`'s
          # — `handoff` and `land` fetch as part of a larger act.
          #
          # A sweep keeps going and fails at the end, for `aggregable`'s reason:
          # N answers on one screen, and a slot that cannot fetch is a line rather
          # than a decision about the others.
          fetch)
            fetchRc=0
            for t in "''${targets[@]}"; do
              fetchSlot "$t" || fetchRc=1
            done
            exit "$fetchRc"
            ;;

          ssh | admin)
            user=agent
            [ "$verb" = admin ] && user=root
            # In case echo got stuck on. Silent, or it lands in a captured command.
            [ "$verb" = ssh ] && { stty sane 2>/dev/null || true; }
            ssh_argv=()
            door "$name" human || {
              echo "no relay socket for '$name', and the module path owns this host." >&2
              # An empty list is the common case now that this refusal fires at all
              # — nothing up is exactly when it used to go direct and time out — so
              # it gets a sentence rather than a blank one.
              if [ ''${#doors[@]} -eq 0 ]; then
                echo "  no capsule has a door: none of them are up." >&2
              else
                echo "  capsules with a door: ''${doors[*]}" >&2
              fi
              echo "  'capsule $name start' if it should be running." >&2
              exit 1
            }
            exec "''${ssh_argv[@]}" "$user@${net.guest}" ''${1+"$@"}
            ;;

          # The three setup problems in the only order they work in (docs/design.md),
          # which is also what makes a fresh capsule usable. Ends attached to the
          # baseline, so it finishes when the build does — Ctrl-C leaves that run
          # going in the guest and `capsule <name> baseline` re-attaches.
          #
          # The inject is still here although `start` does it: a guest that was
          # started by hand, or that has rebooted since, has had no start of ours.
          # Write-if-absent makes the repeat a no-op rather than a second answer.
          setup)
            # `--unit <token>` and `--purpose <text>` are **this verb's own record
            # writes**, and the last unbuilt piece of NOTES item 53's verb 1:
            # assigning a slot is one act, and a token and a sentence that need two
            # more commands after it are a habit rather than a verb — which is the
            # class of thing that item exists about.
            #
            # Both are taken *out* of the argv rather than passed through. The
            # sentence has to be, since `capsule-provision` has no such flag; the
            # token could have been passed on and is not, because the record is
            # where a scope comes from everywhere else. `unitScope` fills it back
            # in below when the invocation carries state, so there is one spelling
            # of that question and `capsule <slot> setup <ref> --unit <token>`
            # with no state half **records the assignment** instead of being
            # refused by a program that has nothing to scope with it
            # (host/git-channel.nix: a `--unit` without `--state-from-host` is an
            # argument error, correctly).
            #
            # Written **before** the push, for two reasons that point the same
            # way: the refusals a token draws — a document with no hole, a name
            # that is not opaque — belong in front of code landing in a capsule,
            # and the provision's own scope is read off the record this writes. A
            # provision that then fails leaves a slot recorded as assigned to work
            # it is not holding, which is what `base` and `generation` are for and
            # is already true of `capsule <slot> unit`.
            setupArgs=()
            unitToken=""
            unitGiven=no
            purpose=""
            purposeGiven=no
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --unit)
                  shift
                  [ "$#" -gt 0 ] || {
                    echo "capsule: --unit takes a token." >&2
                    exit 1
                  }
                  unitToken="$1"
                  unitGiven=yes
                  ;;
                --unit=*)
                  unitToken="''${1#--unit=}"
                  unitGiven=yes
                  ;;
                --purpose)
                  shift
                  [ "$#" -gt 0 ] || {
                    echo "capsule: --purpose takes a sentence." >&2
                    exit 1
                  }
                  purpose="$1"
                  purposeGiven=yes
                  ;;
                --purpose=*)
                  purpose="''${1#--purpose=}"
                  purposeGiven=yes
                  ;;
                *) setupArgs+=("$1") ;;
              esac
              shift
            done
            if [ "$unitGiven" = yes ]; then
              gen=$(recordUnit "$name" "$unitToken" \
                ''${setupArgs[@]+"''${setupArgs[@]}"}) || exit 1
              echo "capsule $name: unit $unitToken, generation $gen"
            fi
            if [ "$purposeGiven" = yes ]; then
              echo "capsule $name: purpose recorded, generation" \
                "$(recordPurpose "$name" "$purpose")"
            fi

            # The provision, its scope and its record are `provisionSlot`'s, and
            # this branch is the two steps after them. It used to be four lines
            # of its own that had drifted from `provision)`'s by exactly the
            # interception (item 53), and the document it leaves loaded is what
            # the baseline question below reads (item 51 step 6).
            provisionSlot "$name" ''${setupArgs[@]+"''${setupArgs[@]}"}
            work "$name" inject
            # Skipped rather than refused when the target declares none: a setup
            # with no baseline is finished, not failed. `capsule-baseline` would
            # say the same thing and exit 1 saying it, which is the right answer
            # to a human who asked for a baseline and the wrong one here.
            if [ -n "$profile_baseline" ]; then
              work "$name" baseline
            else
              echo "capsule $name: profile $profileName declares no baseline, so setup ends here."
            fi
            ;;

          # Explicit, rather than falling through to the program dispatcher below,
          # because provisioning is the one verb that changes what a slot *is* and
          # so the one that has something to record.
          provision)
            # The scope it carries reaches provision because the brief moved
            # inside it (NOTES item 47), so the scoping had to follow — a flag
            # whose value the front end fills in one place and not the other is
            # a scope that silently never applies. `setup` was that other place
            # until item 53, which is why the four steps are one function now.
            provisionSlot "$name" ''${1+"$@"}
            ;;

          # Stand this slot up on that slot's finished exhibit — NOTES item 53's
          # middle verb, and the only one of the three that is machinery which
          # did not exist. It is a **composition** and lives here rather than in
          # a `capsule-handoff`, because it reads this host's state three times
          # (which slot is a source, which quarantine holds it, which record
          # carries the token) and that is exactly what a program may not do
          # (item 20).
          #
          # The order is the whole of it, and every step is a rule some hand-run
          # sequence supplied on the day this was proposed:
          #
          #   1. collect the source, then **verify the exhibit against its
          #      guest** — the failure this item is written from;
          #   2. refuse on a modified tracked file, read from the exhibit
          #      (decision 2);
          #   3. fetch the source, because `capsule-provision` resolves its ref
          #      in the human's repo and the tip has to be there to be pushed;
          #   4. **archive the destination before anything is forced** — collect
          #      it, fetch it, and rename what it had under its own generation
          #      (decision 3);
          #   5. clear the destination's stale outbound state chain, which a
          #      provision does not touch and which would otherwise refuse the
          #      incoming one for a reason that reads as a bug (item 50);
          #   6. **one** provision, carrying its state, because on a target
          #      whose refresh commits there is no moment after a provision when
          #      a brief can land (item 47);
          #   7. carry the source's `unit`, and require a `purpose` — the token
          #      is mechanical and the sentence is the human's (item 29).
          handoff)
            src=""
            purpose=""
            purposeGiven=no
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --purpose)
                  shift
                  [ "$#" -gt 0 ] || {
                    echo "capsule: --purpose takes a sentence." >&2
                    exit 1
                  }
                  purpose="$1"
                  purposeGiven=yes
                  ;;
                --purpose=*)
                  purpose="''${1#--purpose=}"
                  purposeGiven=yes
                  ;;
                -*)
                  echo "capsule: handoff takes a source capsule and --purpose <text>," >&2
                  echo "  and '$1' is neither. Everything else about the assignment is" >&2
                  echo "  the source's." >&2
                  exit 1
                  ;;
                *)
                  [ -z "$src" ] || {
                    echo "capsule: handoff takes one source — '$src' and '$1' are two." >&2
                    exit 1
                  }
                  src="$1"
                  ;;
              esac
              shift
            done
            if [ -z "$src" ]; then
              echo "capsule: handoff needs a source: 'capsule $name handoff <source>" >&2
              echo "  --purpose <text>' stands '$name' up on what <source> has done." >&2
              echo "  Capsules here: ''${declared[*]}" >&2
              exit 1
            fi
            srcKnown=no
            for d in "''${declared[@]}"; do
              [ "$src" = "$d" ] && srcKnown=yes
            done
            if [ "$srcKnown" = no ]; then
              echo "capsule: '$src' is not a capsule on this host, and a handoff is" >&2
              echo "  between two of them: ''${declared[*]}" >&2
              exit 1
            fi
            if [ "$src" = "$name" ]; then
              echo "capsule: '$name' cannot be handed its own work — a handoff is a" >&2
              echo "  second capsule beginning on what the first finished." >&2
              exit 1
            fi
            # The sentence is the human's and guessing it would be this front
            # end deciding something nobody asked it to (NOTES item 29). The
            # token below is the opposite case and is copied without asking.
            if [ "$purposeGiven" = no ] || [ -z "$purpose" ]; then
              echo "capsule: handoff needs --purpose <text> — what '$name' is for." >&2
              echo "  It is free text nothing here parses, and it is the one thing" >&2
              echo "  about this assignment that is not derivable from '$src'." >&2
              exit 1
            fi
            # Two slots on two targets would fetch into two checkouts and push
            # one project's code into another's capsule. Refused here rather than
            # discovered at the push, and naming both documents.
            slotProfileName "$src" || exit 1
            srcProfile="$profileName"
            slotProfileName "$name" || exit 1
            if [ "$srcProfile" != "$profileName" ]; then
              echo "capsule: '$src' is on profile $srcProfile and '$name' is on" >&2
              echo "  $profileName, so there is no work to hand between them." >&2
              exit 1
            fi

            echo "capsule $name: handoff from $src — collecting $src"
            collectSlot "$src" || exit 1
            verifyExhibit "$src" || exit 1
            exhibitDirty "$src"
            if [ "$dirtyTracked" != - ] && [ "$dirtyTracked" -gt 0 ]; then
              echo "capsule: '$src' has $dirtyTracked modified tracked file(s) that cannot" >&2
              echo "  travel — they are in no code ref and no path list, so the exhibit" >&2
              echo "  carries them as .capsule/dirty.diff, a record of a worktree rather" >&2
              echo "  than part of one. Standing '$name' up on it would be a checkout" >&2
              echo "  nobody ever had. Commit them in '$src', then hand off." >&2
              echo "  (Its uncommitted *untracked* work travelled as content: the" >&2
              echo "  exhibit's own count is $dirtyTotal.)" >&2
              exit 1
            fi
            echo "capsule $name: $src is at ''${exhibitTip:0:9} and the exhibit holds it"
            fetchSlot "$src" || exit 1

            # What '$name' had, before anything is forced over it. Skipped
            # rather than refused for a slot nothing has ever assigned: there is
            # no generation to key an archive by because there is nothing to
            # archive.
            if [ "$(recordField "$name" generation)" = - ]; then
              echo "capsule $name: nothing has been assigned here, so there is nothing to archive"
            else
              collectSlot "$name" || exit 1
              fetchSlot "$name" || exit 1
              repoFor "$name" || exit 1
              archiveRefs "$name" "$(recordField "$name" generation)" || exit 1
            fi

            # The destination's own chain, which the incoming one is not rooted
            # in. A provision does not touch it and the brief inside one is not
            # forced, so leaving it here refuses the push for a reason that
            # reads as a bug (NOTES item 50's fast-forward half). The stages are
            # the ones the collect above just took, which is the guest's answer
            # of seconds ago rather than a second round trip.
            stages=()
            if q=$(quarantineOf "$name"); then
              mapfile -t stages < <(git --git-dir="$q" for-each-ref \
                --format='%(refname:lstrip=-1)' ${quarantine.stateRefsOf ''"$name"''}/)
            fi
            if [ "''${#stages[@]}" -gt 0 ]; then
              echo "capsule $name: dropping its own state chain (''${stages[*]}) — the" \
                "incoming one is rooted elsewhere"
              if ! dropped=$(guestDropState "$name" "''${stages[@]}"); then
                echo "capsule: could not drop ${stateRefPrefix}/* in '$name' — the state" >&2
                echo "  half of the provision would be refused as a non-fast-forward," >&2
                echo "  naming a cause that is not the cause. Nothing was provisioned." >&2
                exit 1
              fi
              [ -z "$dropped" ] || printf '  dropped %s\n' "$dropped"
            fi

            # One provision, carrying its state: there is no "after" on a target
            # whose refresh commits (NOTES item 47), so the state half is a flag
            # and never a second command. The force is what decision 3's archive
            # above made safe.
            provisionSlot "$name" "$exhibitTip" --force --state "$src" || exit 1

            # Mechanical, and only when there is one: the token scopes the same
            # unit of work in the same target, so a second capsule on it collects
            # under the same scope. The bare write and not `recordUnit`: this
            # token was checked where it was authored, and its two checks would
            # fire here *after* the provision, which is the one place a refusal
            # cannot be acted on.
            token=$(recordField "$src" unit)
            if [ "$token" != - ]; then
              # shellcheck disable=SC2016  # `$u` is jq's, bound by --arg below
              recordWrite "$name" '.unit = $u' --arg u "$token" > /dev/null
            fi
            echo "capsule $name: on ''${exhibitTip:0:9} from $src, unit $token," \
              "generation $(recordPurpose "$name" "$purpose")"
            ;;

          # Accept the result — NOTES item 53's third verb, and it **stops at
          # refs**. Which branch a result belongs on, whether a closed unit
          # reopens and how two reviews reconcile are the target's governance
          # (item 18's direction, applied to naming); what this owns is the
          # comparison the failure was written from and a report of where the
          # work sits against the repo as it is now.
          #
          # `--branch <name>` is permitted because a name arriving as an argument
          # is a value, and two rules keep it one: there is **no default**, since
          # a default branch name is `target.nix` leaking back through a program
          # (items 28, 36), and it **refuses an existing name** rather than
          # updating it, so nothing a land does can lose a commit.
          land)
            branch=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --branch)
                  shift
                  [ "$#" -gt 0 ] || {
                    echo "capsule: --branch takes a name." >&2
                    exit 1
                  }
                  branch="$1"
                  ;;
                --branch=*) branch="''${1#--branch=}" ;;
                *)
                  echo "capsule: land takes only --branch <name>, and '$1' is not one." >&2
                  echo "  Which branch a result belongs on is the target's to say, so" >&2
                  echo "  there is no default and the refs are the answer without one." >&2
                  exit 1
                  ;;
              esac
              shift
            done

            collectSlot "$name" || exit 1
            verifyExhibit "$name" || exit 1
            fetchSlot "$name" || exit 1
            repoFor "$name" || exit 1

            if [ -n "$branch" ]; then
              # `update-ref <ref> <new> ""` is create-only — the empty old value
              # is the assertion that the name is free — so this is one atomic
              # refusal rather than a check and a race.
              if ! git -C "$repo" update-ref "refs/heads/$branch" "$exhibitTip" ""; then
                echo "capsule: $repo already has a branch '$branch', and a land never" >&2
                echo "  moves one — that is how nothing it does can lose a commit." >&2
                echo "  The work is at refs/capsule/$name/heads/*; name a free branch," >&2
                echo "  or merge from there." >&2
                exit 1
              fi
              echo "capsule $name: $branch is at ''${exhibitTip:0:9} in $repo"
            fi

            exhibitDirty "$name"
            if [ "$dirtyTracked" != - ] && [ "$dirtyTracked" -gt 0 ]; then
              echo "capsule $name: $dirtyTracked modified tracked file(s) did not travel —" \
                "the exhibit carries them as .capsule/dirty.diff, applied by nothing"
            fi

            # The report is what earns the verb, and it can be written without
            # knowing anything about the target: the repo's current HEAD is a
            # fact about that repo rather than a value of ours, so this names the
            # branch it found without ever having chosen one.
            if ! headOid=$(git -C "$repo" rev-parse --verify --quiet HEAD); then
              echo "capsule $name: $repo has no commit on HEAD, so there is nothing to" \
                "compare ''${exhibitTip:0:9} against"
              exit 0
            fi
            headName=$(git -C "$repo" symbolic-ref --quiet --short HEAD) \
              || headName="a detached HEAD at ''${headOid:0:9}"
            read -r only_head only_work < <(git -C "$repo" rev-list --left-right --count \
              "$headOid...$exhibitTip")
            echo "capsule $name: against $headName — $only_work commit(s) here that it" \
              "has not, $only_head there that this has not"
            if conflicts=$(git -C "$repo" merge-tree --write-tree --name-only \
              --no-messages "$headOid" "$exhibitTip"); then
              echo "  and a merge would not conflict"
            else
              echo "  and a merge would conflict on:"
              printf '%s\n' "$conflicts" | tail -n +2 | sed '/^$/d;s/^/    /'
            fi
            ;;

          # The whole record, for when a column is not enough. `jq .` rather than
          # raw bytes: it is a document and reading it should not require knowing
          # that.
          record)
            recordRead "$name" | jq .
            ;;

          # The one assigner-owned field with a use before D2 exists: free text,
          # displayed and never parsed (docs/contract-assignment.md). `"$*"` so a
          # sentence needs no quoting, and it reaches jq as an `--arg` value rather
          # than as filter text.
          purpose)
            if [ "$#" -eq 0 ]; then
              recordField "$name" purpose
            else
              echo "capsule $name: generation $(recordPurpose "$name" "$*")"
            fi
            ;;

          # What this slot may talk to, and what may come back out of it — the one
          # assigner-owned field that is a **control** rather than a label, which
          # is why it is a selection from a declared set and never a name an
          # assigner authors (NOTES item 36, item 25). Two writes and a restart:
          #
          #   - the record, so the slot says what it was told to be;
          #   - the allowlist symlink, in the directory the proxy can reach and
          #     the record's is not, so the proxy serves it without ever reading
          #     the record — the front end resolves, which is a front end's
          #     latitude and never a program's;
          #   - a restart of that slot's proxy, because the proxy renders its
          #     config at start. The cost is stated rather than avoided: that
          #     slot's egress drops for the length of a restart, and a tightening
          #     nobody applied is not a control.
          #
          # The first two go under one `flock` (host/record.nix's `recordAlso`),
          # because a record and a perimeter that disagree is a perimeter nobody
          # can read.
          policy)
            if [ "$#" -eq 0 ]; then
              effectivePolicy "$name"
              exit 0
            fi
            [ "$#" -eq 1 ] || {
              echo "capsule: policy takes one name — it selects from the set this" >&2
              echo "  slot declares: $(slotPolicies "$name")" >&2
              exit 1
            }
            want="$1"
            allowed=no
            read -ra declaredSet <<<"$(slotPolicies "$name")"
            # A distinct refusal, not a special case of the one below: a slot with
            # an empty set is a declaration nobody can satisfy, and reporting the
            # name as not in an empty list would blame the argument for a fault
            # in the declaration.
            if [ "''${#declaredSet[@]}" -eq 0 ]; then
              echo "capsule: '$name' declares no policies, so there is nothing for" >&2
              echo "  an assigner to select. A slot's set is the host operator's," >&2
              echo "  in capsules.nix (NOTES item 36)." >&2
              exit 1
            fi
            for p in "''${declaredSet[@]}"; do
              [ "$want" = "$p" ] && allowed=yes
            done
            if [ "$allowed" = no ]; then
              echo "capsule: '$name' may not take policy '$want'." >&2
              echo "  Its declared set is: $(slotPolicies "$name")" >&2
              echo "  Widening that set is the host operator's, in capsules.nix —" >&2
              echo "  which is the whole point of the set existing (NOTES item 36)." >&2
              exit 1
            fi
            # The module path's, and only there: the record already is
            # (`recordRoot` above), and the symlink is a path the units bind. The
            # devshell shape names its policy per run, on `capsule-host --policy
            # <name>`, which is the same selection with no state to keep.
            #
            # Two variables and one refusal, because a copy that has one and not
            # the other is a copy that would write half of a selection. Both are
            # the module's wrap (host/services.nix), so either being unset means
            # the same thing.
            if [ -z "''${CAPSULE_POLICY_DIR:-}" ] || [ -z "''${CAPSULE_ALLOWLIST_DIR:-}" ]; then
              echo "capsule: no policy directory, so this copy cannot re-point a" >&2
              echo "  slot's allowlist. The verb is the module path's — run" >&2
              echo "  /run/current-system/sw/bin/capsule $name policy $want." >&2
              echo "  On the devshell path a policy is named per run instead:" >&2
              echo "  capsule-host --policy $want." >&2
              exit 1
            fi
            # Inside the record's lock, before the document is written, so a
            # failure here leaves both halves as they were (host/record.nix).
            # `-T`, not just `-n`: without it a link name that is somehow a real
            # directory means `ln` writes *inside* it and reports success, which
            # is a re-point that never happened and a proxy still on the old
            # policy.
            #
            # `$1` is the slot and `$2` is its *record* directory, which this
            # deliberately does not use: the link lives outside the record's
            # directory so that a proxy can traverse to it without being able to
            # reach the record at all (NOTES item 39, host/services.nix's
            # `allowlistDir`).
            #
            # **The restart is in here too, and that is NOTES item 41.** It is
            # what makes a selection true of the wire, and it is the one step that
            # can fail for a reason outside this program — it needs root. Left
            # after the document, its failure writes the record and the link and
            # leaves the proxy serving the old policy, which is fail-*open* for
            # the narrowing case that a policy verb mostly exists for. The hook's
            # contract is exactly the one that fixes it: a hook that fails leaves
            # nothing moved. So the link is put back by hand on the way out —
            # nothing else knows what it was — and `recordWrite` returns non-zero
            # with no document written.
            #
            # Everything here prints to **stderr**. The hook runs inside
            # `gen=$(recordWrite …)`, so a line on stdout is captured as part of
            # the generation.
            recordAlso() {
              local link="$CAPSULE_ALLOWLIST_DIR/$1" prev
              prev=$(readlink -- "$link" 2> /dev/null || true)
              ln -sfT "$CAPSULE_POLICY_DIR/$(policyFile "$want")" "$link" || return 1
              # A proxy that is not running has nothing to reload: it renders its
              # config at start, so the next start is already the new policy.
              if ! proxyActive "$proxy"; then
                echo "  $proxy is not running; it will render $want when it starts" >&2
                return 0
              fi
              echo "  restarting $proxy — egress is down for the length of it" >&2
              proxyRestart "$proxy" && return 0
              echo "capsule: $proxy would not restart, so the selection was undone." >&2
              echo "  It needs a privilege this program does not have; a host that" >&2
              echo "  has not granted it would otherwise leave '$name' reading" >&2
              echo "  '$want' everywhere while the proxy still serves" >&2
              echo "  $(effectivePolicy "$name") (NOTES item 41)." >&2
              if [ -n "$prev" ]; then ln -sfT "$prev" "$link"; else rm -f "$link"; fi
              return 1
            }
            proxy="capsule-proxy-$name"
            # shellcheck disable=SC2016  # `$p` is jq's, bound by --arg below
            gen=$(recordWrite "$name" '.policy = $p' --arg p "$want") || {
              echo "capsule: '$name' still holds $(effectivePolicy "$name") — the" >&2
              echo "  record, its allowlist link and its proxy move together and" >&2
              echo "  none of them moved." >&2
              exit 1
            }
            echo "capsule $name: policy $want, generation $gen"
            ;;

          # Which unit of work this slot is driving, and the only assigner-owned
          # field here that is *not* free text: it fills the hole in the target's
          # state paths, so it reaches a collect as part of a path and is bounded
          # accordingly (NOTES item 32, host/quarantine.nix's `checkToken`).
          # `purpose` says what the slot is for and this says what the exhibit is
          # of — a display string and a scope, which is why they are two fields
          # and not one.
          #
          # `"$1"` and not `"$*"`, for the same reason: a sentence is a purpose
          # and a token is not.
          #
          # **Always a verb since step 6**, where it used to exist only on a host
          # whose own target had a hole. Reading is never refused, because the
          # column it reads prints for every slot; **writing** is, when the slot's
          # document has no place for the token — a recorded scope that no collect
          # will ever substitute is the same lie as a `--unit` that scopes
          # nothing, one layer up. And only when a document actually resolves: a
          # slot nothing has assigned has no target for a token to be wrong
          # against, which is `slotNeedsUnit`'s third answer.
          unit)
            if [ "$#" -eq 0 ]; then
              recordField "$name" unit
            else
              [ "$#" -eq 1 ] || {
                echo "capsule: unit takes one token — it names a unit of work and" >&2
                echo "  goes into the middle of a path. 'capsule $name purpose …'" >&2
                echo "  is the field that takes a sentence." >&2
                exit 1
              }
              # Both checks and the write are `recordUnit`'s, because `setup` is
              # the second place they have to hold (item 53's verb 1). Captured
              # rather than interpolated, so a refusal stops the message.
              gen=$(recordUnit "$name" "$1") || exit 1
              echo "capsule $name: generation $gen"
            fi
            ;;

          # Intercepted for exactly one kind of thing, and it is the thing item 20
          # keeps out of a program: a collect is scoped and bounded by host state,
          # the program refuses without either, and reading this host's state is a
          # front end's job. Two fields, one shape — an explicit flag always wins,
          # because a one-off collect under another policy or of another unit's
          # state is a human's call, and re-recording the slot's assignment as a
          # side effect of reading it would be this front end deciding something
          # nobody asked it to.
          #
          # Neither *absence* is handled here: `capsule-collect`'s own refusals
          # already name the remedies, and a second copy of them here would be a
          # second thing to keep true.
          # The policy is filled so an unassigned slot ingests under exactly the
          # one its proxy is already serving (host/services.nix, NOTES item 36),
          # and the scope from the same record, unconditionally — every collect
          # takes state out of a guest. Both are `collectSlot`'s, because
          # `handoff` and `land` begin with one.
          collect)
            collectSlot "$name" ''${1+"$@"}
            ;;

          # Intercepted for the same one thing, in the one direction that needs
          # it: state taken from *this host's checkout* is scoped by a unit the
          # program may not read (NOTES items 20, 42), exactly as a collect's is.
          # A brief from a capsule is not — the exhibit in that quarantine was
          # already scoped when it was collected, and re-scoping it here would be
          # a second answer to a question that is settled.
          brief)
            mapfile -t unitArgs < <(unitScope "$name" --from-host ''${1+"$@"})
            work "$name" brief ''${unitArgs[@]+"''${unitArgs[@]}"} ''${1+"$@"}
            ;;

          *) work "$name" "$verb" ''${1+"$@"} ;;
        esac
      '';
    }
