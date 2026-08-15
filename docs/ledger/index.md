# The ledger — one numbered item per question

**Cited from source and from the other docs as `NOTES item N`.** That citation
is an *id*, not a path: the numbers are frozen and append-only, a resolved item
is struck or annotated in place, never deleted and never renumbered, and the
file it lives in may change without any of the 39 source comments changing with
it.

**One file per item, and the number is the filename** — `NNN-slug.md`, so
`NOTES item 20` is `020-*.md` and reading one item costs one item rather than
1400 lines. The slug is a convenience and the number is the identity; if a slug
ever misleads, rename the file and leave the number alone.

**Adding one:** a new file with the next number, a row at the bottom of the
table, and a state. Nothing else moves.

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
| [15](./015-things-that-only-grow.md) | two things that only grow: the volume, and the proxy log | measured, accepted |
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
| [36](./036-a-policy-is-selected-not-named.md) | a policy is selected from a declared set, never named by a project | **built** and unswitched — the vocabulary, each slot's set, the allowlist and both collect limbs, plus `capsule <slot> policy <name>` and 28 cases. The live claim is written and unrun |
