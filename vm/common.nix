{lib, ...}: {
  microvm = {
    hypervisor = "firecracker";
    vcpu = 4;
    mem = 4096;
    # Firecracker supports no shares (9p/virtiofs both throw), so the guest
    # store is always a generated disk image — nothing is read from the host
    # store at runtime.
  };

  # No interfaces are declared: firecracker has no user-mode networking, only
  # tap, and tap needs host-side setup. Keep boot from waiting on a network
  # that will never arrive.
  networking.useDHCP = false;
  networking.useNetworkd = false;
  systemd.network.enable = false;

  # Console is the serial line that `microvm-run` attaches to.
  services.getty.autologinUser = "root";

  # Store disk is built from the closure; man pages are pure weight here.
  documentation.enable = false;

  system.stateVersion = lib.trivial.release;
}
