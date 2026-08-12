# `capsule` — the human's front end, and nothing else.
#
# NOTES item 20 decided the naming ahead of this: which capsule a program means
# is `--capsule <name>`, else `CAPSULE_NAME`, else `capsules.default`, and the
# transport is derived from the name rather than baked into a store path. That
# left a front end with exactly three jobs: resolve a name, pick the copy of a
# program that can reach it, and exec. It owns no transport, no socket path of
# its own and no second implementation of anything below it.
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
  # Which `capsule-<verb>` programs this host actually has. `baseline` is absent
  # when the target declares none (host/programs.nix), and an unknown verb should
  # say so rather than exec a command that is not there.
  programVerbs,
}: let
  # Verbs this file implements itself, as opposed to the ones it hands on.
  ownVerbs = ["start" "stop" "created" "ssh" "admin" "setup"];

  verbs = ownVerbs ++ programVerbs;

  names = builtins.attrNames capsules.instances;

  # A leading argument is a capsule when it names one, and a verb otherwise —
  # decidable, because both lists are known here. A name that is also a verb
  # would make it a guess, so it is an eval error instead, in the same spirit as
  # `capsules.nix`'s own refusals.
  collide = lib.intersectLists verbs names;

  # microvm.nix's state directory, and the only host path this file knows. A
  # created VM tracks it rather than the flake (CLAUDE.md), and its `tap-up` is
  # what both `microvm@<name>` and the tap unit are conditioned on — so its
  # absence is what "never created here" looks like, and without asking, a start
  # fails as a dependency error naming neither unit. The justfile used to spell
  # this; it asks `capsule <name> created` now.
  microvms = "/var/lib/microvms";

  # A capsule's identity and its way in are the same thing (NOTES item 17), and
  # the path is a pure function of a name known only at run time — so these are
  # `capsules.socketOf` applied to a shell expression and to the wildcard, and the
  # convention still has exactly one definition.
  guestSock = capsules.socketOf ''"$name"'';
  everyGuestSock = capsules.socketOf "*";
in
  assert collide == [] || throw "host/cli.nix: '${builtins.head collide}' is both a capsule and a verb, so `capsule ${builtins.head collide} …` cannot be read either way";
    pkgs.writeShellApplication {
      name = "capsule";
      runtimeInputs = [pkgs.coreutils pkgs.systemd pkgs.openssh pkgs.socat];
      text = ''
        declared=(${lib.concatMapStringsSep " " lib.escapeShellArg names})

        usage() {
          echo "capsule [<name>] <verb> [args…]"
          echo
          echo "  capsules:  ''${declared[*]}   (default ${capsules.default})"
          echo "  lifecycle: start | stop | created"
          echo "  in:        ssh [cmd…] | admin [cmd…]"
          echo "  work:      ${lib.concatStringsSep " | " programVerbs} | setup [ref]"
        }

        case "''${1-}" in
          -h | --help | help)
            usage
            exit 0
            ;;
        esac

        # Name first, as everywhere here, so `capsule capsule-b provision main`
        # cannot be read the other way round (NOTES item 20). Omitted means the
        # default, which is a value rather than a habit (`capsules.nix`).
        name=${lib.escapeShellArg capsules.default}
        if [ "$#" -gt 0 ]; then
          for d in "''${declared[@]}"; do
            if [ "$1" = "$d" ]; then
              name="$1"
              shift
              break
            fi
          done
        fi

        if [ "$#" -eq 0 ]; then
          echo "capsule: no verb — what should '$name' do?" >&2
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

        sock=${guestSock}
        unit="microvm@$name"

        created() { [ -x "${microvms}/$name/current/bin/tap-up" ]; }

        # The module's copy when this capsule has a door and the host has one,
        # otherwise whatever PATH gives — which inside the repo is the devshell's,
        # the right answer for a capsule on a tap in this namespace.
        program() {
          local module="/run/current-system/sw/bin/$1"
          if [ -S "$sock" ] && [ -x "$module" ]; then
            echo "$module"
          else
            echo "$1"
          fi
        }

        # `--capsule` is what this hands on, so a second one in the arguments is
        # two answers to one question — and the program's own parse takes the last,
        # which would make `capsule capsule-b provision --capsule capsule` succeed
        # against the wrong capsule quietly. Refuse rather than resolve.
        work() {
          local prog arg
          prog=$(program "capsule-$1")
          shift
          for arg in ''${1+"$@"}; do
            case "$arg" in
              --capsule | --capsule=*)
                echo "capsule: '$name' is already named, so drop the --capsule from here." >&2
                exit 1
                ;;
            esac
          done
          "$prog" --capsule "$name" "$@"
        }

        # The interactive door, and deliberately not `host/guest-ssh.nix`'s
        # relaxation: that one turns host-key checking off because the git channel
        # cannot stop for a changed key, and here a human is present to read the
        # warning. `HostKeyAlias` files each capsule's key under its own name, since
        # every guest is at the same address and would otherwise fight over one
        # `known_hosts` entry.
        guest_ssh() {
          local user="$1"
          shift
          if [ -S "$sock" ]; then
            exec ssh -o HostKeyAlias="capsule-$name" \
              -o ProxyCommand="socat - UNIX-CONNECT:$sock" \
              "$user@${net.guest}" ''${1+"$@"}
          fi
          # No socket for this capsule but one for another means the module path
          # owns this host and this capsule is simply not up. Going direct reaches
          # for a `net.guest` whose tap is inside somebody's namespace, which is a
          # timeout that reads as a dead guest — the failure the four programs were
          # taught to refuse (NOTES item 20).
          shopt -s nullglob
          local doors=() s
          for s in ${everyGuestSock}; do
            s=''${s%/ssh.sock}
            doors+=("''${s##*/}")
          done
          if [ ''${#doors[@]} -gt 0 ]; then
            echo "no relay socket for '$name', and the module path owns this host." >&2
            echo "  capsules with a door: ''${doors[*]}" >&2
            echo "  'capsule $name start' if it should be running." >&2
            exit 1
          fi
          exec ssh "$user@${net.guest}" ''${1+"$@"}
        }

        case "$verb" in
          created) created ;;

          start)
            created || {
              echo "capsule '$name' has never been created on this host." >&2
              echo "  Creating resolves its name as a flake attribute (NOTES item 21), so it" >&2
              echo "  needs the flake: 'just up $name' in the checkout, or" >&2
              echo "  'sudo microvm -c $name -f <flake>'." >&2
              exit 1
            }
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
            journalctl -u capsule-perimeter-guard -n 1 --no-pager -o cat 2>/dev/null || true
            ;;

          stop)
            # Not a power cut: the unit's `ExecStop` asks the guest to reboot, it
            # unmounts and then its reset exits the VMM (NOTES item 11). The journal
            # tail is the evidence — `reboot requested` and then a return, rather than
            # 120 s of TimeoutStopSec.
            sudo systemctl stop "$unit"
            journalctl -u "$unit" -n 12 --no-pager -o cat 2>/dev/null || true
            ;;

          ssh)
            # In case echo got stuck on. Silent, or it lands in a captured command.
            stty sane 2>/dev/null || true
            guest_ssh agent ''${1+"$@"}
            ;;

          admin) guest_ssh root ''${1+"$@"} ;;

          # The three setup problems in the only order they work in (docs/design.md),
          # which is also what makes a fresh capsule usable. Ends attached to the
          # baseline, so it finishes when the build does — Ctrl-C leaves that run
          # going in the guest and `capsule <name> baseline` re-attaches.
          setup)
            work provision ''${1+"$@"}
            work inject
            ${lib.optionalString (builtins.elem "baseline" programVerbs) "work baseline"}
            ;;

          *) work "$verb" ''${1+"$@"} ;;
        esac
      '';
    }
