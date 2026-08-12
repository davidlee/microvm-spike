# IMPORT — pricing doctrine's unproven requirements in the spike

**Disposable.** A working packet, not a design and not governance. It exists to
direct a round of cheap probes in this repo so the requirements get *shaped and
priced here* before doctrine's governance gears turn. Delete it when the round
ends and its findings have landed as knowledge records.

Doctrine-side anchors: `RFC-025` § *The microVM turn*, `IMP-426` (the work item),
`QUE-212` (the one blocking question), `CPT-002` (the threat ranking that sets
the priorities below). Read via `doctrine <kind> show <ID>` in `/workspace/doctrine`
— not from files.

---

## The frame, in one paragraph

Doctrine's capsule contract (`SPEC-030`) was written against a bubblewrap
backend and measured there. `SL-248` shipped it; `SL-252` was abandoned trying to
make its conformance fixture defensible; `RSK-231` called the whole surface over
budget. This spike is the candidate replacement boundary. What is *not* yet known
is which of doctrine's requirements the VM satisfies naturally, which it makes
harder, and which it makes meaningless. That is what this round measures.

**The bar for this round is a price, not a proof.** Every item below wants an
answer of the form *"costs about this much, here's the shape, here's what it
breaks"* — not a working implementation and not a conformance row.

---

## Priority 0 — the blocker

### P0. How does a result leave? (`QUE-212`)

> **SETTLED 2026-08-11 — read the records, not this section.** Both legs probed
> and both work (`EVD-016`); `DEC-192` is `accepted` on the owner's ruling —
> host-initiated in both directions, git-daemon deleted. `QUE-212` is `answered`.
> `EVD-017` carries the escalation finding that made deletion the stronger case.
> **Two claims below are wrong and must not travel:** *"the guest never initiates
> a connection to the host at all"* — the proxy remains and is guest-initiated;
> and the host's refspec does not fully decide the destination namespace without
> `--no-tags`. New residual: `QUE-213` (the fetch ceiling), which blocks P1d.
> The rest of this section is kept only as the reasoning that got there.

Nothing downstream can be shaped until this is settled. `REQ-451` and `REQ-452`
are written about a **bounded file snapshot**, and the hazard model that shaped
them — a file appearing in a shared location — is absent here. So their subject
may not exist in this architecture, and P1c's demonstration depends on which
transport survives.

**The rule, stated correctly.** `DEC-135` chose Git bundle ingestion under a
structural rule: trusted control-plane code never runs Git **in a
capsule-authored repository** — because git reads config, hooks and
`.gitattributes` filters from the repo it runs in, so a capsule-written repo used
as execution context is arbitrary code execution. The rule is about **execution
context**, not about bundles. `ADR-020` says the same at architecture altitude:
*no trusting capsule-controlled Git configuration.*

`REQ-451`'s six bounds — path, symlink, quiescence, time, byte, object — tame a
specific hazard: under bubblewrap the natural channel was **a file appearing in a
shared location**, which is racy and path-traversable. The VM has no shares, so
most of that class is *absent*, not defended.

**The actual defect here is direction, not format.** The spike has the guest
**push**: the host runs `receive-pack` as a live hostile-input-parsing service on
a port the guest can reach, the mirror is guest-written, and the ref-restriction
hook, `capsule-git` group and mirror-sync uid all exist to confine that.

**Invert it.** Host-initiated `git fetch ssh://guest/…` into a fresh quarantine
repo keeps `upload-pack` guest-side, runs the host's git in a **host-authored**
repo, and satisfies `DEC-135` with no bundle at all. The host→guest ssh channel
already exists.

**Probe, cheapest first:**

| | shape | what to measure |
|---|---|---|
| A | **host-initiated fetch over the existing ssh channel** | does it work under netns; cost; what bounds it, given `fetch` has no `receive.maxInputSize` analogue — VM disk size, ref restriction, `--depth`? |
| B | A, plus host-side `git bundle create` after the fetch | only if something genuinely needs a snapshottable artifact (see below); cost of the extra step |

**There is no third candidate.** An outbox block device the host mounts is ruled
out by `ASM-010` — the host never hands guest-authored filesystem metadata to the
host kernel, and `ro`/`nosuid`/`nodev`/`noexec` do not mitigate it because the
parse happens before those options constrain anything. This repo already held
that line (`vm/capsule.nix`: *"with fuse2fs or debugfs, never `mount`"*); an
earlier draft of this packet proposed it anyway and was wrong. Do not spend probe
effort re-establishing it.

**A is expected to win.** Two caveats that survive it and should be answered, not
assumed:

- `index-pack` still parses hostile bytes host-side. True of *every* option
  including bundles, so not a new risk — but `transfer.fsckObjects` plus a size
  ceiling is the answer, and the ceiling has to come from somewhere.
- A fetch leaves **no artifact**. `DEC-133` separates the durable admission
  journal from short-horizon forensic exhibits, and a live fetch produces nothing
  to hash, retain or deterministically re-ingest. A retained quarantine repo may
  serve. This is a retention question, not a security one — decide it, don't
  drift.

### The consequence worth more than the fix — confirm this first

If the result leaves by host-initiated fetch **and** provisioning enters by
host-initiated push over the same ssh channel, the guest never initiates a
connection to the host at all, and **git-daemon leaves the perimeter entirely**.
`README.md`'s *"the only two ports the guest may reach"* becomes one — the proxy.
`receive-pack`, the `refs/heads/capsule/*` update hook, the `capsule-git` group
and the mirror-sync uid stop being *confined* and start being *absent*.

That is deletion rather than mitigation, which is exactly the shape `RSK-231`
asked for. Confirm it before shaping anything downstream: if it holds, several
P1 items get cheaper and a chunk of `host/services.nix` and `perimeter/` goes
away.

---

## Priority 1 — the requirements worth importing

Four, chosen because the VM changes the answer and the spike can price them
cheaply. Everything else in `SPEC-030` is control-plane work the hypervisor
boundary does not touch — leave it alone this round.

### P1a. `REQ-450` — fresh mutable state, five axes, worker *and* verifier

*Checkout, repository, runtime, temporary state, process.* This spike is
presently the opposite shape by design: one persistent VM, a persistent `/work`
volume holding a real clone, foreground build-then-exec, nothing registered
anywhere.

**Measure:** wall-clock to a usable fresh capsule cold and warm; disk and pack
cost per instance under one-image-plus-runners versus N blobs; which of the five
axes are actually satisfied versus merely plausible; teardown — does the VMM
exit, is the tap released, is state genuinely gone.

[NOTES item 17](./notes.md) has done this scoping already. The deciding cost is the guest
image, and the two per-instance values that must leave the closure are the
address and the **base commit**. A kernel param works for neither — it lands in
`toplevel`. The netns work makes the guest bit-identical, which is the lever.

**Known sharp edge:** firecracker does not exit on guest poweroff — it halts the
vCPU and holds the tap, so the next start fails `Device or resource busy`. Any
freshness claim that ignores this is measuring the wrong thing.

### P1b. `REQ-454` — verification runs in a *separate* fresh capsule

`red-team.md` `RT-1`: hostile verification code must not run in the control
plane. So two concurrent capsules is a requirement, not a nice-to-have.

Per `CPT-002` this is the **highest-value import in the list**. It is the
substrate for the defence against the threat that actually arrives — a worker
that stays perfectly inside the boundary and produces plausible, wrong work.
Confinement bounds the blast radius; this is what bounds the intent.

**Measure:** two capsules concurrently under the netns design; cost of the second
against the first (shared closure should make it cheap); and confirm the
`probe/netns.sh` result holds for real VMs, not just the model — A cannot reach
B, B cannot reach A, neither reaches the host beyond its allowed pair.

### P1c. `REQ-448` — the authority floor

`DEC-191` makes this invariant at every confinement posture: no canonical ref
mutation, no canonical credentials, no writable shared object store, no
control-plane state. Local edits and local commits only.

Mostly already true here, which is the point — **demonstrate it, don't argue
it.** Show the guest holds no credential that reaches anything canonical, and
that there is no shared object store because there are no shares.

**The third demonstration depends on P0.** Today it is "a push outside
`refs/heads/capsule/*` is refused" by the mirror's update hook. If the inversion
holds, there is nothing to push to — the guest initiates no connection to the
host at all — and the demonstration becomes *absence of a channel* rather than
*refusal on a channel*, which is the stronger claim and needs no hook to make it.
Settle P0 before writing this one.

Cheap, and it is the one property that must hold identically on every backend, so
it is worth having a spike-side demonstration to point at.

### P1d. `REQ-451` / `REQ-452` — ingestion bounds

**Blocked on P0.** Do not shape these until the transport is chosen; their
subject may not exist.

---

## Explicitly out of scope this round

- The conformance suite. `DEC-190` splits it into a neutral verdict kernel and
  per-mechanism payloads, and `DEC-189` says the row membership does not port.
  Both are *after* this round — a suite needs a capsule to measure.
- `REQ-455`–`REQ-458` (journal, CAS, staleness, repair, retention) and `REQ-461`
  (capacity). Control-plane concerns; the boundary does not change them.
- Anything that looks like production code in this repo. Evidence, not product —
  the `SL-241` precedent.
- The front list for `DEC-191`'s confinement profile. Design work, not probing.

---

## How to report

Per item: **the shape**, **the price**, **what it breaks**, and **what you did
not measure**. That last one is not optional — `RFC-025`'s evidence discipline is
that limits travel with claims, and four of `SL-248`'s defects were derivations
that were accidentally correct in the one environment they had ever run in.

State the host. State whether it ran off-jail. `n = 1` is fine and expected; `n =
1` presented as general is the failure mode this whole programme is recovering
from.

Findings graduate out of this file into knowledge records (`QUE`/`DEC`/`EVD`) and
into `IMP-426`. Then delete it.
