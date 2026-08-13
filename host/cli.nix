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
  target,
  capsules,
  # The host->guest ssh relaxation, for the *reachability probe* only
  # (host/guest-ssh.nix). The human's own door keeps the strict default, because a
  # human is there to read the warning; a probe asking "is anything listening"
  # would otherwise report a rotated host key as an unreachable guest.
  guestSsh,
  # Which `capsule-<verb>` programs this host actually has. `baseline` is absent
  # when the target declares none (host/programs.nix), and an unknown verb should
  # say so rather than exec a command that is not there.
  programVerbs,
  # The guest-side half of a status, as a store path pushed over the door
  # (host/observe.nix). A path and not a set of guest paths, deliberately: this
  # file asks a capsule what is true and does not know what `/work` is.
  observe,
}: let
  # Verbs this file implements itself, as opposed to the ones it hands on.
  ownVerbs = ["start" "stop" "created" "status" "ssh" "admin" "setup" "branches" "fetch" "record" "purpose"];

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

  # Where the module keeps quarantines. On the module path this is not a guess at
  # all — that copy is wrapped with `CAPSULE_STATE` and `CAPSULE_REPO` from the
  # host's own options (host/services.nix), the same wrapper the two stateful
  # programs get, and `CAPSULE_STATE` is the first thing tried below. This is the
  # *devshell* copy's guess at where the module put things, which is the case that
  # actually needs one: inside the repo, asked about a capsule the units own. The
  # convention itself has one definition (host/git-channel.nix's `statePaths`).
  moduleState = "/var/lib/capsule";

  # A capsule's identity and its way in are the same thing (NOTES item 17), and
  # the path is a pure function of a name known only at run time — so these are
  # `capsules.socketOf` applied to a shell expression and to the wildcard, and the
  # convention still has exactly one definition.
  sockOfArg = capsules.socketOf ''"$1"'';
  everySock = capsules.socketOf "*";

  # The assignment record's mechanism, injected rather than reimplemented
  # (host/record.nix). Desired state only — the observed half is `observe`.
  record = import ./record.nix {inherit pkgs;};
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
          echo "  assigned:  record | purpose [text…]"
          echo "  in:        ssh [cmd…] | admin [cmd…]"
          echo "  work:      ${lib.concatStringsSep " | " programVerbs} | setup [ref]"
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
          local n="$1" prog arg
          prog=$(program "$n" "capsule-$2")
          shift 2
          for arg in ''${1+"$@"}; do
            case "$arg" in
              --capsule | --capsule=*)
                echo "capsule: '$n' is already named, so drop the --capsule from here." >&2
                exit 1
                ;;
            esac
          done
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
        # this host has doors but not this capsule's — which means the module path
        # owns it and this capsule is simply not up. Going direct then reaches for a
        # `net.guest` whose tap is inside somebody's namespace, and that is a timeout
        # that reads as a dead guest (NOTES item 20).
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
          [ ''${#doors[@]} -eq 0 ]
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

        # What the guest says about itself: one round trip, one line, the field
        # order defined in host/observe.nix and nowhere else. This *is* the
        # reachability probe — a line back is the proof — so a row costs one ssh
        # rather than one per column, which is what Plan D D5 asks for.
        observed() {
          local ssh_argv=()
          door "$1" probe || return 1
          "''${ssh_argv[@]}" "agent@${net.guest}" 'bash -s' < ${observe} 2>/dev/null
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

        statusFmt='%-7s %-7s %-10s %-8s %-8s %-4s %-7s %-9s %-5s %-8s %-4s %-4s %-11s %-4s %-3s %s\n'

        statusHeader() {
          # shellcheck disable=SC2059
          printf "$statusFmt" \
            capsule created vm proxy relay door answers \
            head dirty baseline age disk 'mem cur/peak' refs gen purpose
        }

        yesno() { if "$@"; then echo yes; else echo no; fi; }

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
          # `gen` and `purpose` are the *desired* side, read from the record rather
          # than measured — the two objects stay apart on one row, which is the
          # whole point of keeping them apart in the first place
          # (docs/contract-assignment.md). `purpose` is last because it is free text
          # this repo never parses, so it is the one column with no width.
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
          local n="$1" ref="''${2--}" oid
          oid=$(observed "$n" | cut -f1)
          if [ -z "$oid" ] || [ "$oid" = - ]; then
            echo "capsule: provisioned, but the guest did not answer for its HEAD, so" >&2
            echo "  no base was recorded. 'capsule $n status', then provision again." >&2
            return 0
          fi
          # SC2016: `$ref`, `$oid`, `$profile` and `$class` are *jq* variables,
          # bound by the `--arg`/`--argjson` below. Not expanding in the shell is
          # the entire point — a value interpolated into a filter would be jq code.
          # shellcheck disable=SC2016
          recordWrite "$n" \
            '.base = {ref: $ref, oid: $oid} | .profile = $profile | .class = $class' \
            --arg ref "$ref" \
            --arg oid "$oid" \
            --arg profile ${lib.escapeShellArg target.name} \
            --argjson class ${lib.escapeShellArg (builtins.toJSON {inherit (target.sizes) mem vcpu;})} \
            > /dev/null
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
            # `|| true` because the assertion below is the better error: it reports
            # what the VMM said rather than that a start returned nonzero.
            sudo systemctl start "$unit" || true
            # A start returns once the VMM is exec'd, and a VMM that cannot open its
            # tap is gone again in milliseconds — which is how a crash loop reads as a
            # successful start. So ask again, after long enough for that to have
            # happened.
            sleep 2
            if [ "$(systemctl show "$unit" -P SubState)" != running ]; then
              echo "capsule $name: did not stay up —" >&2
              journalctl -u "$unit" -n 15 --no-pager -o cat >&2
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
            # 120 s of TimeoutStopSec.
            unit=$(unitOf "$name")
            sudo systemctl stop "$unit"
            journalctl -u "$unit" -n 12 --no-pager -o cat 2>/dev/null || true
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
          # `CAPSULE_REPO` before `target.path` because that is what the git channel's
          # own default does (host/git-channel.nix), and a capsule's refs are already
          # namespaced by its name, so N quarantines fetch into one repo without
          # colliding.
          fetch)
            for t in "''${targets[@]}"; do
              if q=$(quarantineOf "$t"); then
                git -C "''${CAPSULE_REPO:-${target.path}}" fetch "$q" \
                  'refs/capsule/*:refs/capsule/*'
              else
                echo "nothing collected yet — capsule $t collect" >&2
              fi
            done
            ;;

          ssh | admin)
            user=agent
            [ "$verb" = admin ] && user=root
            # In case echo got stuck on. Silent, or it lands in a captured command.
            [ "$verb" = ssh ] && { stty sane 2>/dev/null || true; }
            ssh_argv=()
            door "$name" human || {
              echo "no relay socket for '$name', and the module path owns this host." >&2
              echo "  capsules with a door: ''${doors[*]}" >&2
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
            work "$name" provision ''${1+"$@"}
            recordProvisioned "$name" ''${1+"$@"}
            work "$name" inject
            ${lib.optionalString (builtins.elem "baseline" programVerbs) ''work "$name" baseline''}
            ;;

          # Explicit, rather than falling through to the program dispatcher below,
          # because provisioning is the one verb that changes what a slot *is* and
          # so the one that has something to record.
          provision)
            work "$name" provision ''${1+"$@"}
            recordProvisioned "$name" ''${1+"$@"}
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
              # shellcheck disable=SC2016  # `$p` is jq's, bound by --arg below
              echo "capsule $name: generation $(recordWrite "$name" \
                '.purpose = $p' --arg p "$*")"
            fi
            ;;

          *) work "$name" "$verb" ''${1+"$@"} ;;
        esac
      '';
    }
