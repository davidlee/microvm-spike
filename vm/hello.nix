{pkgs, ...}: {
  # Smallest thing that proves firecracker + KVM + the generated kernel work.
  # No interfaces are declared, so keep boot from waiting on a network that
  # will never arrive.
  networking.useNetworkd = false;
  systemd.network.enable = false;

  environment.systemPackages = [pkgs.hello];

  users.motd = ''
    hello microvm. `hello` works, `poweroff` leaves.
  '';
}
