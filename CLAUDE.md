@.doctrine/state/boot.md
If you have NOT seen `BOOT-SENTINEL: doctrine-governance-snapshot` anywhere in your context (system prompt or preceding messages), you MUST read the file referenced above now. If you HAVE seen it, you MUST NOT — the content is already in context.

# CLAUDE.md

Firecracker microVM used to confine a coding agent working on one target repo
(`target.nix`; here `~/dev/doctrine`). [README.md](./README.md) is usage;
everything else is [docs/](./docs/index.md), which maps question to file.

**Governance is doctrine's** — `.doctrine/project-orientation.md` is the way in,
and `ADR-001` is the scope: routing here is backlog-first, larger programs of
work get a slice, and this repo's id space is strictly separate from the
doctrine corpus it confines. **No file holds the present tense** —
`capsule all status` says what is true on this host, `doctrine backlog list` what
is next, `doctrine knowledge list` what is open, and `STD-001` is the rule for
what any of it counts as evidence for. Two more before proposing changes:
[docs/ledger/](./docs/ledger/index.md) is a **closed archive** of rationale and
gaps, one file per item (`NNN-slug.md`) — **several obvious-looking ideas are
recorded there as considered-and-rejected** — cited from source as `NOTES item
N`, an id and not a path, so those numbers are frozen. It stops at item 54 and
takes no more (`ADR-002`); a new decision is `doctrine adr new`, a durable gotcha
is `doctrine memory record`, latent work is `doctrine backlog new`, an epistemic
claim is `doctrine knowledge new`. And [docs/probes.md](./docs/probes.md) owns
every measured figure, so link to it rather than copying a number out.

Plans are scoping, not commitments: `plan-b-other-jails.md` is the
non-firecracker shapes, `plan-c-multi-capsule.md` is what N capsules on one host
would cost, `plan-e-room.md` is a guest that is **not** a capsule — several
people ssh'd into one shared box — and is the first test of whether the
machinery underneath is separable from the product. Do not put present-tense
state in a plan; that is a backlog or knowledge record's job.

## Working here

capsule C is driving a production workload (doctrine's SL-251).

**Be judicious about running nix builds or evals.** The user runs those
in ~/flakes for system builds themselves. Builds for this project are fine. 
Be conservative beyond that.

Verify with `just check` (`nix-instantiate --parse` over every file, plus `alejandra -c`; neither
evaluates). `just` (default) runs the build, units, and fmt.

**There are three kinds of check here, and they are not interchangeable.**
`just check` parses and formats without evaluating. `hostModuleUnits` *evaluates*
the NixOS module — what it says, including its programs, since a unit graph does
not mention them. `guardCases`, `briefCases`, `snapshotCases`, `refreshCases`, `observeCases`,
`baselineCases`, `policyCases`, `profileCases` and `gitChannelCases`
*run* a host-side
program's own text with a substitute for the one thing tying it to this host
(`just cases`), and are the answer whenever the interesting branches are ones a
live host can only reach destructively or expensively — the guard's by unnaming a
namespace under a running guest, the brief runner's by dirtying one capsule's
worktree to watch another refuse it, the state snapshot's by driving a real unit
of work in a checkout that holds several, the refresh's by giving it a target
command that fails or eats its own stdin, the baseline's by having a build that
can be asked to fail, the status's by catching an unprovisioned volume or a run
in flight before it leaves that state, the front end's by editing the declared
pool and writing the live record of a slot somebody is using, the profile's by
holding two targets at once and by handing the render a target no host declares,
and the git channel's by confining a second project. **That last is the only one
over a program that talks to a guest, and what it can reach is everything
upstream of the door** — `pkgs.openssh` is in its subjects' `runtimeInputs`, so
nothing in a sandbox can stub `ssh`, and that is a boundary to respect rather
than work around.
**A suite that composes a program's command line by hand pins only one end of
it.** `snapshotArgs` and `observeArgs` are an order of values printed at one end
and read at the other, and a suite spelling that order itself would agree with
itself while the two ends disagreed — silently, in the status's case. So those
two suites build the tail from the *shipped fragment* and run the *shipped
script* with it.
All three kinds are in `just build`, so a failing case is a failing
build — **check that when you add one**: `observeCases` and `baselineCases` were
written, wired into `just cases`, and left out of `just build` for a session
(NOTES item 51 step 3). **One suite per file, beside the program it pins** —
`host/<name>-cases.nix`, a function of `pkgs`, `lib` and **the store path the
program ships**, with a short `import` in `flake.nix` (NOTES item 51 step 0).
Three of them are handed a fixture instead and say so in their headers: the
guard's stubbed kernel, the front end's pool that is not this host's, the
profile's target that is nobody's. A new suite goes in
its own file and takes its subject as an argument — never a second render of the
text it claims to pin. **A suite whose subject is a *library* rather than a
program** takes the fragment its callers get and splices it into the smallest
`main` that exercises it (`host/profile-cases.nix`); and when what it pins is a
`throw` rather than a program, the verdicts are read at eval with
`builtins.tryEval` and asserted in the shell, which is `hostModuleUnits`'
arrangement one level down.

The seam that makes the third kind possible is worth reusing rather than
reinventing: `writeShellApplication` prepends `runtimeInputs` to `PATH`, so a
test cannot stub `ip` by prepending its own. **A program that needs testing takes
as an argument the one thing that ties it to this host** — `host/guard.nix`'s
`tools` and `host/cli.nix`'s `moduleState`, an argument with a default so both
shipped copies stay one store path — exactly as all of them take `transport`.
**For the five guest-pushed scripts that argument is now a *run-time* one**
(NOTES item 51): `state-snapshot`, `refresh`, `brief`'s runner, `observe` and
`baseline`'s runner take their checkout — and their ceiling, their command, their
declared paths — on the command line, so a suite runs the store path a capsule
runs rather than a second render of the same text, and one program serves any
number of targets. **And the host side of that command line is built from a
document at run time** (item 51 step 4), so each of those files exports the *tail*
as a shell fragment and no call site can order the values differently.
`host/guest-exec.nix`'s `loginRun` is `bash -l -c 'bash -s "$@"'` for exactly
that reason and `host/baseline.nix` uses the same `"$0" "$@"` shape to keep a
third parse out of a staged run.
**How many times a value is escaped depends on where it lives, and the count went
down by one.** A value *spliced into a program's text* crosses **two** shells —
this host's, building the ssh argv, and the guest's, handed one string — and is
escaped twice. A value that is an **array element at run time** is not parsed by
this host's shell at all, so exactly one `%q` is right and two arrive
backslashed; `profileQuote` (host/profile.nix) is that one filter, and it can be
line-based only because the render refuses a newline in any value. Two
rules for writing a case: assert the *reason* as well as the exit status, since a
refusal for the wrong reason is a different program passing; and check the suite
can fail by mutating the behaviour it claims to pin — the skip in
`host/guard.nix` was reverted to its old form once, on purpose, to watch the case
for it go red.

**`probe/` is evidence, not scaffolding.** Each probe answers one design
question and is kept so the answer stays checkable — `probe/netns.sh` is what
PLAN_C's addressing and isolation decisions rest on. They need root, so they are
the user's to run (`sudo probe-netns`); `just build` shellchecks them. Write new
ones the same way: assert both directions, since a denial-only network test
passes for the wrong reason, and never borrow live addressing — a probe on the
real `/30` tests the real capsule — **nor a live *name***. Both halves of that
are now *enforced* rather than asked for: `flake.nix`'s `probeFabric` holds every
name, link, address and network a probe's egress fabric is built from, and
`borrowed`, its intersection with what `capsules.nix` declares, **throws at
eval**. Don't reach around it. The reason it exists rather than a comment is
[NOTES item 38](./docs/ledger/038-a-probe-that-became-a-borrower.md), and the
shape generalises: `probe/netns-egress.sh` shared `cap-egress`, `eg-up`/`eg-rt`,
both addresses and the whole `10.100.0.0/16` with production **without ever
borrowing them** — it verified the shape first and `capsules.nix` was written
from its map afterwards, so the probe became a borrower by standing still while
the declaration moved onto it. Its cleanup trap deletes `eg-rt`, the fleet's
uplink, by name; only three refusals sitting ahead of the trap kept that
theoretical, and following one of them cost a guard failure and a recovery. **A
probe that verifies a shape before the shape is declared becomes a borrower the
moment the declaration copies it, and there is no diff to notice.** **And a probe's set-up produces the state it needs
rather than inheriting something that resembles it** (NOTES item 37, three
faults in one file): `|| exit 1` on a set-up step kills the run with no report at
exactly the moment the program under test is broken; tolerating a failed set-up
lets residue — a link on its way out — satisfy the precondition and be reaped
before the assertion, so the control passes for the wrong reason; and a round
that inherits the previous round's wreckage makes every later red name the wrong
round. Never ask the program under test to clean up after its own failure.
**Mutate and re-run**: build the probe against a deliberately broken copy of
what it tests and check *which* rounds go red — that is how all three of those
were found, and how a round that resembles the real failure but never
discriminates gets caught. `probe/harness.sh` is concatenated ahead of
each probe by the `probe` builder in `flake.nix`, not sourced, so shellcheck
sees one file; values from `net.nix`/`target.nix` reach a probe through that
builder's `prelude` rather than being spelled in the script. **The harness comes
first and the prelude second**, so the harness can declare an empty default for
every injected value — which is what lets it carry the egress fabric without
every probe that never builds one tripping SC2154, and it means a prelude
assignment wins over that default rather than being overwritten by it. **Quote them
there** — an unquoted `TAP=vm-capsule` reads as arithmetic to shellcheck
(SC2100) once the harness has a `vm` variable in scope, and
`writeShellApplication` fails the build on it. The harness carries four verbs,
not three: `check` a verdict, `observe` a finding, `measure` a figure (a round
whose bar is a price needs numbers beside the assertions), and `report`. It also
carries the whole capsule-in-a-namespace boot — `ns_up`, `capsule_boot`,
`wait_guest`, `halt_guest` — because `netns-boot.sh` and `freshness.sh` assert
and measure the same shape, and two copies of a boot sequence are two answers
the first time one is edited. Same rule, same file, for **the egress fabric** —
`egress_up`, `egress_attach`, `egress_resolver`, `egress_rules`, `proxy_up`,
`guest_connect` — since `netns-egress.sh` and `two-capsules.sh` both put a proxy
in a namespace and ask the guest to get out.

**A VMM is identified by its namespace, never by its name.** The one-image lever
means every capsule runs the same runner from the same store path, so all of
them are `microvm@capsule` in the process table: `pkill -f` on that name is a
power cut for the siblings, and it reads as a clean teardown while doing it.
`vm_running`, `wait_vm` and `halt_guest` all take a namespace and scope
themselves with `ip netns pids`; the unscoped question survives as
`any_vm_running`, which is what a probe's refusal wants and the only thing it is
for. The thing that isolates a capsule is the same thing that names it — no
pidfile, no registry. `probe/netns-boot.sh` is the deliberate exception to the
addressing rule and says why in its header: it boots the real guest, whose image
has `net.nix` in it, so the real capsule *is* the subject.

Formatting is alejandra, 2-space indent, matching doctrine's flake.

**Commit often, and make the message carry the session.** There is no changelog
here — `git log` is the record and the ledger holds the reasoning — so a commit
message is load-bearing rather than a courtesy. The house style is a
`feat:`/`fix:`/`doc:` subject naming *the finding*, not the file touched:

```
fix: a teardown that only unnames, and the programs nothing built
doc: item 36 is closed at the wire, and item 38 is why the fabric moved
feat: two capsules on two policies at once, on a fabric that is nobody's
```

Cite the item (`NOTES item N`), say what was **not** exercised, and commit at
each piece rather than at the end of a session — a green suite sitting
uncommitted is a piece of work whose only record is prose someone has to
maintain by hand. This is not a preference: the one time the messages became
`053.2` and `51.6`, a 720-line reverse-chronological log grew at the top of
[docs/status.md](./docs/status.md) to hold what they had stopped carrying, in
the one file whose contract is the present tense
([NOTES item 54](./docs/ledger/054-status-grew-a-changelog.md)). **Content lands
somewhere.** If the commit will not take it, it accretes in the nearest file with
no size bound, one entry at a time, with no diff big enough to notice.

## Architecture invariants

**These are `POL-001`…`POL-004`, `required`, and they are in your context
already** — the boot snapshot at the top of this file carries every active policy
and standard, so they are governed and queryable rather than prose here. Read one
with `doctrine policy show POL-00N`. Break one and the confinement stops meaning
anything.

| | |
| --- | --- |
| **`POL-001` The perimeter is host-side** | egress filtering, the forward drop, no default route in the guest, root only by ssh key. Guest-side settings are convenience, not security. Part of the perimeter lives in `~/flakes` and the drop is verified at run time, not assumed |
| **`POL-002` Nothing generic learns what the target is** | *would a different target need this code changed, or only a different value?* The smell is a toolchain's name outside `target.nix`. Everything beyond the contract is declared, optional, and has a working absent path |
| **`POL-003` One declaration per axis, and no implicit default** | `net`, `capsules.nix`, `policies.nix`, `target.nix`, `probeFabric` — one home each, nothing named implicitly, and resolution is the front end's act and never a program's |
| **`POL-004` Reusable code knows nothing about the jail** | `perimeter/` and `host/git-channel.nix` take injected fragments. A program that needs testing takes as an argument the one thing that ties it to this host — which is what makes the case suites possible at all |

**Adding one is `doctrine policy new`, not a row above.**

The surface `POL-002` produces is written down field by field:
[docs/contract-target.md](./docs/contract-target.md) is what any repo must supply
and may rely on, and
[docs/contract-doctrine.md](./docs/contract-doctrine.md) is doctrine's two roles.
Update them in the same commit as anything that moves the boundary.

## Firecracker constraints and the gotchas that have already cost time

**These moved into the memory corpus and are not restated here** — one copy, so
nothing drifts, which is `NOTES item 54`'s lesson applied to this file. Each is
scoped by path, glob or command, so the ones that bear on what you are touching
surface when you touch it. Read one with `doctrine memory show <key>`; sweep the
set with `doctrine memory search --tag gotcha`.

The index, so you know a thing exists before you trip over it:

| gotcha | key (`mem.…`) |
| --- | --- |
| Firecracker's floor: no shares, no passthrough, no balloon, no jailer — **no host directory can ever be mounted into the guest** | `fact.oubliette.firecracker-constraints` |
| A tap cannot be swapped under a running VM | `fact.oubliette.tap-swap-under-running-vm` |
| A guest poweroff does not exit the VMM; a guest reboot does — and the success path reads like a crash | `fact.oubliette.poweroff-does-not-exit-the-vmm` |
| A dead guest does not mean a dead VM, and **a VMM is identified by its namespace, never by its name** | `fact.oubliette.dead-guest-is-not-a-dead-vm` |
| A `set -u` script must never *be* a login shell; the symptom is a wrong exit status | `fact.oubliette.set-u-script-must-not-be-a-login-shell` |
| The serial console's TUI input quirk is fixed and nobody knows why | `fact.oubliette.serial-console-tui-input` |
| The guest's clock is UTC and this host is AEST | `fact.oubliette.guest-clock-is-utc` |
| On the module path a missing `microvm -c` fails as a dependency, not as itself | `fact.oubliette.missing-microvm-create-fails-as-a-dependency` |
| `microvm -c` takes no flake fragment, and omitting `-f` is worse than forgetting it | `fact.oubliette.microvm-create-takes-no-fragment` |
| A newline in a unit directive silently deletes the rest of the drop-in | `fact.oubliette.newline-in-a-unit-directive` |
| **Forcing proves a derivation evaluates; only building proves its text is a program** | `pattern.oubliette.forcing-is-not-building` |
| A hardened unit that may not read `/proc` gets a short answer, not an error | `fact.oubliette.proc-read-needs-cap-sys-ptrace` |
| `BindReadOnlyPaths` is mounted as root and opened as the unit's user, so a bind is not an access | `fact.oubliette.a-bind-is-not-an-access` |
| The devshell's programs shadow the module's and carry different transports | `fact.oubliette.devshell-programs-shadow-the-modules` |
| The module's programs on `PATH` are wrappers, so reading one answers about the wrapper | `fact.oubliette.module-programs-on-path-are-wrappers` |
| `capsule-host` children orphan easily, and `wait -n` must name its pids | `fact.oubliette.capsule-host-children-orphan` |
| The two paths cannot see each other by probing | `fact.oubliette.two-paths-cannot-probe-each-other` |
| A fresh capsule has fresh ssh host keys at the same address | `fact.oubliette.fresh-capsule-fresh-host-keys` |
| `sudo` strips `SSH_AUTH_SOCK`, and the guest's key is `~/.ssh/id` | `fact.oubliette.sudo-strips-ssh-auth-sock` |
| Extracting a guest-authored tree: `..` is not the escape test and `tar -x` is not the extractor | `pattern.oubliette.extracting-a-guest-authored-tree` |
| A `just` recipe's trailing command is evaluated on **this host**, not carried as argv | `fact.oubliette.just-interpolation-is-text-not-argv` |
| `CAPSULE_STATE` moves the quarantine and not the record — and `capsule-adopt` has no transport | `fact.oubliette.capsule-state-moves-the-quarantine-not-the-record` |
| `nix run`/devshell binaries are store paths, so an edited program is stale until rebuilt | `fact.oubliette.devshell-binaries-are-store-paths` |
| `denyCurrentBranch` only governs the branch HEAD names | `fact.oubliette.deny-current-branch-only-governs-head` |
| `git+file:` inputs read committed HEAD | `fact.oubliette.git-file-inputs-read-committed-head` |
| `~/flakes` builds this repo two ways and only one of them is the lock | `fact.oubliette.flakes-builds-this-repo-two-ways` |
| Set `CAPSULE_KEEP=1` before a probe run you might need to read | `fact.oubliette.capsule-keep-before-a-probe-run` |
| `environment.variables` is login-shell scope | `fact.oubliette.environment-variables-is-login-shell-scope` |

**Adding one is `doctrine memory record`, not a row above.** A row with no memory
behind it is the ratchet starting again in a new file.

## Conventions

- Guest modules live in `vm/`; `common.nix` holds only what every VM needs, and
  sizes are `lib.mkDefault` so each VM can override. Host-side NixOS modules
  live in `host/` and are exported from `flake.nix`, opt-in — the devshell path
  must keep working with no rebuild and no root.
- Host-side helpers are `writeShellApplication` (shellcheck runs at build, so an
  unused variable is a build failure — hence `paths` in `perimeter/` being a
  function each program calls with only what it uses).
  `perimeter/egress-allow.txt` is deliberately a plain file, not a store path,
  so the allowlist can change without a rebuild.
- **Two paths run the same code.** `capsule-host` composes the proxy plus the
  watch in the foreground as you; `host/services.nix` runs the same proxy as a
  unit under `capsule-proxy`, and installs the same two git-channel programs
  wrapped with its own paths. Don't grow a second implementation for either — if
  a unit needs something, it comes from the same program. **Two programs read the
  real repo** — `capsule-provision`, and `capsule-brief --from-host` for a unit
  no capsule has driven yet (NOTES item 42) — and both always run as the human.
  The second writes one ref there and drops it again: it **keeps no archive**,
  because a quarantine is what a capsule sent back rather than a place state
  lives, which is the same decision that makes a source name which is not a
  declared slot a refusal.
- **The guest's tool set has two owners, and which one a tool has decides where
  it goes.** `compose(floor, extras)`: the **floor** is the target's —
  `target.nix`'s `toolsPackage`, for doctrine `packages.dev-tools` — so a tool
  the project builds or tests with goes in *that repo's* flake and the VM cannot
  drift from its devshell. The **extras** are the host operator's, and they are
  `fragments.nix`'s vocabulary selected by `extras` in `flake.nix`: `rg`, an
  editor, an agent CLI — anything that is nobody's project. Putting a
  convenience in `target.nix` says doctrine needs it, which is the ownership
  smell pointed the other way (NOTES item 31,
  docs/contract-flavour.md). A fragment's source is a flake input of *this*
  repo, pinned here, and convenience is **declared** — never scraped from a
  human's `$HOME`, which would describe a machine the capsule is not. One list
  for the fleet today, so one image; per-slot selection is Plan D D7. The jailed
  `claude`/`codex` bwrap wrappers are still excluded — they bind host paths that
  do not exist in the VM.
