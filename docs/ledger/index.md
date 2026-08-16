# The ledger — one numbered item per question

> **CLOSED ARCHIVE. Item 54 was the last; there is no item 55.**
> New decisions go to `doctrine adr new`, durable gotchas to `doctrine memory
> record`, latent work to `doctrine backlog new`, epistemic claims to `doctrine
> knowledge new`. `NOTES item N` stays a valid citation form forever and nothing
> here is renumbered or deleted; an item may still be **resolved in place**.
> Why, and what the alternative cost: `ADR-002`.

**Cited from source and from the other docs as `NOTES item N`.** That citation
is an *id*, not a path: the numbers are frozen and append-only, a resolved item
is struck or annotated in place, never deleted and never renumbered, and the
file it lives in may change without any of the source comments citing it
changing with it.

**One file per item, and the number is the filename** — `NNN-slug.md`, so
`NOTES item 20` is `020-*.md` and reading one item costs one item rather than
1400 lines. The slug is a convenience and the number is the identity; if a slug
ever misleads, rename the file and leave the number alone.

**Adding one: no.** That was the rule while this was live, and it is recorded
because the archive's shape is a consequence of it. Nothing is appended now.

**The `state` column is a state, not an abstract** — a verdict plus at most one
clause naming what is outstanding, and never more than about two lines. Every
item carries a `*State:*` header of its own, so a longer row is a second copy of
it and this table stops being the cheap way in. Do not calibrate a new row
against the row above it: that is how items 36–54 reached an average of 2,662
characters against items 1–35's 145, with one cell at **10,618** — longer than
some whole items — and how this file reached 57 KB in 79 lines while promising
that reading one item costs one item
([item 54](./054-status-grew-a-changelog.md),
[item 15](./015-things-that-only-grow.md)). The rows were cut back on
2026-08-16; **if the recent ones are much longer than the old ones again, that
is the ratchet and not the work being more interesting.**

Resolved items are kept because the reasoning is the value — several of them
record a wrong first answer next to the measurement that corrected it, which is
what stops it being proposed again. Present tense belongs to
[status.md](../status.md) and figures to [probes.md](../probes.md); an item that
has become a bare status flag should shrink to a pointer at one of them the next
time it is touched.

| # | item | state |
| --- | --- | --- |
| [1](./001-what-has-been-run.md) | what has actually been run, versus reviewed | standing caveat |
| [2](./002-agent-credentials.md) | agent credentials into a guest with no shares | open |
| [3](./003-claude-code-unfree.md) | `pkgs.claude-code` is unfree, and guarded for channel drift | resolved |
| [4](./004-live-postgres.md) | `just test` may want a live Postgres | open, unhit |
| [5](./005-doctrine-binary-in-guest.md) | no `doctrine` binary in the guest | resolved — `dev-tools` |
| [6](./006-proxy-env-login-shell-scope.md) | proxy env is login-shell scope, so units don't inherit it | accepted |
| [7](./007-host-config.md) | host config — the accept, the forward drop, and checking the drop | resolved, plus one host edit outstanding (item 18) |
| [8](./008-git-daemon-unauthenticated.md) | git-daemon is unauthenticated | resolved by deletion (item 18) |
| [9](./009-egress-allowlist-unproven.md) | egress allowlist unproven; and the `MaxClients` hang that was not it | half — slots fixed, list still unproven |
| [10](./010-vendored-crates-dropped.md) | vendored crates and pre-seeded `node_modules`, dropped | decision |
| [11](./011-host-side-runs-as-you.md) | everything host-side runs as you | services half done, VMM half open |
| [12](./012-no-resource-ceiling.md) | no resource ceiling on the VM | open |
| [13](./013-host-smt-on.md) | host SMT is on | accepted, not fixed |
| [14](./014-hypervisor-choice.md) | hypervisor choice — firecracker's floor is what shapes half this list | open option |
| [15](./015-things-that-only-grow.md) | things that only grow: the volume, the proxy log, and a document | two measured and accepted, one fixed ([54](./054-status-grew-a-changelog.md)) |
| [16](./016-target-agnostic.md) | target-agnostic | done, and a second target has since exercised it — item 23 |
| [17](./017-more-than-one-capsule.md) | more than one capsule at a time | scoped — [Plan C](../plan-c-multi-capsule.md) |
| [18](./018-git-channel-direction.md) | which way the git channel points | measured, inverted, done |
| [19](./019-baseline-build-and-figures.md) | the baseline build, and where a figure is allowed to live | built, run, measured |
| [20](./020-which-capsule-a-program-means.md) | which capsule a host program is talking to | decided, built, run at N=2 on both paths |
| [21](./021-declared-capsule-flake-attribute.md) | a declared capsule needs a flake attribute, and all of them are one value | built and run at N=2 |
| [22](./022-secrets-at-start.md) | secrets at start, and a payload that may be absent | built and run at N=2 |
| [23](./023-second-target.md) | a second target, and what the parameterisation actually cost | done on branch `second-target` |
| [24](./024-set-u-not-login-shell.md) | a `set -u` script must not *be* the login shell | fixed and shipped, unwitnessed |
| [25](./025-assignment-is-a-perimeter-verb.md) | assignment is a perimeter-mutating verb | scoped in [contract-assignment.md](../contract-assignment.md); **being resolved by item 36**, half built |
| [26](./026-project-nix-runs-on-the-host.md) | a project's flake is code that runs on the host | open — scoped in [contract-flavour.md](../contract-flavour.md) |
| [27](./027-a-class-is-not-always-a-kilobyte.md) | a class is a kilobyte only over reservations the profile derives nothing from | settled for `mem` by eval, `vcpu` read from source |
| [28](./028-a-slot-has-no-default.md) | a slot has no default, and a front end is where one is guessed | built and run at N=2 |
| [29](./029-the-record-is-front-end-written.md) | the record is front-end written, and a pin is measured rather than resolved twice | built and run on this host |
| [30](./030-a-pool-audits-what-exists.md) | a pool degrades by auditing what exists, not by excluding what is declared | reviewed, built, run — closes [Plan D](../plan-d-fleet.md) L12, and **the pool is declared and switched**: `a`…`j`, costing 3% of an eval and one page of PID 1 at rest, guard reading `2 of 10` |
| [31](./031-the-fragment-vocabulary.md) | the fragment vocabulary: composition built, selection deferred | built, run, measured — supersedes item 3; selection is [Plan D](../plan-d-fleet.md) D7 |
| [32](./032-the-sideband-channel.md) | the sideband channel: state that is not a commit | built and run; extraction is item 34 and the inbound half is item 35, both now run — **the scope is closed**: `statePaths` is a template, the assignment fills `{unit}`, and the same exhibit is 36 entries against 1886 |
| [33](./033-provision-is-a-sequence.md) | a provision is not finished when the push lands | built, evaluated and **run** — inside a provision and standalone; step (3) of item 32's inbound half |
| [34](./034-adopting-a-guest-authored-tree.md) | adopting a guest-authored tree: what actually needed checking | built, evaluated, logic asserted against real git objects, **run** on the real 1886-entry exhibit |
| [35](./035-briefing-a-capsule-with-state.md) | briefing a capsule with another one's state | built, evaluated, guest half asserted at build time (`briefCases`), **run** across two live capsules — closes item 32's inbound step (2) |
| [36](./036-a-policy-is-selected-not-named.md) | a policy is selected from a declared set, never named by a project | **closed** — built, switched, and proven at the wire: two capsules on two policies at the same moment, `200` against `403`, swapping when the policies do |
| [37](./037-a-teardown-that-only-unnames.md) | a teardown that only unnames, and the check that could not have caught it | **fixed, switched and instrumented** — both netns programs roll back an aborted `up`; `probe/netns-restart.sh` 33/33 against 30/3 pre-fix; and `hostModulePrograms` builds every program the module's units name, which nothing had |
| [38](./038-a-probe-that-became-a-borrower.md) | a probe that became a borrower without changing | **fixed and enforced** — the egress fabric is `probe/harness.sh`'s, and `flake.nix`'s `probeFabric` **throws at eval** on any string `capsules.nix` declares. Both probes have since run green on it |
| [39](./039-a-bind-is-not-a-traversal.md) | a bind is mounted as root and opened as the user | **fixed, asserted at eval, switched and started** — the allowlist link has its own directory, and `hostModuleUnits` throws when a unit binds a path under a module-declared directory its user cannot traverse |
| [40](./040-no-doors-is-not-the-other-shape.md) | a fallback selected by absence, and the ten seconds a status row spent proving it wrong | **fixed and measured** — `door` asks for the tap rather than inferring from another slot's socket: ten status rows in 0.375 s against 10.06 s for one. Both arms are host state, so neither is case-covered |
| [41](./041-a-delegable-verb-that-ends-in-root.md) | a delegable verb that ends in root, and the half-write when it cannot | **fixed, asserted and switched** — the restart is inside the record's hook, so a failed bounce moves nothing, and the module grants exactly that one restart per declared slot. Exercised by [44](./044-a-rule-matches-a-path-not-a-name.md) |
| [42](./042-a-state-half-no-capsule-has-held.md) | a state half no capsule has ever held | **delivered** — slot `e`, as step (2) of one provision: 5.204 s end to end, the state half ≈0.65 s of it. Both origins, host and quarantine, have since run |
| [43](./043-a-grant-that-was-present-and-inert.md) | a grant that was present and inert | **fixed, asserted and switched** — sudoers is last-match-wins and a plain definition lands at priority 1000, where module merge order decides. The rule is `lib.mkAfter` and a third assertion reads the *rendered* config |
| [44](./044-a-rule-matches-a-path-not-a-name.md) | a rule matches a path, not a name | **fixed, switched and exercised** — the verb reaches root unattended, `sealed` and back on a cold ticket. A rule names a path, not a name, and `runtimeInputs` decides which path the caller actually runs |
| [45](./045-a-brief-is-an-origin-not-a-top-up.md) | a brief is an origin, not a top-up | **half answered** — the composite it argued for is built and has run. **Still open: whether a top-up is a scoped additive verb or a refusal**, which no delivery so far settles, since each removes the window rather than serving a capsule inside it |
| [46](./046-bash-until-the-record-stops-being-flat.md) | bash, and the three things that would end it | **decided, and the decision is to change nothing** — the six failures that look like a language problem are one class, *structure passed through text at a boundary*, and every fix was the same move. The trigger is recorded, not a verdict |
| [47](./047-a-script-on-stdin-and-the-command-that-eats-it.md) | a script on stdin, and the command that eats it | **fixed twice over, cased, switched and delivered** — a host-authored guest script *is* the guest shell's stdin, so a target command that reads stdin reads the rest of the script and bash exits 0 with most of it unrun |
| [48](./048-a-forwarded-port-is-host-state.md) | a forwarded port is host state, and nothing allocates one | **open, nothing built** — *reach* exists (`-L` through the relay socket); **allocation** does not. Nothing stops two capsules claiming one host port, and `capsule <n> ssh` cannot say `-L` at all |
| [49](./049-who-owns-a-state-directory.md) | who owns a state directory, and the read nobody has taken | **both reads taken, and they found a different failure than this item was written about; the constraint that replaces it is asserted, built and switched.** Plan D's D3 and D7 are ungated |
| [50](./050-a-quarantine-outlives-its-assignment.md) | a quarantine is keyed by a slot, and a slot outlives an assignment | **third finding fixed and green; the key is still the slot** — `capsule <slot> fetch` answers for the code and state halves separately and prints the archive as the remedy. A slot's second assignment still overwrites the first's refs |
| [51](./051-the-target-in-four-store-paths.md) | the four programs still spell the target, and it is item 20 one level up | **closed** — no host-side program is a function of which project this host confines: each takes `--profile <name>` and refuses without one, and none carries a target's values, its name, or its own existence. Step 5 belonged to [52](./052-the-document-leaves-the-store.md) |
| [52](./052-the-document-leaves-the-store.md) | the document leaves the store, and a pin becomes necessary | **closed — all three steps.** The documents are out of the store, every predicate about one is the reader's, and a slot is pinned to the bytes it was provisioned under. **The pin has never been exercised live** |
| [53](./053-three-coarse-verbs.md) | three coarse verbs, and the words that must not enter them | **built and green — all three verbs, and nothing of the item is unbuilt.** What is left is a first live exercise: the verify, the archive, the drop and the force have run in a sandbox and nowhere else |
| [54](./054-status-grew-a-changelog.md) | status.md grew a changelog, and it grew where the commit stopped | **resolved by construction** — status.md 2463 → ~290 lines, five evicting entries with the rule written in the file. The changelog grew exactly where the commit message stopped carrying the session. **Nothing enforces the bound** |
