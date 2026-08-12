# Bringing a guest down cleanly — the half of a stop that has to happen *inside*
# the capsule, and the one thing no host-side signal can do for us.
#
# Firecracker offers exactly one shutdown signal, `SendCtrlAltDel`, and this
# guest cannot receive it: the i8042 controller firecracker emulates is a stub
# for CPU reset, and the kernel's driver refuses to attach to it (`probe with
# driver i8042 failed with error -22`), so there is no keyboard to press the keys
# on. That is what leaves microvm.nix's own `microvm-shutdown` — and therefore
# every `systemctl stop microvm@<name>` — a power cut on a mounted ext4 volume
# (NOTES item 11).
#
# So the request goes over ssh, and it is a **reboot**, not a poweroff. The guest
# has no ACPI power button, so a poweroff halts the vCPU and leaves the VMM
# holding the tap ("Power off not available: System halted instead"), which is
# the EBUSY trap in CLAUDE.md. A reboot instead unmounts everything and then
# resets, and `reboot=k` turns that reset into the one thing the i8042 stub *does*
# implement — the VMM exits by itself, `exit_code=0`, with nothing killing it.
#
# It knows nothing about VMMs, namespaces or unit names, which is what lets both
# paths use it: it asks a guest to go down, and waiting for the hypervisor is the
# caller's job, because only the caller can see one. `vm-stop` reaps the process
# it can prove is its own; the unit hands off to microvm.nix's own `ExecStop`,
# whose `socat` on the API socket blocks until firecracker exits.
#
# `--identity` for the same reason `transport` is an argument elsewhere: the
# devshell path runs as the human with her agent, and a unit has neither. One
# store path, the difference supplied at the call site.
{
  pkgs,
  net,
  guestSsh,
}:
pkgs.writeShellApplication {
  name = "capsule-halt";
  runtimeInputs = [pkgs.openssh];
  text = ''
    identity=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --identity)
          shift
          [ "$#" -gt 0 ] || {
            echo "--identity needs the path to a private key" >&2
            exit 1
          }
          identity=(-o IdentitiesOnly=yes -i "$1")
          ;;
        --identity=*) identity=(-o IdentitiesOnly=yes -i "''${1#--identity=}") ;;
        *)
          echo "capsule-halt: unexpected argument '$1'" >&2
          exit 1
          ;;
      esac
      shift
    done

    # Root, because a reboot is root's to ask for: the agent is unprivileged by
    # design and polkit will not grant it to a non-local session.
    ssh_cmd=(${guestSsh.command} ''${identity[@]+"''${identity[@]}"})

    # No ConnectTimeout of its own: `guestSsh.args` carries one, and ssh takes
    # the first value it is given for an option, so a second here would be dead
    # text that reads as the answer.
    if "''${ssh_cmd[@]}" -o BatchMode=yes \
         root@${net.guest} 'systemctl --no-block reboot'; then
      echo "capsule-halt: reboot requested — the guest unmounts, then its reset exits the VMM"
      exit 0
    fi

    # Nonzero, because "the guest did not take the request" is exactly what a
    # caller has to know: it decides between waiting for a VMM that is about to
    # exit and killing one that never will. A unit must not let that skip the
    # commands after it, so the `ExecStop` line carries systemd's `-` prefix
    # rather than this lying about the outcome.
    echo "capsule-halt: no guest answering at ${net.guest} — nothing to halt cleanly" >&2
    exit 1
  '';
}
