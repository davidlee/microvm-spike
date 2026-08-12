What works. flake.nix:20 lists aarch64-darwin. hypervisorsOnDarwin = [ "qemu" "vfkit" ] — vfkit natively (Apple Virtualization.framework), qemu via HVF. microvm.vmHostPackages is the seam: runner script built as darwin, guest closure as aarch64-linux (lib.replaceString "-darwin" "-linux"). firecracker / cloud-hypervisor / crosvm are KVM — Linux only, not offered.

Two taxes.

1. Guest must be built by Linux. Nix on macOS can't build linux derivations. Needs nix.linux-builder from nix-darwin (itself a VM, so VM-inside-nothing bootstrap) or a remote Linux builder. Fine, but it's a real dependency, and every guest config change round-trips through it.
2. Guest is aarch64. doctrine's toolchain pin, sccache, any x86 assumption changes.

The killer, for this spike specifically: no tap.

vfkit.nix:  type == "bridge" -> throw "requires vmnet-helper which is not yet implemented"
            otherwise        -> throw "use type = \"user\" for NAT networking"
flake.nix:  hypervisorsWithTap = filter (hv: hv != "vfkit") …

type = "user" is Virtualization.framework NAT. NAT means the guest has a default route to the internet, which is precisely the invariant the whole confinement rests on ("no default route in the guest; the only egress is the proxy"). Point the guest at a proxy and it's a guest-side setting — an agent that ignores HTTPS_PROXY just goes direct. The perimeter would have to be rebuilt on macOS pf, filtering the vmnet subnet, which is a different piece of machinery and a weaker one (no p2p /30, shared vmnet, no per-VM address guarantee).

qemu on darwin doesn't rescue it — macOS has no native tap device, so it's user-net there too.

Silver lining if you ever port it: vfkit does virtio-fs (--device virtio-fs,sharedDir=), so the no-shares tax that shapes half this design vanishes — credentials by bind mount, no bootstrap tarball.

Verdict: microvm.nix on macOS is real and boots NixOS guests. The capsule doesn't port — its security comes from tap + no route + host-side proxy, and vfkit gives you none of the three. Keeping the agent host on Linux is the right call.

What to do instead: plan-b-other-jails.md. Two shapes — a plain qemu/UTM Linux VM with the perimeter on the macOS side (hardened tier), and seatbelt with the perimeter reused verbatim (the low-barrier tier, and the one to ship as the macOS default).

