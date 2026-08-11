{lib, ...}: {
  microvm = {
    hypervisor = "firecracker";
    vcpu = 4;
    mem = 4096;
    # Firecracker supports no shares (9p/virtiofs both throw), so the guest
    # store is always a generated disk image — nothing is read from the host
    # store at runtime, and no host directory can be mounted in.
  };

  # Console is the serial line that `microvm-run` attaches to.
  services.getty.autologinUser = "root";

  networking.useDHCP = false;

  # Store disk is built from the closure; man pages are pure weight here.
  documentation.enable = false;

  system.stateVersion = lib.trivial.release;
}
