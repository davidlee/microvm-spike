# Single source of truth for the host<->guest link. A /30 point-to-point tap:
# no bridge, no LAN exposure, and deliberately no default route in the guest —
# the only way out is the allowlist proxy on the host end.
#
# Imported by flake.nix (which threads it to the guest via specialArgs) and by
# the host-side NixOS module, so an address is never spelled twice.
{
  tap = "vm-capsule";
  host = "10.99.0.1";
  guest = "10.99.0.2";
  prefix = 30;
  mac = "02:00:00:00:99:02";
  proxyPort = 3128;
  gitPort = 9418;
}
