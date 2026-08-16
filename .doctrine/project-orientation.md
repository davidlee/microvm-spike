# Project Orientation

## Project Purpose

oubliette builds a **capsule**: a Firecracker microVM that confines a coding
agent to exactly one target repo, with a host-side egress perimeter the guest
cannot reach. The product is the capsule; the confined repo is a *client*. Today
one client exists — `~/dev/doctrine`, declared in `target.nix` — and it is the
guinea pig, never the design.

The operator is a human on one NixOS host running N slots (`a`…`j`), each a
capsule assigned a unit of work, a policy, and a target profile.

## Guiding Principles

- **The perimeter is host-side.** Egress filtering, the forward-chain drop, the
  namespace. Never move a control into the guest — guest-side settings are
  convenience, not security. The full invariant list is
  [CLAUDE.md](../CLAUDE.md) → *Architecture invariants*; break one and the
  confinement stops meaning anything.
- **doctrine is the guinea pig, not the design.** Every target need must be met
  by a *generic capability plus a value the target supplies*. The review
  challenge: *would a different target need this code changed, or only a
  different value?* If the code, it is in the wrong place.
- **Declare, don't scrape.** No value comes from a human's `$HOME`, and nothing
  target-shaped is read out of the target repo — the agent can edit that.
- **Forcing proves a derivation evaluates; only building proves its text is a
  program.** Three kinds of check exist here and they are not interchangeable
  (`just check` parses, `hostModuleUnits` evaluates, the `*Cases` suites *run*).
- **Evidence has rungs** — `STD-001`, and it is `required`. build / run / start /
  trigger / take / exercise / compare / reach / read back. A branch can be built,
  evaluated, shellchecked and shipped while the condition selecting it has never
  once been true, and nothing distinguishes that from a branch that works. **Name
  the rung** in the commit and in the completion note; "done" is not a rung.

## Architecture

A host NixOS module (`host/`) creates a network namespace per slot, puts the
tap inside it, runs a tinyproxy allowlist and an ssh relay socket beside it, and
ships a set of `capsule-<verb>` programs plus one `capsule` front end. The guest
(`vm/`) has no default route: the proxy is the only egress. Git is not a control
— the host initiates both directions and the guest has no remote.

Two paths run the same code: a devshell path (`capsule-host`, foreground, no
root) and the module path (systemd units). One at a time; `capsule-host` refuses
while a proxy unit is active.

Major components:

- `flake.nix` — `net` (single source of truth for addresses), `probeFabric`,
  every derivation and case suite.
- `capsules.nix` / `policies.nix` / `target.nix` — the three declarations. Slots,
  host controls, and the repo under confinement. No perimeter value lives in
  `target.nix`.
- `host/` — the NixOS module, the programs, and one `*-cases.nix` suite per
  program.
- `perimeter/` — the proxy and `capsule-host`, which know nothing about the jail.
- `vm/` — guest modules.
- `probe/` — evidence, not scaffolding. Needs root; the user runs these.

## Structure

- `docs/` — the map is [docs/index.md](../docs/index.md).
- `docs/ledger/` — **closed archive**, items 1–54. See *Conventions*.
- `docs/probes.md` — measured figures (migrating to observations).
- `.doctrine/` — governance. ADRs, policies, standards, backlog, knowledge,
  memory, slices.
- `CLAUDE.md` — architecture invariants, and an index of the gotchas (bodies are
  in the memory corpus: `doctrine memory search --tag gotcha`).

## Conventions

**The ledger is frozen at item 54 and is a closed archive.** `docs/ledger/`
holds 54 items with frozen, append-only ids, cited from ~42 source files as
`NOTES item N` — an *id*, not a path. That citation form stays valid forever and
nothing renumbers. **No new ledger items.** New decisions go to
`doctrine adr new`; durable gotchas to `doctrine memory record`; latent work to
`doctrine backlog new`; epistemic claims to `doctrine knowledge new`. An existing
item may still be *resolved in place* — never deleted, never renumbered.

**Two id spaces, strictly separate.** This repo confines doctrine *and* is now
governed by doctrine. An `SL-`/`ADR-`/`REQ-` id in this repo's `.doctrine/` means
nothing in `~/dev/doctrine`'s corpus and vice versa; a bare id is always this
repo's. Nothing mechanical enforces it — the machinery's `statePaths` are
relative to the *guest's* checkout, so oubliette's own `.doctrine/` is invisible
to it. Related trap: `unit` and `purpose` on a slot already borrow doctrine's
slice/audit vocabulary and name *the confined project's* entities.

**Routing here is backlog-first.** Most capsule work runs straight off
`doctrine backlog` — issue / improvement / chore / risk / idea. **Larger programs
of work get a slice** and the full lifecycle. Do not open a slice for a
one-file fix; do not run a multi-phase program off a backlog item.

**Figures are measurements, not prose.** Link, don't copy a number.
**There is no changelog** — `git log` is the record, so a commit message is
load-bearing: a `feat:`/`fix:`/`doc:` subject naming *the finding*, citing the
item or entity, and saying what was **not** exercised. Commit at each piece.
Content lands somewhere: if the commit will not take it, it accretes in the
nearest file with no size bound.

Formatting is alejandra, 2-space indent. Lint after every file.

## Tooling & Development Workflow

    just              # build + units + fmt (the default)
    just check        # nix-instantiate --parse over every file + alejandra -c; no eval
    just units        # evaluates the NixOS module — seconds
    just cases        # runs each host program's own text against a stub
    just build        # all three, so a failing case is a failing build

Slot lifecycle: `just up <name>`, `just provision|inject|baseline|collect|setup
<name>`, `capsule <slot> <verb>`, `capsule all status`. Probes need root and are
the user's to run (`sudo probe-netns`).

Be judicious about nix builds and evals beyond this project. **Ask the program,
don't read it** — the module's programs on `PATH` are wrappers.

## Further Reading

1. [CLAUDE.md](../CLAUDE.md) — invariants, gotchas, conventions. Read before
   proposing changes.
2. [docs/index.md](../docs/index.md) — maps question to file.
3. [docs/ledger/index.md](../docs/ledger/index.md) — the archive. **Several
   obvious-looking ideas are recorded there as considered-and-rejected.**
4. [docs/contract-target.md](../docs/contract-target.md) and
   [docs/contract-doctrine.md](../docs/contract-doctrine.md) — what any repo must
   supply, and doctrine's two roles.
5. [docs/threat-model.md](../docs/threat-model.md) — what the confinement claims.
