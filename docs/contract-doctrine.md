# Contract — doctrine, in both of its roles

doctrine appears in this repo wearing two hats, and conflating them is the
failure this file exists to prevent:

- **as client** — it holds the requirements this boundary is a candidate answer
  to, and it consumes the evidence taken here;
- **as target** — it is the repo under confinement, i.e. one instance of
  [contract-target.md](./contract-target.md).

The same repo, two contracts, and neither implies the other. A different client
could import this evidence without being confined by it, and a different target
could be confined without holding a single requirement.

Which of the below has actually been answered is [status.md](./status.md)'s to
say, and every figure is [probes.md](./probes.md)'s. This file names the
surface. [import-doctrine.md](./import-doctrine.md) is a different thing again —
a **disposable round packet** that directed one round of probes; it is deleted
when its findings land as records. This file is the durable part.

## Role 1 — doctrine as client

### Which records this boundary answers to

Read them with `doctrine <kind> show <ID>` in doctrine's own checkout, never
from files. Nothing here copies record text: it would drift, and doctrine's
tooling is the reader.

| record | what it asks of a capsule | where this repo's answer is kept |
| --- | --- | --- |
| `RFC-025` § *The microVM turn* | the frame for replacing the bubblewrap boundary | [design.md](./design.md) |
| `IMP-426` | the work item every round here reports into | [status.md](./status.md) |
| `SPEC-030` | the capsule contract as written against bubblewrap and measured there — this boundary is the candidate replacement | [threat-model.md](./threat-model.md) |
| `REQ-448`, `DEC-191` | the authority floor: no canonical ref mutation, no canonical credentials, no writable shared object store, no control-plane state | [threat-model.md](./threat-model.md); the git channel's direction is [item 18](./ledger/018-git-channel-direction.md) |
| `REQ-450` | fresh mutable state on five axes — checkout, repository, runtime, temporary state, process | [probes.md](./probes.md), `freshness.sh` |
| `REQ-454`, `RT-1`, `CPT-002` | verification runs in a *separate* fresh capsule from the work it judges | [probes.md](./probes.md), `two-capsules.sh`; the N case is [plan-c-multi-capsule.md](./plan-c-multi-capsule.md) |
| `REQ-451`, `REQ-452`, `QUE-213` | ingestion bounds, and the ceiling a `fetch` has no knob for | [item 18](./ledger/018-git-channel-direction.md); the byte/disk bound is open in [status.md](./status.md) |
| `DEC-135`, `ADR-020` | the host's git never runs in a capsule-authored repository — the rule is about execution context, not about bundles | `host/git-channel.nix`: a host-authored quarantine, `--no-tags`, `transfer.fsckObjects` |
| `ASM-010` | the host never hands guest-authored filesystem metadata to the host kernel | `vm/capsule.nix`: the volume is read with fuse2fs or debugfs, never `mount` |
| `QUE-212`, `DEC-192`, `EVD-016`, `EVD-017` | which direction a result leaves by | [item 18](./ledger/018-git-channel-direction.md) — host-initiated both ways, the daemon deleted rather than confined |
| `DEC-133`, `DEC-193` | the durable admission journal versus short-horizon exhibits, and how long a quarantine is kept | open here: the quarantine is the exhibit and nothing in this repo sets its retention |
| `DEC-189` | a conformance row needs a falsifying delta, and row membership does not port | why REQ-450's process axis is deliberately **unrowed** here — a capsule is a separate kernel, so a permanently green row is misleading evidence rather than extra assurance |
| `DEC-190` | the conformance suite splits into a neutral verdict kernel and per-mechanism payloads | out of scope for this repo: a suite needs a capsule to measure |
| `POL-002` | platform independence from host-project conventions and state | pointed the other way: [CLAUDE.md](../CLAUDE.md)'s guinea-pig rule is the same discipline with this repo as the platform |
| `RSK-231`, `SL-241`, `SL-248`, `SL-252` | why the surface was over budget, and the precedent that this repo is evidence rather than product | [import-doctrine.md](./import-doctrine.md), which is the round packet that carried them |
| `SPEC-012` | merge safety by absence | [design.md](./design.md): the agent has no path to a canonical ref |

Explicitly not this boundary's business: `REQ-455`–`REQ-458` (journal, CAS,
staleness, repair, retention) and `REQ-461` (capacity). Control-plane concerns —
the hypervisor boundary does not change them.

### How evidence leaves

One probe answers one design question, and its result becomes one doctrine
evidence record. The mapping is not incidental — it is why `probe/` is kept in
the tree at all:

| probe | record |
| --- | --- |
| `netns-boot.sh` | `EVD-018` |
| `freshness.sh` | `EVD-019` |
| `two-capsules.sh` | `EVD-020` |

`netns.sh` and `netns-egress.sh` carry no record in [probes.md](./probes.md);
the P0 transport probes landed as `EVD-016`/`EVD-017`. That file is the
authority on what each probe last returned, and the only place a figure lives —
so a record it does not name is one to check doctrine-side rather than to assume
absent.

The reporting shape, per item: **the shape**, **the price**, **what it breaks**,
and **what you did not measure**. The last is not optional — limits travel with
claims. State the host. State whether it ran off-jail. `n = 1` is fine and
expected; `n = 1` presented as general is the failure mode this whole programme
is recovering from.

**Corrections travel in both directions, and that is the load-bearing half.**
`EVD-019` carried "16 GiB per capsule is what binds at N", which had been read
off `target.nix` — a configuration fact — and travelled as a measurement into
this repo's ledger, its status doc, that record, and the design of the very
probe that refuted it. `DEC-189` says a row needs a falsifying delta; the
corollary is that a number needs one too. A figure withdrawn here is withdrawn
there, struck in place rather than deleted
([item 12](./ledger/012-no-resource-ceiling.md)).

### The direction of the dependency

This repo cites record IDs and holds no record text. doctrine's records may cite
these docs. No doctrine record is authored from here — findings graduate into
`QUE`/`DEC`/`EVD` and into `IMP-426` through doctrine's own gears, which is what
keeps this repo evidence rather than governance.

## Role 2 — doctrine as target instance

What doctrine declares, as an instance of
[contract-target.md](./contract-target.md). Everything below is a *value*; none
of it is a mechanism, and none of it may become one.

| field | doctrine's value | what breaks if doctrine changes it |
| --- | --- | --- |
| `toolsPackage` | `packages.dev-tools` — a `buildEnv` over its `devToolPkgs`, agent-free | the guest loses its tool set. This is the one limb of the floor doctrine has to keep satisfying |
| `defaultBranch` | `edge` | the guest's initial HEAD and the branch a provision lands on; a mismatch is a push that moves a ref and leaves the worktree alone. **Being deleted outright** — the guest's branch becomes the constant `work` and nothing replaces the field ([contract-target.md](./contract-target.md)). If doctrine wants a branch name that identifies a *slice*, that is per-assignment and not per-project — two slices of doctrine at once is the case that settles it — and the place to apply it is on the way out of the quarantine, where the name means something |
| `baseline` | `just web-build test` | `capsule-baseline` has nothing to take a cold-build figure with |
| `commands` | `just test / just web-build` | the motd stops naming its entrypoints. Cosmetic |
| `caches` | `CARGO_HOME`, `BUN_INSTALL_CACHE_DIR` | those caches move into guest RAM, since the guest's root is tmpfs |
| `extraTools` | `pkg-config`, `openssl` | its list assumes a host that already has them |
| `sizes` | 4 vCPU / 8 GiB / 32 GiB volume | see [probes.md](./probes.md) — measured against this target's build, not guessed |
| `guestConfig` | one cargo config, `jobs` derived from `sizes.vcpu`, `debug`/`incremental` off | its builds go back to costing what they cost before ([probes.md](./probes.md)) |

Three obligations that are not fields:

- **Its flake input reads committed HEAD.** `git+file:` means uncommitted work
  in doctrine is invisible to the capsule; a tool-set change needs a commit
  there and `nix flake update target` here.
- **The jailed `claude`/`codex` wrappers stay out of `dev-tools`.** They are
  bwrap wrappers binding host paths that do not exist in the VM. The capsule's
  confinement is the VM.
- **Doctrine's own tooling runs on the checkout, not on the host's records.**
  The guest carries the `doctrine` binary via `dev-tools`
  ([item 5](./ledger/005-doctrine-binary-in-guest.md)), so an agent in a capsule
  reads and writes records *in its own clone* at `<volumePath>/doctrine` — not
  doctrine's bwrap path, and not this host's copy. Record edits come back the
  way every other change does: as commits, through `capsule-collect`, into a
  quarantine the human then chooses to fetch from.

**The boundary that matters most.** doctrine's needs may inform a default; they
may never carry the mechanism. The cargo config is the worked example — the
capability is *render static guest config from the instance's declared
reservation*, not "support cargo", and emphatically not "copy the human's
`~/.cargo/config.toml`", which describes a machine the capsule is not. The smell
is a toolchain's name appearing anywhere but `target.nix`. CLAUDE.md has the
full rule and its three limbs.

## Role 3 — driving a slice from doctrine (parked)

Not built, and parked deliberately rather than forgotten: a skill that runs a
real doctrine slice inside a capsule, `capsule-run`-shaped — **argv supplied by
doctrine, so this repo never learns what a slice is.** That is the same
generic-capability-plus-a-value rule as `baseline`, one altitude up.

Where it attaches, if it lands: the four host programs already are the
boundary's verbs, and they already take the capsule as an argument
([item 20](./ledger/020-which-capsule-a-program-means.md)). What is missing is a
*run a command and return its verdict* verb with escalation semantics — what
happens when the slice fails, who decides to retry, and in which capsule. ssh
plus tmux is the play until those settle; a scheduler over agents sits on top of
`capsule start/stop/status` and changes nothing here
([plan-c-multi-capsule.md](./plan-c-multi-capsule.md), "No daemon").

**Why the contract is not written yet, which is a decision and not an
omission.** Two reasons, and the second is the load-bearing one:

1. doctrine does not want to care about this yet. A contract drafted now would
   be drafted against a client with no requirements to give it, which is the
   failure mode this repo exists to recover from.
2. When doctrine does care, the angle is likely to be **different in kind** — a
   capsule filling an outbox and the host noticing, rather than a synchronous
   verb returning a verdict. A request/result shape frozen today would be the
   wrong abstraction rather than an incomplete one.

That difference has one consequence worth writing down before anyone drafts it,
because it is where an invariant would get given up by accident. **An
event-based model is guest-initiated**, and the host initiates both directions
precisely so the guest has no channel out
([item 18](./ledger/018-git-channel-direction.md)). An outbox the host *polls*
over the door it already has keeps that property; a doorbell the guest *rings*
does not, whatever it is implemented with. Start there.

**And when it lands it is not doctrine's contract.** doctrine being the first
consumer of an execution verb is not a reason for the mechanism to be its — the
same rule as Role 2's, one altitude up again. It belongs in a generic execution
contract beside
[contract-assignment.md](./contract-assignment.md), which already carries the
one field any such shape needs from this side: a `generation`, so a result that
arrives after a slot has been re-assigned is refusable rather than
misattributed.
