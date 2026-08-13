# Threat model — what the boundary actually is

What the confinement claims, and what it does not. The shape it describes is in
[design.md](./design.md); the items that keep it honest are in
[ledger/index.md](./ledger/index.md).

Guest ring-0 to host, largest surface first:

1. **KVM.** MSR/CPUID/paging/instruction-emulation surface in the host kernel,
   reachable from guest ring 0. Irreducible in any VM, and still the reason the
   VM is worth having: the bwrap jails' equivalent boundary is the whole host
   syscall table.
2. **Firecracker's device model.** virtio-net, two virtio-block, serial, an
   i8042 stub, PCIe config space. No vsock, no balloon, no MMDS, no vhost-user,
   no virtiofsd — the generated config has `"vsock": null` and nothing else
   attached. Rust, small, seccomp-filtered (above).
3. **The host IP stack, via the tap.** The guest emits arbitrary L2 frames and
   the host kernel parses them. This is surface the bwrap jails do *not* have —
   a bwrap process holds no effective `CAP_NET_RAW`, because the host netns is
   owned by the initial user namespace. Which is why none of the host config in
   README "Host requirements" is optional
   ([item 7](./ledger/007-host-config.md)).
4. **The one host service on the /30.** tinyproxy — C, parsing guest-authored
   HTTP. There were two; the second was a git daemon running `receive-pack` as
   the host user on a repo whose objects then flowed into the real tree, and it
   is gone rather than hardened (item 18). What remains of that surface is
   `index-pack` inside a host-initiated fetch, which no longer listens and which
   the guest cannot start.

**Raising the price of (1).** Guest ring-0 is the *input* to the KVM surface,
and loading a kernel module is the cheap way to get there once something has
root in the guest. `security.lockKernelModules` + `security.protectKernelImage`
turn that into a guest kernel LPE instead. This is not the perimeter moving
inward — the perimeter stays host-side, and a guest that is already ring-0 can
undo anything in the guest. It buys the interval between "agent escalates to
guest root" and "agent is in a position to attack the hypervisor", which is
where the expensive surface begins. The device set is fixed and fully loaded by
the time the lock lands; anything wanting a module on demand (fuse, loop,
`nf_tables`) will fail, and the switch is two lines in `vm/capsule.nix`.

And the channel no hypervisor closes: **the commits**. `capsule/*` gets fetched
and built on the host, so agent-authored code executes outside the jail by
design. That is the largest practical risk here and everything above is
second-order to it. The confinement's job is to bound what the agent can reach
*while* working, not to make its output safe to run unread.

