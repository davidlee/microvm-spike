# Status — where this stands, and what is next

The one place the current state lives. Read it before picking the work up cold,
and edit it when the state changes rather than adding a second account of it
somewhere. Figures belong in [probes.md](./probes.md), reasoning in
[ledger/index.md](./ledger/index.md); this file says what is true now and what
happens next.

**This file holds no past tense but the five most recent entries, and those
evict.** It grew to 2463 lines by holding a fourth copy of every session — the
commit, the ledger item's own `*State:*` header, and here
([item 54](./ledger/054-status-grew-a-changelog.md)). Each section below states
what leaves it and where that goes; a paragraph with no home in one of them
belongs in the ledger item it cites, or in the commit message.

| section | holds | what leaves, and where |
| --- | --- | --- |
| **Now** | what is true on this host at this moment | it stops being true — overwrite it |
| **Recent** | the five most recent pieces of work, one paragraph each | a sixth arrives — the oldest goes, and anything still true in it moves to **Now** or **Open** first |
| **Next** | work not yet done | it is done — delete the step, do not strike it |
| **Open** | claims nothing should call closed | it closes — delete it; the reasoning is in its item |

## Now

**HEAD is `bbf4e8a` (item 53 verb 1), and this host is one commit behind it** —
switched onto `d256185` (item 52 step 3) at 2026-08-16 22:34. So the installed
`capsule` has `handoff`, `land` and the pin markers, but its `setup` does not yet
write `unit` and `purpose` itself; that is one `just system-switch` away and
nothing depends on it first. `just`, `just check` and `just units` are green;
`just cases` is **536**.

**Nothing is running.** Ten slots declared (`a`…`j`), five created (`a`…`e`),
every VM, proxy and relay inactive; `capsule-perimeter-guard` reports `5 of 10
declared capsule namespace(s) verified`. Every slot is on profile `doctrine` and
policy `build`, and no profile cell carries `*` or `!` — no slot has been left
behind by a document edit.

| slot | unit | purpose |
| --- | --- | --- |
| `a` | 254 | SL-254 — 9 phase slice |
| `b` | — | SL-254 audit |
| `c` | 251 | — |
| `d` | 251 | SL-251 implementation, migrated from `c` |
| `e` | 251 | SL-251 audit of `d` |
| `f`…`j` | — | not created |

**`~/flakes` is switched**, not just edited: 9418 is out of the tap's firewall
stanza and the `capsule-git` group is gone from the live system.

## Recent

Five entries, evicting. Each says what moved, which item holds the reasoning,
and **what it did not exercise** — the last is the part no item owns, because it
is a fact about a session rather than about a decision.

1. **`setup` writes the two fields that say what a slot was assigned** —
   [item 53](./ledger/053-three-coarse-verbs.md) verb 1, so nothing of that item
   is unbuilt. Both writes are **in front of the push**, because a token draws
   two refusals and a refusal arriving after the code has landed leaves a capsule
   standing up on work nobody meant to assign it. The token is taken *out* of the
   argv and filled back in from the record by `unitScope`, so a scope has one
   origin; the checks are one function (`recordUnit`) at four call sites. Seven
   mutations red on their own rounds, an eighth rejected by shellcheck before the
   suite ran. **Nothing live was touched**, and this host has not been switched
   onto it.
2. **A slot is pinned to the document it was provisioned under** —
   [item 52](./ledger/052-the-document-leaves-the-store.md) step 3, closing that
   item. A provision copies the target's document into the slot's own directory
   and records that copy's `sha256:`; every later verb on that slot is pointed at
   *that* directory. **A provision is the one verb that reads this host's
   directory**, because the act that sets a pin cannot be governed by it.
   **Never exercised live**: no capsule was touched, and the first exercise is a
   free slot, a `target.nix` edit and a `capsule all status`.
3. **`handoff` and `land` became verbs of the front end** — item 53's middle and
   third acts. Both collect first and then refuse unless the guest's head is one
   of the objectnames the quarantine's code refs hold — **no `--stale`**, whose
   corollary is that both need the source *running*. The archive rename before
   the force is automatic and *frees* the live names, which is what stops
   [item 50](./ledger/050-a-quarantine-outlives-its-assignment.md) recurring one
   assignment later. **The verify, the archive, the drop and the force have run
   in a sandbox and nowhere else.**
4. **A fetch answers for each half separately**, item 50's third finding: two ref
   namespaces are two questions, so `code:` and `state:` get their own lines and
   the remedy for a refused half is the archive rather than a `+`. Run on this
   host against slot `e` both ways. **The key is untouched** — a slot's second
   assignment still overwrites the first's refs in the quarantine.
5. **The target left the store, and no host-side program is a function of which
   project this host confines** —
   [item 51](./ledger/051-the-target-in-four-store-paths.md) closed by its step 6,
   then item 52's steps 1–2. Every program takes `--profile <name>` and refuses
   without one; the documents are in `/var/lib/capsule-profiles`, written by an
   activation script, so a second target is a file rather than a rebuild; every
   predicate about a document is the reader's, run by the render itself.
   **A second target has still never been declared** — the capability is built
   and unused.

## Next, in order

1. **Switch this host onto `bbf4e8a`**, so `setup` writes the two fields where it
   is actually run. Cheap, and it is the precondition for step 2 being a real
   exercise rather than a sandbox one.
2. **Item 53's first live exercise.** The verify, the archive, the drop and the
   force are sandbox-only. The cheap half is a free slot handed a finished
   exhibit, watched rather than assumed. `f`…`j` are declared and uncreated, and
   `c`'s work has already migrated to `d`, so neither destination costs a live
   assignment.
3. **Item 52 step 3's first live exercise**, and it costs nothing: provision a
   free slot, edit `target.nix`, switch, and read `capsule all status` for the
   `*`. Then corrupt the pinned copy and read the `!`.
4. **[Plan D §9](./plan-d-fleet.md#9-order-of-work) step 6 — D3 + D4**, volume
   verbs and clone semantics, **ungated** since
   [item 49](./ledger/049-who-owns-a-state-directory.md)'s read was taken. S4 and
   S5 are the two most frequent administrative actions and one of them is a
   hand-typed `rm -rf`.
5. **§9 step 7 — D6, detached sessions**, when N > 2 stops being a probe and
   starts being a Tuesday. Carries L9, the *is an agent running* column, and
   `generation`'s refusal half
   ([item 46](./ledger/046-bash-until-the-record-stops-being-flat.md)).
6. **§9 step 8's remainder — D7 and D2's dynamic half.** Items 51 and 52 took the
   host-side programs; what is left is the guest **image**, which still knows the
   project's name (§6.2), and per-assignment flavour selection, which is what
   turns the record's inert `extras` and `image` into fields something selects.
7. **A second target**, Plan C's
   [order of work](./plan-c-multi-capsule.md#order-of-work) item 8, if it is
   still wanted. Now a file rather than a rebuild, and it is the only thing that
   can exercise three refusals that are build-time-only today.

**Parked deliberately, not forgotten**: driving a real doctrine slice from a
skill — `capsule-run`-shaped, argv supplied by doctrine so this repo never learns
what a slice is; [contract-doctrine.md](./contract-doctrine.md)'s Role 3 says
where it would attach. SL-254 was driven by hand and SL-251 is being driven by
hand, and **the sideband arc is what that hand-driving turned out to need** —
collect the half that is not a commit, adopt it, brief the next capsule with it,
scope what a collect takes. Items 42 and 45 are the same lesson from the other
end: the *first* capsule on a unit needs the same half, nothing had a way to give
it one, and when the case arrived the capsule had already started. What the next
hand-driven slice repeats is the requirements list Role 3 is waiting on — write
it down as it happens.

## Open, and nothing should claim these closed

- **Which of build / run / start / trigger / *take* does the evidence cover?**
  Five findings in two days, each green everywhere it was looked at: item 37
  found programs nothing built, item 38 an assertion nothing ran, item 39 a unit
  nothing started, item 40 **a refusal nothing had ever triggered**, item 41 **a
  branch nothing had ever taken**. That last pair is the largest remaining seam —
  a branch can be built, evaluated, shellchecked and shipped while the condition
  selecting it has never once been true, and nothing here distinguishes that from
  a branch that works. Worse, item 41's *first* run passed on an accident of
  environment, which is what a first run is least likely to expose. Most of the
  entries below are instances of it.
- **The sideband arc has only ever run forwards.** Every refusal it met was one
  of the two that happened to fire — a non-fast-forward push, and the ambiguity
  of an over-collected tree. The `code-oid` mismatch, a dirty destination
  worktree and an over-budget state half have still never been reached by a real
  capsule; the guest's own `code-oid` refusal is now reachable **only** by HEAD
  moving mid-flight.
- **Item 45's decision is still owed.** Whether a top-up is a scoped additive
  verb — `--only-absent`, same validation, same `code-oid`, refusing any path
  that already exists — or a **refusal** saying *brief before you start*. The
  second is cleaner; the first is what the day wanted. Neither the `e` delivery
  nor the c→d migration settles it: both remove the window rather than serving a
  capsule already inside it, which is precisely the case
  [item 45](./ledger/045-a-brief-is-an-origin-not-a-top-up.md) was written about.
- **The policy verb has one exercise left: run it as a user who is *not* the
  owner.** The owner holds blanket `ALL`, so the owner's success is the weakest
  form of that evidence
  ([item 41](./ledger/041-a-delegable-verb-that-ends-in-root.md)).
- **Which stage a host-authored commit lands at.** With no archive it is always a
  root commit, so it parents nothing, and `implementation` is a default somebody
  picked — overridable with `--stage`. Related and reserved: **the chain across
  stage names**, since an audit capsule collecting at `--stage audit` cannot take
  the implementation state it was briefed with as its parent
  (`capsule-collect --stage audit --after implementation`, ~10 lines across two
  files).
- **Nothing has priced the state half from a *quarantine* origin.** The `e` run
  timed its refresh alone and could subtract it; the c→d migration's 9.618 s is
  one number with no breakdown. Cheap to take on the next migration and the one
  figure that would say whether reading a quarantine costs more than reading this
  host's checkout.
- **A probe's assertions are only as current as its last run**, and one count was
  never captured — `probe-netns-egress`'s last run recorded its colour and not
  its total, which is exactly the evidence
  [item 1](./ledger/001-what-has-been-run.md) says to read. Re-take the number.
- **The probes lost the host's DoT hop.** `~/flakes` stubs
  `DNSStubListenerExtra` on `10.101.0.1` and the probe fabric is `10.111.0.1`, so
  every probe falls back to `1.1.1.1` and says so
  ([item 38](./ledger/038-a-probe-that-became-a-borrower.md)). A two-line
  `~/flakes` edit; no assertion depends on it.
- **Three absent paths are still only reasoned**, never run: `baseline = null`,
  `caches = {}` and `guestConfig = {}` — the target contract's degradation paths
  ([contract-target.md](./contract-target.md)).
- **A namespace teardown is instrumented as a *program* and not as a *unit*.**
  `probe/netns-restart.sh` runs `capsule-netns` directly, 33/33
  ([item 37](./ledger/037-a-teardown-that-only-unnames.md)). What is outside it
  is systemd: ordering, the fact that a unit failing in `ExecStart` never runs
  `ExecStop`, and the start limit — two of which are what turned this bug from a
  failed restart into a recovery. That is a live-host claim and probably not a
  probe's shape.
- **Extras are fleet-wide, so the record's `extras` and `image` are still
  inert** — and `"extras": []` in a live record reads as a lie worth being able
  to answer: the *fleet* composes `agents` and `dev-facilities` at build time,
  and that field means *this assignment selected none*, because nothing selects
  yet. One list for every slot is what keeps one image; per-assignment selection,
  the store-path identity, the gcroot that retains it and the refusal to
  recompose under a dirty volume are all still Plan D D7. **Nothing selects
  extras, so nothing pins them** — no gcroot holds a resolved image and no
  refusal stops a slot's composition changing under a populated volume, which is
  safe only while the list is fleet-wide. And "one image" is an argument about
  the declaration rather than a reading of this host: the fleet has run as three
  runner store paths at once.
- **`generation` is read once and still never checked.** `capsule <slot> fetch`
  names `refs/capsule/<slot>/gen/<n>/` off it when a half is refused, and
  `handoff` renames by it — but nothing yet *refuses* on it. The refusal half — a
  command stating the generation it acts for, so a stale controller is told
  rather than obeyed — waits for D6. Nothing today can be stale, so nothing today
  notices the rest of the field is inert.
- **`capsule-provision` called directly still writes no record**, deliberately
  ([item 29](./ledger/029-the-record-is-front-end-written.md)). So a slot can be
  provisioned with no `base` pinned, and the only thing that says so is a missing
  key and a `-` in the `gen` column.
- **The two copies of the CLI are one store path by construction and nothing
  checks it.** `flake.nix` and `host/services.nix` both import `host/cli.nix`,
  and the claim that this is one derivation rather than two rests on the two
  argument sets being equal — which they were not, for `observe`, until a host
  rebuild said so. `hostModuleUnits` forces the module's programs, so a *missing*
  argument is caught at eval; a **different** argument would still produce two
  silently identical-looking programs. Narrowed by subtraction rather than
  checked: every argument that could differ now comes from one place.
- **`microvm -c capsule` would create a capsule with no perimeter.** The guest
  image is a flake attribute beside the slots — it has to be, since probes build
  `.#capsule` and match `microvm@capsule` — and `microvm -c` resolves any
  attribute. That instance would have no namespace, proxy or relay unit, so it
  boots into the root namespace. `capsule` and `just up` refuse the name because
  it is not declared; nothing else guards it
  ([item 28](./ledger/028-a-slot-has-no-default.md)).
- **The byte/disk bound on collect.** `ulimit -f` bounds one packfile, not the
  transfer — many small objects or a delta bomb go past it. A quota or a
  dedicated filesystem for the quarantine is the host-shaped answer. The state
  half has its own ceiling in a different place and for a different reason
  (`stateMaxBytes`, checked *in the guest* before the commit, because the fetch is
  atomic and an over-budget state half must skip rather than take the code refs
  down with it) — and `capsule-adopt` adds none: it reports the byte count and
  lets a human decide.
- **Three refusals are build-time-only and want a second target, not a second
  run**: `--unit` against a target with no hole
  ([item 32](./ledger/032-the-sideband-channel.md)), `capsule-adopt`'s gitlink
  mode class ([item 34](./ledger/034-adopting-a-guest-authored-tree.md)) — no
  target carries one — and the corrected `capsule-baseline` sizing, which has
  never produced a record because doctrine shares no inodes between `target/` and
  `.cargo` and so reconciles either way
  ([item 23](./ledger/023-second-target.md)).
- **`capsule-brief`'s count is truthful and the sentence beside it is not.** It
  says `differs from its HEAD in 0 paths` because every path doctrine declares is
  gitignored, so a brief carries the runtime tier and *not* the other agent's
  uncommitted tracked edits — which live only in the exhibit's
  `.capsule/dirty.diff` and are dropped at layout by design. The gloss describes a
  case doctrine does not produce.
- **Whether an injected credential survives use.** The token rotates on refresh
  and the capsule holds a copy, not the shared file — so host and capsule drift,
  and how long a capsule's copy stays good is unknown. `capsule-inject --force`
  is the answer until it is measured.
- **A rotated secret does not reach a running capsule either**, and for the same
  reason: every payload is write-if-absent, which is what makes injecting at
  every start a no-op rather than a clobber. Refreshing at start would discard
  what the guest wrote, silently, N times, so it is not policy
  ([item 22](./ledger/022-secrets-at-start.md)).
- **Quarantine retention** (doctrine has DEC-193 proposed). Two pieces of stale
  state on this host are the near-term case: `/var/lib/capsule/collect/` holds a
  `faux.git` from before a capsule named its own quarantine, and
  `/var/lib/capsule/doctrine.git` is the served mirror
  [item 18](./ledger/018-git-channel-direction.md) deleted the *service* for.
  Both are out-of-band cleanups, not flake changes.
- **Nothing outside a capsule's namespace can independently confirm its
  `ip_forward=0`.** This is what is left of `just status`'s blindness after
  `capsule all status`: the guard is the only reader of the inside of a
  namespace, so if the guard is wrong it is wrong alone. It holds egress bound
  to itself, which is why that is acceptable rather than merely unavoidable.
- **N=2 is not N, and nothing has a time series.** The stall figures are
  cumulative totals over each cgroup's life, so they bound how much and say
  nothing about when; `just load` has still never sampled a build. The
  **ratchet** is the term that decides how many fit — a capsule holds most of its
  ceiling until it is stopped, measured as 6141 MiB of `anon` for a guest
  reporting 481 MiB used, because firecracker has no balloon and no free-page
  reporting — so peaks are not additive across a working day. What replaces the
  6144 question is narrower and unmeasured: **how many hot slots actually fit**,
  ~7.5 GiB per built slot against this host's 60.4 GiB, and **whether any ceiling
  low enough to cut the charge is low enough to squeeze the guest**. 6144 was
  not, and nothing says where that boundary is; [plan-d](./plan-d-fleet.md) §0's
  recommendation needs rewriting rather than re-running.
- **Time-to-interactive is not 8.31 s.** "Usable" in [probes.md](./probes.md)
  means *provisioned* — that is the freshness probe's own definition. An
  interactive capsule is boot + provision + setup + a cold baseline build, and
  because `/work/home` is on the volume that freshness deletes, **setup is paid
  per fresh capsule**. Relatedly, the freshness probe still cannot take the cold
  build's price itself: its namespace has no upstream, so the 109 s and the 22
  assertions come from different runs and must not be quoted as one result.
- **`socat`'s `,nodelay` is shipped and unmeasured.** Bulk throughput over the
  relay is fine — 93.7 MiB/s out, 117.9 MiB/s back
  ([probes.md](./probes.md)) — but the per-packet fix that stopped interactive
  echo clumping has no figure.
- **`capsule <name> start|stop`'s two message branches are unexercised.** The
  epoch-scoped journal tail is verified both directions against a live unit; the
  branches that print them need a stopped or failing unit
  ([item 40](./ledger/040-no-doors-is-not-the-other-shape.md)'s class).
- `vm --help` creates `.vm/--help/`. Every argument is a VM name. Papercut.
