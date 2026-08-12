# CLAUDE.md

Firecracker microVM used to confine a coding agent working on one target repo
(`target.nix`; here `~/dev/doctrine`).
[README.md](./README.md) is usage; everything else is [docs/](./docs/index.md),
which maps question to file. Three of them before proposing changes:
[docs/status.md](./docs/status.md) is where the work is up to,
[docs/notes.md](./docs/notes.md) is the numbered ledger of rationale and gaps —
**several obvious-looking ideas are already recorded there as
considered-and-rejected**, and it is cited from source as `NOTES item N`, so those
numbers are frozen — and [docs/probes.md](./docs/probes.md) owns every measured
figure, so link to it rather than copying a number out.

Plans are scoping, not commitments: `plan-b-other-jails.md` is the
non-firecracker shapes, `plan-c-multi-capsule.md` is what N capsules on one host
would cost. Do not put present-tense state in a plan; that is `status.md`'s job.

## Working here

**Do not run nix builds or evals.** The user runs those themselves — they are
slow, and as a subshell they have crashed the session. Verify with
`just check` (`nix-instantiate --parse` over every file, plus `alejandra -c`;
neither evaluates). Hand the user the command to run — `just build` for the
host-side scripts, which is also where shellcheck runs — and say what you
expect it to do. `just` recipes that shell out to `nix eval` (`_net`, `_target`,
and so `status`/`fetch`/`allowed`/`ssh`/`admin`) are the user's to run, not
yours.

Shell in `writeShellApplication` cannot be run either, since it only exists
after a build. Render the script by hand into the scratchpad and `shellcheck`
that — it catches the SC2034/SC2154 class before the user spends a build on it.

**`probe/` is evidence, not scaffolding.** Each probe answers one design
question and is kept so the answer stays checkable — `probe/netns.sh` is what
PLAN_C's addressing and isolation decisions rest on. They need root, so they are
the user's to run (`sudo probe-netns`); `just build` shellchecks them. Write new
ones the same way: assert both directions, since a denial-only network test
passes for the wrong reason, and never borrow live addressing — a probe on the
real `/30` tests the real capsule. `probe/harness.sh` is concatenated ahead of
each probe by the `probe` builder in `flake.nix`, not sourced, so shellcheck sees
one file; values from `net.nix`/`target.nix` reach a probe through that builder's
`prelude` rather than being spelled in the script. **Quote them there** — an
unquoted `TAP=vm-capsule` reads as arithmetic to shellcheck (SC2100) once the
harness has a `vm` variable in scope, and `writeShellApplication` fails the build
on it. The harness carries four verbs, not three: `check` a verdict, `observe` a
finding, `measure` a figure (a round whose bar is a price needs numbers beside
the assertions), and `report`. It also carries the whole capsule-in-a-namespace
boot — `ns_up`, `capsule_boot`, `wait_guest`, `halt_guest` — because
`netns-boot.sh` and `freshness.sh` assert and measure the same shape, and two
copies of a boot sequence are two answers the first time one is edited.

**A VMM is identified by its namespace, never by its name.** The one-image lever
means every capsule runs the same runner from the same store path, so all of them
are `microvm@capsule` in the process table: `pkill -f` on that name is a power cut
for the siblings, and it reads as a clean teardown while doing it. `vm_running`,
`wait_vm` and `halt_guest` all take a namespace and scope themselves with
`ip netns pids`; the unscoped question survives as `any_vm_running`, which is
what a probe's refusal wants and the only thing it is for. The thing that
isolates a capsule is the same thing that names it — no pidfile, no registry.
`probe/netns-boot.sh` is the deliberate exception to the addressing rule and
says why in its header: it boots the real guest, whose image has `net.nix` in
it, so the real capsule *is* the subject.

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
  platform-shaped belongs at
  the call site in `flake.nix` (`perimeterChecks`). `host/git-channel.nix` has
  the same seam for the same reason: it knows a git URL and optionally an ssh
  command, both injected, and nothing about taps or namespaces.
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
- **`target.nix` is the same deal for the repo under confinement** — name, path,
  tools package, allowlist file, caches, default branch, sizes. Threaded the same
  way. `doctrine` may appear in exactly two places: `target.nix`, and
  `inputs.target.url`, which cannot be computed. Nothing target-shaped goes in
  `perimeter/`, `vm/capsule.nix` or the justfile; it comes from there as a value.
  And nothing target-shaped is ever read *out of the target repo* — the agent can
  edit that (NOTES item 16). `target.guestPath` is the one path both sides share,
  which is why it is derived there rather than spelled in the guest and again in
  the host's git channel.
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
- **Firecracker does not exit when the guest powers off.** A guest `poweroff`
  halts the vCPU; the VMM keeps running and keeps the tap open, so the next
  `vm capsule` dies with `Device or resource busy` (EBUSY on TUNSETIFF — a
  single-queue tap can only be attached once). microvm.nix's `microvm-shutdown`
  works around this with `SendCtrlAltDel`, relying on `reboot=k` turning a
  guest reset into a VMM exit — but this guest ignores ctrl-alt-del, so that
  route is dead too. `vm-stop` therefore powers off over ssh (clean unmount),
  waits, then terminates the VMM, which is safe once the guest has halted.
  The `socat ... W address is opened in read-write mode` warning on the
  fallback path is cosmetic, from microvm.nix's own shutdown command.
- **TUIs do not take input on the serial console.** Claude Code renders fine
  there (colours, layout, correct `stty size`) but ignores Enter; the same
  binary over ssh works. Raw mode turns off the CR→NL translation, so the app
  sees a bare `\r` and evidently drops it. `TERM=xterm-256color` on the serial
  getty was tried and did not help — reverted. **Run agents over ssh**; the
  console is for boot and admin.
- **A dead guest does not mean a dead VM.** Check `pgrep -af 'microvm@'`, not
  whether the console returned or the guest answers ping.
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
  `accept-new` does not fix it: the host is *changed*, not unknown. `guestSsh` in
  `flake.nix` disables the check and keeps no record, injected via `sshCommand`.
  Sound only because the link is a host-created /30 with one peer — change it in
  the same commit as any change to the transport, and don't "fix" it with a
  capsule-scoped `known_hosts`, which just accumulates one stale key per capsule.
- **`sudo` strips `SSH_AUTH_SOCK`, and the guest's key is `~/.ssh/id`** — not a
  filename ssh tries by default, so a root-side program gets the *wrong* key
  offered and a clean `Permission denied`, while ping keeps passing. Cost one
  `probe-netns-boot` run. Anything host-side that ssh's to the guest runs as the
  human for this reason; `probe/netns-boot.sh` finds the agent socket itself and
  refuses before it boots anything if there is none.
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
- The guest's tool set comes from the target's flake — `target.nix`'s
  `toolsPackage`, for doctrine `packages.dev-tools`. Add tools
  there, not here, so the VM and that devshell cannot drift. The jailed
  `claude`/`codex` bwrap wrappers are excluded on purpose — they bind host
  paths that do not exist in the VM.
