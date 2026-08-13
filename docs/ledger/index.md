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
| [22](./022-secrets-at-start.md) | secrets at start, and a payload that may be absent | built, unrun on this host |
| [23](./023-second-target.md) | a second target, and what the parameterisation actually cost | done on branch `second-target` |
| [24](./024-set-u-not-login-shell.md) | a `set -u` script must not *be* the login shell | fixed in-tree, unshipped on this host |
| [25](./025-assignment-is-a-perimeter-verb.md) | assignment is a perimeter-mutating verb | open — scoped in [contract-assignment.md](../contract-assignment.md) |
| [26](./026-project-nix-runs-on-the-host.md) | a project's flake is code that runs on the host | open — scoped in [contract-flavour.md](../contract-flavour.md) |
