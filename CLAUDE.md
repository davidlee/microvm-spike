# CLAUDE.md

Firecracker microVM used to confine a coding agent working on one target repo
(`target.nix`; here `~/dev/doctrine`). [README.md](./README.md) is usage;
everything else is [docs/](./docs/index.md), which maps question to file. Three
of them before proposing changes: [docs/status.md](./docs/status.md) is where
the work is up to, [docs/ledger/](./docs/ledger/index.md) is the numbered ledger
of rationale and gaps, one file per item (`NNN-slug.md`) — **several
obvious-looking ideas are already recorded there as considered-and-rejected**,
and it is cited from source as `NOTES item N`, which is an id and not a path, so
those numbers are frozen — and [docs/probes.md](./docs/probes.md) owns every
measured figure, so link to it rather than copying a number out.

Plans are scoping, not commitments: `plan-b-other-jails.md` is the
non-firecracker shapes, `plan-c-multi-capsule.md` is what N capsules on one host
would cost. Do not put present-tense state in a plan; that is `status.md`'s job.

## Working here

capsule a has finished driving a production workload (doctrine's SL-254).

**Be judicious about running nix builds or evals.** The user runs those
in ~/flakes for system builds themselves. Builds for this project are fine. 
Be conservative beyond that.

Verify with `just check` (`nix-instantiate --parse` over every file, plus `alejandra -c`; neither
evaluates). `just` (default) runs the build, units, and fmt.

**There are three kinds of check here, and they are not interchangeable.**
`just check` parses and formats without evaluating. `hostModuleUnits` *evaluates*
the NixOS module — what it says, including its programs, since a unit graph does
not mention them. `guardCases`, `briefCases` and `snapshotCases` *run* a host-side program's own
text with a substitute for the one thing tying it to this host (`just cases`),
and are the answer whenever the interesting branches are ones a live host can
only reach destructively or expensively — the guard's by unnaming a namespace
under a running guest, the brief runner's by dirtying one capsule's worktree to
watch another refuse it, the state snapshot's by driving a real unit of work in
a checkout that holds several. All three kinds are in `just build`, so a failing case is a failing
build.

The seam that makes the third kind possible is worth reusing rather than
reinventing: `writeShellApplication` prepends `runtimeInputs` to `PATH`, so a
test cannot stub `ip` by prepending its own. **A program that needs testing takes
as an argument the one thing that ties it to this host** — `host/guard.nix`'s
`tools`, `host/brief.nix`'s guest `runner` and `host/state-snapshot.nix`'s
`snapshotFor`, both taking the checkout they run in — exactly as all three take
`transport`: one text, two instantiations, no second copy of an invariant. Two
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
real `/30` tests the real capsule. `probe/harness.sh` is concatenated ahead of
each probe by the `probe` builder in `flake.nix`, not sourced, so shellcheck
sees one file; values from `net.nix`/`target.nix` reach a probe through that
builder's `prelude` rather than being spelled in the script. **Quote them
there** — an unquoted `TAP=vm-capsule` reads as arithmetic to shellcheck
(SC2100) once the harness has a `vm` variable in scope, and
`writeShellApplication` fails the build on it. The harness carries four verbs,
not three: `check` a verdict, `observe` a finding, `measure` a figure (a round
whose bar is a price needs numbers beside the assertions), and `report`. It also
carries the whole capsule-in-a-namespace boot — `ns_up`, `capsule_boot`,
`wait_guest`, `halt_guest` — because `netns-boot.sh` and `freshness.sh` assert
and measure the same shape, and two copies of a boot sequence are two answers
the first time one is edited.

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

## Architecture invariants

Break these and the confinement stops meaning anything:

- **The perimeter is host-side.** Egress filtering (tinyproxy allowlist) runs on
  the host, where the guest cannot reach it. Git is not a control at all any
  more: the host initiates both directions and the guest has no remote, so what
  used to be a ref restriction enforced by a hook is now the absence of a
  channel (NOTES item 18). Guest-side settings — proxy env vars, the
  unprivileged `agent` user, `receive.denyCurrentBranch` — are convenience and
  clumsiness-guards, not security. Never move a control from the host into the
  guest.
- **`perimeter/` knows nothing about the jail.** It builds the proxy and
  `capsule-host` from addresses, a port, and two injected shell fragments —
  `preflight` (once, before anything binds) and `watch` (supervised child; exits
  nonzero when the perimeter is gone, which tears the proxy down). No tap name,
  no hypervisor, no Linux-only tool goes in there — that is what lets a seatbelt
  or VM-based shape reuse it (docs/plan-b-other-jails.md). Anything
  platform-shaped belongs at the call site in `flake.nix` (`perimeterChecks`).
  `host/git-channel.nix` has the same seam for the same reason: it knows a git
  URL and a `transport` fragment, both injected, and nothing about taps or
  namespaces. That fragment is also what lets one store path serve N capsules —
  it resolves `--capsule <name>` at run time and sets `ssh_cmd`, so a capsule's
  socket is derived from its name instead of built into four programs (NOTES
  item 20). Don't let a program probe for which transport to use: that bakes
  both into it.
- **Part of the perimeter is not in this repo.** The firewall port, the
  forward-chain drop on the tap, and the sudoers rule that makes the drop
  readable all live in the host's NixOS config (`~/flakes`) — README "Host
  requirements". It is one port now, not two: dropping 9418 there is an
  outstanding host-config edit (NOTES item 18). Anything proposed here that
  assumes the host is unconfigured, or that tries to compensate for it
  guest-side, is wrong twice. The drop is
  *verified at run time*, not assumed: unverifiable-and-forwarding is a refusal
  to start, and forwarding coming up mid-session kills egress. Don't soften
  that to a warning — a warning is what it had while the drop was in fact
  missing from the host config.
  **All of that is the devshell path.** On the module path the tap is inside a
  namespace `host/netns.nix` creates, so the control is that namespace's own
  `ip_forward`, the sudoers rule and the `latent` state are gone, and the host
  config's remaining job — forwarding, NAT, the resolver stub — the module
  installs itself. Two shapes, one at a time: `capsule-host` refuses while a
  `capsule-proxy-*` unit is active.
- **No default route in the guest.** The only egress is the proxy. Adding NAT
  or a gateway would silently void the allowlist — and so would leaving the
  host forwarding for the tap, since guest root can add the route itself.
  Guest kernel hardening (`lockKernelModules`) raises the cost of getting that
  root; it is not what makes the claim true.
- **Root is reachable only by ssh key from the host.** The agent has no sudo and
  no su, by design.
- **`net` in `flake.nix` is the single source of truth** for tap name, both
  addresses, MAC and the proxy port. It is threaded to the guest via
  `specialArgs`. Don't hardcode an address anywhere else.
- **A slot has no default, and its name means nothing.** `capsules.nix` declares
  which slots exist (`a`, `b`) and nothing anywhere names one implicitly: the
  four host programs take `--capsule <name>` or `CAPSULE_NAME` and **refuse**
  without one, the `capsule` front end resolves an unnamed verb to the slot that
  is *up* (refusing when none or several are), and no `just` recipe spells a
  name — the delegating ones pass none and the lifecycle ones require one
  (NOTES item 28). `capsule` as a flake attribute is the guest **image**, not a
  slot: probes build `.#capsule` and match `microvm@capsule`, so it has to stay
  a real attribute even though it is not declared in `capsules.nix`.
- **`target.nix` is the same deal for the repo under confinement** — name, path,
  tools package, allowlist file, caches, sizes. Threaded the same way. It has
  **no branch field** and gets none back: the guest's branch is `workBranch` in
  `flake.nix`, a constant, because a name that identifies the work is not
  project state (docs/contract-target.md). `capsule-provision <ref>` is a ref in
  the target repo and is the other thing called a branch here.
  `statePaths` is a **template** list, not a path list: each entry may hold one
  `{unit}`, filled at collect by an opaque token the assignment carries, and a
  hole with no unit refuses rather than collecting everything (NOTES item 32).
  That is the shape for anything a policy must scope by run-time state — the
  policy says *where* the hole is, the assignment says *what* fills it, and the
  token is bounded (`host/quarantine.nix`'s `checkToken`) so it can name an
  instance and never widen a perimeter.
  `doctrine` may appear in exactly two places: `target.nix`, and
  `inputs.target.url`, which cannot be computed. Nothing target-shaped goes in
  `perimeter/`, `vm/capsule.nix` or the justfile; it comes from there as a
  value. And nothing target-shaped is ever read *out of the target repo* — the
  agent can edit that (NOTES item 16). `target.guestPath` is the one path both
  sides share, which is why it is derived there rather than spelled in the guest
  and again in the host's git channel.
- **doctrine is the guinea pig, not the design.** The capsule is the product and
  the confined repo is a client, so every target need must be met by a *generic
  capability plus a value the target supplies* — never by the generic code
  learning what the target is. doctrine's needs may inform a default; they may
  never carry the mechanism. Three limbs:
  1. **Generalise before implementing.** For each target-shaped want, name the
     capability it is an instance of, and build that. doctrine wants its cargo
     config tuned to the capacity it has been given; the capability is *render
     static guest config from the instance's declared reservation*. Not "support
     cargo", and emphatically not "copy the human's `~/.cargo/config.toml`" —
     which is a third failure, a config describing a machine the capsule is not.
     The smell is a toolchain's name (`cargo`, `bun`, `sccache`) appearing
     anywhere but `target.nix`.
  2. **Anything beyond the contract is declared and optional.** The contract is
     *be a git repo on this host, and expose one flake package that is your
     devshell's tool set* (NOTES item 16). Everything else is a `target.nix`
     field with a working absent path — `toolsPackage = null` already degrades
     rather than breaks, and a second target must be able to omit any field
     doctrine happens to set.
  3. **Fix transient local state out-of-band.** A one-off in `~/flakes`, this
     host's disk, or one repo's history is fixed by hand and not by permanent
     leniency in the flake. Strict-and-owned beats lenient-and-coupled: it fails
     loudly here, and it is the only thing that ports.

  The review challenge, which is the whole point: *would a different target need
  this code changed, or only a different value?* If the code, it is in the wrong
  place. This is doctrine's own POL-002 (platform independence from host-project
  conventions and state) pointed the other way — the same discipline, with this
  repo as the platform and doctrine as the host.

  The surface this rule produces is written down field by field:
  [docs/contract-target.md](./docs/contract-target.md) is what any repo must
  supply and may rely on, and
  [docs/contract-doctrine.md](./docs/contract-doctrine.md) is doctrine's two
  roles — the client holding the requirements, and one instance of that
  contract. Update them in the same commit as anything that moves the boundary.

## Firecracker constraints (verified in microvm.nix source)

`lib/runners/firecracker.nix` throws on: 9p/virtiofs **shares**, device
passthrough, balloon, hotplug memory, and `user != null`. It has no user-mode
networking (tap only) and microvm.nix has **no jailer support**. Consequences,
which shape nearly every decision here:

- No host directory can ever be mounted into the guest. Anything that must get
  in comes over the tap or is baked into the closure.
- The guest store is a generated read-only image; `nix` in the guest would need
  `writableStoreOverlay` plus its own volume (see NOTES).
- Guest roots are tmpfs, i.e. guest RAM — hence `/work` on a volume for the
  checkout, `target/`, `TMPDIR` and caches.

## Gotchas that have already cost time

- **A tap cannot be swapped under a running VM.** Deleting it leaves firecracker
  holding a dead fd; recreating attaches to nothing and the guest goes silent
  with `No route to host`. `capsule-net down` now refuses while a VM runs.
- **A guest poweroff does not exit the VMM; a guest reboot does.** `poweroff`
  halts the vCPU — the guest even says so, `Power off not available: System
  halted instead` — and the VMM keeps running and keeps the tap open, so the
  next `vm capsule` dies with `Device or resource busy` (EBUSY on TUNSETIFF — a
  single-queue tap can only be attached once). A `reboot` unmounts and then
  resets, and `reboot=k` makes that reset a VMM exit, because CPU reset is the
  one thing firecracker's i8042 stub implements. It logs that as `Unexpected
  exit reason on vcpu run: Shutdown`, then `Killing vCPU threads`, then
  `Firecracker exiting successfully. exit_code=0` — the first two read like a
  crash and are the success path. So **ask for a
  reboot, not a poweroff** — that is `capsule-halt`, used by `vm-stop` and by
  the unit's `ExecStop`, and it is why a stop needs a key into the guest at all.
  microvm.nix's own `microvm-shutdown` is `SendCtrlAltDel`, which is inert here:
  the guest's i8042 driver refuses firecracker's stub outright (`probe with
  driver i8042 failed with error -22`), so there is no keyboard to press it on.
  It is still worth running *after* the request — its `socat` on the API socket
  blocks until firecracker exits, which is exactly the wait a stop needs. The
  `socat ... W address is opened in read-write mode` warning it prints is
  cosmetic.
- **The serial console's TUI input quirk is fixed, and nobody knows why.**
  Claude Code used to render fine there but ignore Enter (the same binary over
  ssh worked); `boot.kernelModules = ["i8042" "atkbd"]` in the guest fixes it,
  A/B'd both ways with nothing else changed. Neither driver binds anything —
  i8042 fails to probe, so atkbd has no port, and no input device appears — so
  that is an observation, not an explanation. Don't build on the mechanism, and
  don't drop those modules casually. ssh is still the documented way to run
  agents.
- **A dead guest does not mean a dead VM.** Check `pgrep -af 'microvm@'`, not
  whether the console returned or the guest answers ping.
- **A `set -u` script must never *be* a login shell, and the symptom is a wrong
  exit status.** NixOS's `/etc/bash_logout` opens by reading an unset guard
  variable, so `bash -l script` where the script sets `-u` dies on the way out
  and **the shell reports 1 whatever the script returned** — a program whose job
  is to relay a build's exit status then reports a red build that was green. Run
  it as a child instead: `bash -l -c "bash script args"` keeps the login shell's
  environment, which is the load-bearing part (NOTES item 6), and lets `set -u`
  die with the child. `NOSYSBASHLOGOUT=1` does not help: under `-u` the guard
  read errors before the `||` beside it. Cost a session, and hid two green
  baselines (NOTES item 24).
- **The guest's clock is UTC; this host is AEST.** So a guest `ls` shows a file
  written five minutes ago as ten hours old, and `find -newermt` compares
  against a guest-local time that may be in the guest's future. Ask the guest
  for `date -u` before reading any mtime in it against a host clock — this is
  what made a run taken minutes earlier look like the previous evening's.
- **On the module path, a missing `microvm -c` fails as a dependency, not as
  itself.** microvm.nix's templates are gated on
  `ConditionPathExists=/var/lib/microvms/%i/current/bin/tap-up`, so with no
  create the tap unit is *skipped* — logged as `finished successfully` — and the
  proxy's `BindsTo` on a unit that never went active fails. The only message is
  `A dependency job for microvm@capsule.service failed`, naming neither. Read
  `ls /var/lib/microvms/<name>/current/bin` before anything else. Same trap when
  the state dir is stale rather than absent: the VM tracks that directory, not
  the flake, so a guest change needs `sudo microvm -u <name>`.
- **A newline in a unit directive silently deletes the rest of the drop-in.**
  systemd reads it as unbalanced quoting, ignores that directive, and does not
  reliably resume — so a multi-line `ExecStartPre=${pkgs.bash}/bin/bash -c '…'`
  took `NetworkNamespacePath`, `ExecStop` and `Restart=no` with it, and every
  capsule started as microvm.nix's bare template: root namespace, no tap, EPERM,
  restarting every 5 s. Nix will happily generate it and only a load says
  otherwise. **Everything else looked fine** — both proxies and relays active,
  both sockets present, `capsule-perimeter-guard: 2 capsule namespace(s)
  verified` — because none of them can see inside a VMM's unit; the one witness
  is `journalctl -u microvm@<name>`, and `systemctl show microvm@<name> -P
  NetworkNamespacePath -P Restart` is the confirmation. Repeated `changed on
  disk … run daemon-reload` warnings and a stuck `NeedDaemonReload=yes` are what
  a drop-in that never parses looks like from outside; reloading is not the fix.
  Put the script in the store and name it (`host/services.nix`'s
  `stopKeyCheck`), and `just build` now refuses a newline in any of the module's
  `serviceConfig` values.
- **A module's *programs* are not in its unit graph, so `just build` could pass
  with the module unbuildable.** `hostModuleUnits` evaluates the whole module,
  which is what makes it worth seconds instead of a rebuild — but it only ever
  *forced* assertions, unit names and `serviceConfig` strings. Everything the
  module puts on a human's PATH lives in `environment.systemPackages`, which
  nothing read, and nix is lazy: `host/cli.nix` is imported at two call sites
  (`flake.nix`'s and the module's), so an argument added to one of them made a
  host rebuild die on `function 'anonymous lambda' called without required
  argument 'observe'` after both `just build` and `just units` were green. Now
  forced, with names in the output and paths never — `builtins.seq` on an outPath
  evaluates the derivation, while embedding the string *of* one would make every
  program a build input of a text file and turn the eval into a build. The general
  shape: **anything built at two call sites needs one construction, not two
  careful ones.** `observe` moved into `host/programs.nix` beside the paths it
  reads for that reason, which is the same reason `baselineRecord` is exported
  there.
- **A hardened unit that may not read `/proc` gets a short answer, not an
  error.** `ip netns pids <ns>` works by reading `/proc/<pid>/ns/net` for every
  process, which `ptrace_may_access` gates on **`CAP_SYS_PTRACE`** for anything
  owned by another user — `CAP_DAC_READ_SEARCH` does not cover that check. With
  the caps trimmed it returns the readable processes and silently omits the rest,
  so the guard concluded a correctly-bound VMM was `not in cap-a` and refused the
  fleet's egress, naming a cause that was not the cause. The A/B that proves it,
  and the shape for the next one:
  `sudo systemd-run --pipe -q -p CapabilityBoundingSet="…" <cmd>` beside plain
  `sudo <cmd>` — the same command under the unit's own capability set. **The
  stubbed cases cannot catch this class**: `guardCases` proves logic, and
  privilege is only provable on a host, so `hostModuleUnits` now asserts the
  pairing instead (a program that reads `/proc` and a unit that may).
- **Inside the repo, the devshell's programs shadow the module's, and they carry
  different transports.** `capsule-provision` on `PATH` in the devshell ssh's
  straight to `net.guest`, which is unroutable from the root namespace once the
  tap is in a namespace; the module's copy of the same program goes through the
  relay socket. Same name, same source, different `transport`. **The devshell's
  copies refuse rather than time out**: a relay socket for the named capsule
  means the module path owns this host, so they name the copy to run instead of
  ssh'ing at an address that is no longer routable from here. It used to be a
  timeout against `10.99.0.2`, which reads as a dead guest. Refusing, not
  choosing — a program that can try both transports has both baked in (NOTES
  item 20). `just provision | inject | baseline | collect | setup <name>` picks
  the reachable copy, which is a recipe's latitude and not a program's.
- **`microvm -c … -f <flake>` takes no fragment, and omitting `-f` is worse than
  forgetting it.** The CLI appends
  `#nixosConfigurations.<name>.config.microvm.declaredRunner` itself, so
  `-f …#capsule` asks for that attribute *of* `packages.capsule` and the error
  reads as a missing output. With no `-f` at all it defaults to the flake at
  `/etc/nixos` — not a git repo on this host — and fails as
  `fatal: '/etc/nixos' does not appear to be a git repository`, naming neither
  the missing flag nor the fact that it substituted a path you never typed. Use
  `just up <name>`, which passes `{{justfile_directory()}}`. It also needs root,
  for `/var/lib/microvms` and the gcroots.
- **`capsule-host` children orphan easily.** A Ctrl-C could leave tinyproxy
  holding the port. It preflights the port, reaps a stray matching its own
  config path, and uses `wait -n` with an INT/TERM trap; if a bind fails anyway,
  look for strays with `ss -lntp`.
- **`wait -n` must name its pids.** Bare `wait -n` waits for the next job to
  change state, and a child that exited *before* the call has already been
  reaped and forgotten — so `capsule-host` sat blocked on its watch loop, with
  its services dead at bind time, looking healthy and serving nothing.
  `wait -n "${children[@]}"`: with explicit pids bash keeps each status until
  waited on.
- **The two paths cannot see each other by probing.** `capsule-host`'s port
  check is a connect from the host, and `capsule-proxy` denies RFC1918, so
  systemd drops the probe and the port reads as free. Hence the explicit
  `systemctl is-active` refusal in the injected `preflight` — systemd-shaped, so
  it lives at the call site in `flake.nix`, not in `perimeter/`.
- **A fresh capsule has fresh ssh host keys at the same address**, because they
  live on its volume — so `known_hosts` refuses, and since the git channel rides
  ssh that blocks provisioning rather than merely annoying `just ssh`.
  `accept-new` does not fix it: the host is *changed*, not unknown. `guestSsh`
  in `flake.nix` disables the check and keeps no record, injected via
  `sshCommand`. Sound only because the link is a host-created /30 with one peer
  — change it in the same commit as any change to the transport, and don't "fix"
  it with a capsule-scoped `known_hosts`, which just accumulates one stale key
  per capsule.
- **`sudo` strips `SSH_AUTH_SOCK`, and the guest's key is `~/.ssh/id`** — not a
  filename ssh tries by default, so a root-side program gets the *wrong* key
  offered and a clean `Permission denied`, while ping keeps passing. Cost one
  `probe-netns-boot` run. Anything host-side that ssh's to the guest runs as the
  human for this reason; `probe/netns-boot.sh` finds the agent socket itself and
  refuses before it boots anything if there is none.
- **Extracting a guest-authored git tree: `..` is not the escape test, and
  `tar -x` is not the extractor.** A tree that comes out of a capsule is
  attacker-shaped input. Three classes, and where each is already handled is not
  where you would guess (NOTES item 34): a `..` or `.git` **path component** is
  refused twice already — `transfer.fsckObjects=true` at `capsule-collect` errors
  `hasDotdot`/`hasDotgit`, and `git read-tree` refuses `invalid path` — while a
  **symlink target** and a **gitlink** sail through both. `git archive | tar -x`
  then plants `-> /etc/passwd` in your worktree and turns the gitlink into an
  empty directory, exit 0, silent; nothing escapes until the next thing that
  greps or copies the exhibit. And refusing every `..` target refuses doctrine's
  own tree, whose `.doctrine/slice/N/phases -> ../../state/slice/N/phases` is
  inside the root and load-bearing. The rule is **lexical resolution within the
  extraction root**, against the tree and never with `realpath` — plus git's own
  writer (`read-tree` into a temporary index, `checkout-index` out of it) rather
  than a second one made of shell.
- **A `just` recipe's trailing command is *evaluated on this host*, not carried
  as argv.** just interpolates a recipe's arguments as text, so the recipe's own
  shell parses them before anything is sent: `just ssh b 'echo $(hostname)'`
  answered `Sleipnir`. It is not word-splitting — that was the documented and
  survivable half — it is a diagnostic that reads as the capsule's and is the
  host's, which is the one failure a door exists to prevent, and it is silent
  because both ends have a `hostname`. `capsule <name> ssh` never had it, because
  a program takes argv. `just ssh`/`just admin` now `quote(cmd)` and pass one
  word, with the empty case kept distinguishable since no command means an
  interactive shell. **Any new recipe that forwards `*args` into a program has
  this until it quotes**, and the general rule is that `{{...}}` is text
  substitution and never an argument.
- **`CAPSULE_STATE` moves the quarantine and not the record.** The assignment
  record's root is the literal `/var/lib/capsule`, deliberately — a slot is a
  module-path thing, so a record for a devshell capsule would describe a slot
  that does not exist (`host/cli.nix`, `recordRoot`) — while `quarantineOf`
  *searches* both homes because either shape can collect. So a devshell
  `capsule <name> unit|purpose|provision` writes the **live** record whatever
  `CAPSULE_STATE` says, and there is no throwaway root to try one against: the
  generation only goes up, so an experiment is a hand-edit to undo.
- **`nix run`/devshell binaries are store paths, so an edited program is stale
  until it is rebuilt.** A probe that "ignores your fix" is the old build on
  `PATH` — `just build`, re-enter the devshell, or
  `sudo "$(nix build --no-link --print-out-paths .#probe-netns-boot)/bin/…"`.
- **`denyCurrentBranch` only governs the branch HEAD names.** Push any other
  branch and the ref lands while the worktree is untouched, silently. The seed
  sets `--initial-branch` and `capsule-provision` verifies the advertised symref
  for exactly this reason; don't remove either. An empty repo advertises no
  symref at all, so the check cannot cover the first provision — the seed is
  what does.
- **`git+file:` inputs read committed HEAD.** Changes to the target's flake need
  a commit there before `nix flake update target` sees them. Uncommitted work
  in that repo is invisible to the capsule.
- **`environment.variables` is login-shell scope.** Proxy vars do not reach
  systemd units in the guest; anything daemon-side needs its own
  `serviceConfig.Environment`.
- `initialHashedPassword = ""` does not give a passwordless root: it applies
  only at account creation, and PAM rejects empty passwords for `su`.

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
  a unit needs something, it comes from the same program. `capsule-provision` is
  the only thing that reads the real repo, and it always runs as the human.
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
