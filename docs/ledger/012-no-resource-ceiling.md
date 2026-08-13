# NOTES item 12 — no resource ceiling on the VM

*State: open.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**No resource ceiling on the VM** — though less is unbounded than that suggests,
and the distinction matters for what is worth fixing. (The two host services now
have ceilings; see [item 11](./011-host-side-runs-as-you.md). This is about the
VMM.)

| resource | bound today | actually open |
| -------- | ----------- | ------------- |
| memory   | `target.sizes.mem`, hard — but a **ceiling**, not a charge. ~~the VM costs 16 GiB for its whole life~~ **struck**: firecracker does not preallocate and the guest root is tmpfs, so two booted capsules cost ~1.5 GiB between them ([probes](../probes.md)) | what the guest *touches* — no balloon, so a high-water mark is never returned. ~~Unmeasured under load~~ **measured**: two cold builds at once peaked at 7774 and 6801 MiB inside an 8192 ceiling with zero reclaim ([probes](../probes.md#two-cold-builds-at-once)), so memory is *not* the binding term at N=2. What is still open is the ratchet, not the peak — a capsule holds most of its ceiling until it is stopped |
| vCPU     | `target.sizes.vcpu` threads of 32 | the *share*: those threads at 100% compete with everything else you are doing. A real charge from the first busy thread, unlike memory |
| disk     | 32 GiB, hard — a sparse file cannot exceed its declared size | see [item 15](./015-things-that-only-grow.md) |
| disk I/O | none | a `cargo build` in the guest hammers the host disk unthrottled |

So the real asks are `CPUQuota`/`CPUWeight` and `IOWeight`, plus
`MemoryMax` as a backstop against a VMM leak rather than against the guest.
Interim, without moving to the host module: `systemd-run --user --scope -p
CPUQuota=400% -p IOWeight=50 -p MemoryMax=10G -- vm capsule`. Caps only, no
uid separation, and the user slice needs the `cpu` controller delegated for
the quota to take.

**How the memory row came to be wrong is worth more than the row.** It was
read off `target.nix` — a configuration fact, labelled as one — and it
travelled as a measurement anyway: into this ledger, into the spike's status
doc, into doctrine's EVD-019, and into the design of the very probe that
eventually refuted it. DEC-189 says a row needs a falsifying delta; the
corollary is that **a number needs one too**, and a number read off a config
file has none. The same trap is why [probes.md](../probes.md) exists and why
it records provenance per figure.
