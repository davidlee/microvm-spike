{pkgs, ...}: {
  # Smallest thing that proves firecracker + KVM + the generated kernel work.
  environment.systemPackages = [pkgs.hello];

  users.motd = ''
    hello microvm. `hello` works, `poweroff` leaves.
  '';
}
