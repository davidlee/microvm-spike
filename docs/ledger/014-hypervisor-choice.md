# NOTES item 14 — hypervisor choice — firecracker's floor is what shapes half this list

*State: open option — scoped, nothing run.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Scoped in [spike-cloud-hypervisor.md](../spike-cloud-hypervisor.md)**, which
is what a cloud-hypervisor branch would touch and in what order. Two things
there correct the framing below rather than extend it. **Shares are no longer
the case for it**: the tarball, the credential and the read-only store were
solved without them ([item 18](./018-git-channel-direction.md),
[item 22](./022-secrets-at-start.md)), and under a VMM that *can* mount a host
directory, "no shares" stops being a constraint this repo inherits and becomes a
policy it has to state. What is left as the case is **memory** — firecracker's
runner throws on `balloon` and every hotplug option, so the ratchet in
[item 12](./012-no-resource-ceiling.md) has no lever under it, and CH's balloon
carries `free_page_reporting`. And **"a one-word switch" is now measured, with a
precondition attached**: it is two words. microvm.nix puts `i8042` in the initrd
for firecracker alone, so as committed the swap changes `toplevel`, the initrd
and the store disk; with that one module made unconditional, all three are the
*same derivation* and only the runner differs (`just hypervisor-delta`,
2026-08-13). Forcing it on the firecracker side changes nothing — same erofs, so
no rebuild for a running slot — which means a cloud-hypervisor slot would share
the exact image every firecracker slot runs, and the one-image property
([item 21](./021-declared-capsule-flake-attribute.md)) survives a second
hypervisor. Identical bytes are not a boot, though: nothing has started that VMM.

**Hypervisor choice.** firecracker's feature floor — no shares — is what shapes
the bootstrap-tarball problem, the credential problem and the read-only store,
i.e. about half of this list. `hypervisor = "cloud-hypervisor"` is a one-word
switch: also a Rust VMM, runner passes `--seccomp true`, gains virtiofs shares
(secrets by ro-bind, no tarball) and balloon. Cost is virtiofsd — one more
host-side daemon speaking a guest-controlled protocol — and a slightly larger
device model. The policy (no default route, proxy-only egress, host-side ref
guard) is unchanged either way. Worth a branch. `crosvm` is the other candidate:
shares plus `--pivot-root` and per-device minijail sandboxing built in, but its
nixpkgs maintenance needs checking first. `qemu` is the only runner honouring
`microvm.user`, but it is the largest surface and its user-mode networking would
void the egress control. Direct firecracker + jailer is not worth it: the jailer
wants everything inside a chroot while the generated config is absolute
`/nix/store` paths, so it means pre-populating a chroot with the closure —
reimplementing microvm.nix, badly, for less than
[item 11](./011-host-side-runs-as-you.md) buys.
