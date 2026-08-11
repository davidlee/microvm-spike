# CLAUDE.md

Firecracker microVM used to confine a coding agent working on one target repo
(`target.nix`; here `~/dev/doctrine`).
[README.md](./README.md) is usage; [NOTES.md](./NOTES.md) is rationale, gaps and
things deliberately not built. Read NOTES before proposing changes — several
obvious-looking ideas are already recorded there as considered-and-rejected.

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

Formatting is alejandra, 2-space indent, matching doctrine's flake.

## Architecture invariants

Break these and the confinement stops meaning anything:

- **The perimeter is host-side.** Egress filtering (tinyproxy allowlist) and the
  git ref restriction (`update` hook, `refs/heads/capsule/*` only) both run on
  the host, where the guest cannot reach them. Guest-side settings — proxy env
  vars, the unprivileged `agent` user — are convenience and clumsiness-guards,
  not security. Never move a control from the host into the guest.
- **`perimeter/` knows nothing about the jail.** It builds `capsule-host` from
  addresses, ports, and two injected shell fragments — `preflight` (once,
  before anything binds) and `watch` (supervised child; exits nonzero when the
  perimeter is gone, which tears the services down). No tap name, no
  hypervisor, no Linux-only tool goes in there — that is what lets a
  seatbelt or VM-based shape reuse it (PLAN_B.md). Anything platform-shaped
  belongs at the call site in `flake.nix` (`perimeterChecks`).
- **Part of the perimeter is not in this repo.** The firewall ports, the
  forward-chain drop on the tap, and the sudoers rule that makes the drop
  readable all live in the host's NixOS config (`~/flakes`) — README "Host
  requirements". Anything proposed here that assumes the host is unconfigured,
  or that tries to compensate for it guest-side, is wrong twice. The drop is
  *verified at run time*, not assumed: unverifiable-and-forwarding is a refusal
  to start, and forwarding coming up mid-session kills egress. Don't soften
  that to a warning — a warning is what it had while the drop was in fact
  missing from the host config.
- **No default route in the guest.** The only egress is the proxy. Adding NAT
  or a gateway would silently void the allowlist — and so would leaving the
  host forwarding for the tap, since guest root can add the route itself.
  Guest kernel hardening (`lockKernelModules`) raises the cost of getting that
  root; it is not what makes the claim true.
- **Root is reachable only by ssh key from the host.** The agent has no sudo and
  no su, by design.
- **`net` in `flake.nix` is the single source of truth** for tap name, both
  addresses, MAC and ports. It is threaded to the guest via `specialArgs`.
  Don't hardcode an address anywhere else.
- **`target.nix` is the same deal for the repo under confinement** — name, path,
  tools package, allowlist file, caches, default branch, sizes. Threaded the same
  way. `doctrine` may appear in exactly two places: `target.nix`, and
  `inputs.target.url`, which cannot be computed. Nothing target-shaped goes in
  `perimeter/`, `vm/capsule.nix` or the justfile; it comes from there as a value.
  And nothing target-shaped is ever read *out of the target repo* — the agent can
  edit that (NOTES item 16).

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
- **`capsule-host` children orphan easily.** If either service dies at bind
  time the other can keep its port. It now preflights both ports and uses
  `wait -n` with an INT/TERM trap; if a bind fails anyway, look for strays with
  `ss -lntp`.
- **`wait -n` must name its pids.** Bare `wait -n` waits for the next job to
  change state, and a child that exited *before* the call has already been
  reaped and forgotten — so `capsule-host` sat blocked on its watch loop, with
  both services dead at bind time, looking healthy and serving nothing.
  `wait -n "''${children[@]}"`: with explicit pids bash keeps each status until
  waited on.
- **The two paths cannot see each other by probing.** `capsule-host`'s port
  check is a connect from the host, and both units deny that address
  (`capsule-gitd` allows only the guest; `capsule-proxy` denies RFC1918), so
  systemd drops the probe and every port reads as free. Hence the explicit
  `systemctl is-active` refusal in the injected `preflight` — systemd-shaped, so
  it lives at the call site in `flake.nix`, not in `perimeter/`.
- **`git+file:` inputs read committed HEAD.** Changes to the target's flake need
  a commit there before `nix flake update target` sees them. Uncommitted work
  in that repo is invisible to the capsule.
- **Never `git remote update` the mirror** — a mirror's fetch is force+prune and
  deletes what the guest pushed. Explicit refspecs only.
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
- **Two paths run the same code.** `capsule-host` composes `sync`/`proxy`/`gitd`
  in the foreground as you; `host/services.nix` runs the same three as units
  under `capsule-proxy`/`capsule-git`. Don't grow a second implementation for
  either — if a unit needs something, it comes from the same program.
  `capsule-sync` is the only thing that may read the real repo, and it always
  runs as the human: that is what keeps the serving uid away from the tree.
- The guest's tool set comes from the target's flake — `target.nix`'s
  `toolsPackage`, for doctrine `packages.dev-tools`. Add tools
  there, not here, so the VM and that devshell cannot drift. The jailed
  `claude`/`codex` bwrap wrappers are excluded on purpose — they bind host
  paths that do not exist in the VM.
