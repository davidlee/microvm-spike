{lib, ...}: {
  microvm = {
    hypervisor = "firecracker";
    # Baselines; each VM sizes itself.
    vcpu = lib.mkDefault 4;
    mem = lib.mkDefault 4096;
    # Firecracker supports no shares (9p/virtiofs both throw), so the guest
    # store is always a generated disk image — nothing is read from the host
    # store at runtime, and no host directory can be mounted in.
  };

  # Console is the serial line that `microvm-run` attaches to.
  services.getty.autologinUser = "root";

  # What makes a stop clean, and it is a *keyboard driver*. Firecracker's only
  # shutdown signal is `SendCtrlAltDel` on the API socket — an i8042 keystroke —
  # and microvm.nix's `microvm-shutdown`, i.e. every `systemctl stop
  # microvm@<name>`, is exactly that call. The guest was recorded as *ignoring*
  # it (NOTES item 11); it was never able to receive it: nixpkgs builds
  # `CONFIG_SERIO_I8042` and `CONFIG_KEYBOARD_ATKBD` as modules, nothing
  # autoloads a legacy port device (the cmdline already carries firecracker's
  # own `i8042.nopnp` and friends), and `security.lockKernelModules` then makes
  # the omission permanent at boot. Loaded here, `systemd-modules-load` gets
  # them in before that lock, the kernel's VT handler sees ctrl-alt-del, systemd
  # reboots cleanly and `reboot=k` turns the reset into a VMM exit — so the
  # volume is unmounted rather than power-cut, on both paths and for root, with
  # no credential into the guest.
  #
  # Attack surface is the driver, not the device: the i8042 stub is in
  # firecracker's surface either way (docs/threat-model.md), and the only thing
  # that can feed it scancodes is the host.
  boot.kernelModules = ["i8042" "atkbd"];

  networking.useDHCP = false;

  # Store disk is built from the closure; man pages are pure weight here.
  documentation.enable = false;

  system.stateVersion = lib.trivial.release;
}
