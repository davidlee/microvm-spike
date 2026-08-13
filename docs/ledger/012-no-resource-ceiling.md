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
| memory   | `target.sizes.mem`, hard — but a **ceiling**, not a charge, and ~~a lever on the charge~~ **not a lever on it either**: cutting it 8192 → 6144 moved a built slot's `anon` by 46 MiB ([probes](../probes.md#the-first-cold-build-at-a-6144-ceiling)). ~~the VM costs 16 GiB for its whole life~~ **struck**: firecracker does not preallocate and the guest root is tmpfs, so two booted capsules cost ~1.5 GiB between them ([probes](../probes.md)) | what the guest *touches* — no balloon, so a high-water mark is never returned. ~~Unmeasured under load~~ **measured**: two cold builds at once peaked at 7774 and 6801 MiB inside an 8192 ceiling with zero reclaim ([probes](../probes.md#two-cold-builds-at-once)), so memory is *not* the binding term at N=2. What is still open is the ratchet, not the peak — a capsule holds most of its ceiling until it is stopped, and lowering the ceiling does not shorten the hold |
| vCPU     | `target.sizes.vcpu` threads of 32 | the *share*: those threads at 100% compete with everything else you are doing. A real charge from the first busy thread, unlike memory |
| disk     | 32 GiB, hard — a sparse file cannot exceed its declared size | see [item 15](./015-things-that-only-grow.md) |
| disk I/O | none | a `cargo build` in the guest hammers the host disk unthrottled |

So the real asks are `CPUQuota`/`CPUWeight` and `IOWeight`, plus
`MemoryMax` as a backstop against a VMM leak rather than against the guest.
Interim, without moving to the host module: `systemd-run --user --scope -p
CPUQuota=400% -p IOWeight=50 -p MemoryMax=10G -- vm capsule`. Caps only, no
uid separation, and the user slice needs the `cpu` controller delegated for
the quota to take.

**The ceiling is not a dial on the charge, which is the second half of the same
claim.** "A ceiling, not a charge" was established by a boot — two booted
capsules costing ~1.5 GiB against a declared 16 GiB. It left open the obvious
inference that a *smaller* ceiling therefore buys a smaller bill, and
[plan-d](./plan-d-fleet.md) §0 spent that inference: it cut `sizes.mem` to 6144
and scaled the four-hot recommendation by the new number. The first build at
6144 refutes it. A built slot's `anon` is ~6.1 GiB at **both** ceilings — 6141
of 8192, 6095 of 6144 — because what the VMM holds is every distinct page the
build ever touched, not a fraction of what the guest was offered. So four hot
slots cost what four cost before, and the only lever that returns memory is a
stop ([probes](../probes.md#the-first-cold-build-at-a-6144-ceiling)).

Two corollaries worth having by name. **99% of a ceiling can be a coincidence:**
6095 of 6144 reads as saturation and is not, and the only reason anyone can tell
is that the same workload was measured against a different ceiling. **And
all-zero `memory.events` is not evidence of headroom** — no `MemoryMax` is set
on these units, so nothing can be forced to reclaim and the field is zero by
construction. The guest's own `free` and `/proc/pressure/memory` are what say
whether a ceiling squeezed anything, and they live on the other side of the
boundary from every other figure here.

**How the memory row came to be wrong is worth more than the row**, and it went
wrong the same way twice. It was
read off `target.nix` — a configuration fact, labelled as one — and it
travelled as a measurement anyway: into this ledger, into the spike's status
doc, into doctrine's EVD-019, and into the design of the very probe that
eventually refuted it. DEC-189 says a row needs a falsifying delta; the
corollary is that **a number needs one too**, and a number read off a config
file has none. The same trap is why [probes.md](../probes.md) exists and why
it records provenance per figure.

The second time was smaller and better-behaved, and still the same trap. §0's
6144 was arithmetic over measured peaks — so it had provenance — but the *step*
from "peaks are 6801-7845 inside 8192" to "so declare 6144 and four fit" is a
model of how the peak depends on the ceiling, and that model was never measured.
A figure with provenance can still carry an unmeasured relationship, and the
relationship is the thing that travels into a recommendation. What made it cheap
to catch was reading the guest's side of the same moment; the cut had been
deployed for one build.
