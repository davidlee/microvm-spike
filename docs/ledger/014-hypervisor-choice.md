# NOTES item 14 — hypervisor choice — firecracker's floor is what shapes half this list

*State: open option.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

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
