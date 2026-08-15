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
  stateNeedsUnit,
  # The guest-side half of a status, as a store path pushed over the door
  # (host/observe.nix). A path and not a set of guest paths, deliberately: this
  # file asks a capsule what is true and does not know what `/work` is.
  observe,
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
  # `unit` only exists where the target's policy has a hole for one (NOTES item
  # 32) — `collect` stays a program's verb and is merely *intercepted* below, the
  # way `provision` is, to do the one thing a front end may do and a program may
  # not: read this host's record.
  ownVerbs =
    ["start" "stop" "created" "status" "ssh" "admin" "setup" "branches" "fetch" "record" "purpose" "policy"]
    ++ lib.optional stateNeedsUnit "unit";

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
          echo "  assigned:  record | purpose [text…] | policy [<name>]${lib.optionalString stateNeedsUnit " | unit [<token>]"}"
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

        ${proxyControl}

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

        statusFmt='%-7s %-7s %-10s %-8s %-8s %-4s %-7s %-9s %-5s %-8s %-4s %-4s %-11s %-4s %-3s %-7s ${lib.optionalString stateNeedsUnit "%-6s "}%s\n'

        statusHeader() {
          # shellcheck disable=SC2059
          printf "$statusFmt" \
            capsule created vm proxy relay door answers \
            head dirty baseline age disk 'mem cur/peak' refs gen policy ${lib.optionalString stateNeedsUnit "unit "}purpose
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
            "$(effectivePolicy "$n")" ${lib.optionalString stateNeedsUnit ''"$(recordField "$n" unit)"''} \
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

          ${lib.optionalString stateNeedsUnit ''
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
              ${quarantine.checkToken ''"$1"'' "'unit $1'"}
              # shellcheck disable=SC2016  # `$u` is jq's, bound by --arg below
              echo "capsule $name: generation $(recordWrite "$name" \
                '.unit = $u' --arg u "$1")"
            fi
            ;;

        ''}

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
          collect)
            policyGiven=no
            ${lib.optionalString stateNeedsUnit "unitGiven=no"}
            for a in ''${1+"$@"}; do
              case "$a" in
                --policy | --policy=*) policyGiven=yes ;;
                ${lib.optionalString stateNeedsUnit "--unit | --unit=*) unitGiven=yes ;;"}
              esac
            done
            # So an unassigned slot ingests under exactly the policy its proxy is
            # already serving (host/services.nix, NOTES item 36).
            if [ "$policyGiven" = no ]; then
              set -- --policy "$(effectivePolicy "$name")" ''${1+"$@"}
            fi
            ${lib.optionalString stateNeedsUnit ''
          recordedUnit=$(recordField "$name" unit)
          if [ "$unitGiven" = no ] && [ "$recordedUnit" != - ]; then
            set -- --unit "$recordedUnit" ''${1+"$@"}
          fi
        ''}
            work "$name" collect ''${1+"$@"}
            ;;

          *) work "$name" "$verb" ''${1+"$@"} ;;
        esac
      '';
    }
