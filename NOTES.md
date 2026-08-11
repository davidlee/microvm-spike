# microvm.nix spike — notes

A **capsule**: a firecracker microVM used as an agent jail. It holds a real
git clone of `~/dev/doctrine`, can run `just web-build` / `just test`, and has
exactly enough network for a coding agent to work — no more.

## Layout

| path                   | what                                               |
| ---------------------- | -------------------------------------------------- |
| `flake.nix`            | VMs, devshell, host-side scripts, the link's config |
| `vm/common.nix`        | shared guest config (firecracker, serial console)   |
| `vm/hello.nix`         | smoke test VM, no network                           |
| `vm/capsule.nix`       | the agent jail                                      |
| `net/egress-allow.txt` | proxy hostname allowlist — plain file, no rebuild   |
| `.vm/<name>/`          | per-VM state: volume images, API socket (gitignored)|
| `.vm/host/`            | the bare mirror, proxy config + logs (gitignored)   |

## Running

```
direnv allow
capsule-net up      # one sudo: creates the tap, owned by you
capsule-host        # foreground: git daemon + egress proxy
vm capsule          # another terminal
```

`vm hello` first if you want to prove firecracker boots before debugging
anything else. `capsule-net down` removes the tap.

## The confinement shape

**Link.** One point-to-point tap, `10.99.0.1/30` (host) ↔ `10.99.0.2/30`
(guest). No bridge, no LAN exposure, **no NAT and no default route in the
guest**. The guest cannot originate traffic anywhere except the host end of
the /30.

**Egress.** tinyproxy on the host, `FilterDefaultDeny Yes` over
`net/egress-allow.txt` (hostnames, extended regex). The guest gets
`HTTPS_PROXY` and no resolver at all — DNS happens in the proxy, so a name
that is not on the list cannot even be resolved, let alone reached. IP-level
allowlisting was rejected: `api.anthropic.com` is CDN-fronted with rotating
addresses.

**Git.** `git clone --mirror ~/dev/doctrine` into `.vm/host/`, served by
`git daemon` on the p2p address with `receive-pack` enabled. The guest clones
real history with real ancestry and pushes back.

- Bare is a hard requirement: a non-bare clone refuses pushes to its checked-out
  branch (`receive.denyCurrentBranch`).
- `--mirror` over plain `--bare` buys `fetch = +refs/*:refs/*`, so the mirror
  tracks every ref namespace rather than just `refs/heads/*` + tags. Your
  `phase/`, `dispatch/`, `review/`, `candidate/`, `w/` namespaces all live
  under `refs/heads/` (274 refs), so plain `--bare` would have carried them
  too — the mirror's edge is fidelity on anything future that doesn't.
- **Never `git remote update` the mirror.** A mirror's fetch is force+prune and
  would delete what the guest pushed. `capsule-host` refreshes with an explicit
  `+refs/heads/*:refs/heads/*` instead.
- An `update` hook restricts guest pushes to `refs/heads/capsule/*`. The agent
  cannot rewrite your history through the mirror — it gets a namespace, and you
  fetch from it:
  ```
  git fetch .vm/host/doctrine.git 'refs/heads/capsule/*:refs/heads/capsule/*'
  ```
  Which lines up with SPEC-012's merge-safety-by-absence: the agent has no path
  to the coordination tier, physically.

Guest helpers: `capsule-clone` (re-fetch, for when the host side came up late)
and `capsule-push <name>`.

**State.** One 32 GiB sparse volume at `/work`: the checkout, `target/`,
`TMPDIR`, cargo + bun caches. Survives reboots. Deliberately not on the
rootfs — microvm.nix roots are tmpfs, i.e. guest RAM.

## Why firecracker forces this

`lib/runners/firecracker.nix:86` in microvm.nix:

```
else if shares != []
then throw "9p/virtiofs shares not implemented for Firecracker"
```

Same for device passthrough, balloon, hotplug memory. Firecracker also has no
user-mode networking — tap only, which is why `capsule-net` needs one sudo.
(qemu and kvmtool do have user-net *and* virtiofs, which would remove the host
setup entirely at the cost of the isolation story and of any real egress
control.) Consequences: guest `/nix/store` is a generated disk image, nothing
host-side can be mounted in, and the only channels into the VM are the tap and
the volume.

microvm.nix has **no jailer support** — firecracker runs unwrapped, so the
isolation floor is KVM plus whatever the host user can do, not the jailer's
chroot/seccomp/cgroup setup.

## Open items

1. **Nothing here has been run yet** — no eval, no build. Expect first-boot
   friction.
2. **Agent credentials.** No shares, so nothing can be injected from the host
   filesystem. First boot: put `export ANTHROPIC_API_KEY=...` in `/work/.env`
   (sourced at login, persists on the volume). OAuth login would need
   `claude.ai` + `console.anthropic.com`, both allowlisted, but the device flow
   wants a browser.
3. **`pkgs.claude-code`** is included only via `lib.optional (pkgs ? claude-code)`
   — unverified on this channel. Your `llm-agents.nix` / `pub` flake is the
   fallback source, and would want adding as an input.
4. **`just test` may want a live Postgres.** doctrine's flake sets
   `doCheck = false; # tests need a live Postgres`, though no `DATABASE_URL`
   appears anywhere in the tree. Not provisioned; `services.postgresql.enable`
   in `vm/capsule.nix` if it bites.
5. **No `doctrine` binary in the guest**, so `just validate` / `just check`
   won't run — only `test` and `web-build`.
6. **Proxy env is login-shell scope** (`environment.variables` → `/etc/set-environment`).
   Anything run from a systemd unit in the guest won't inherit it.
7. **Host firewall.** If the guest can't reach `10.99.0.1`, the host is
   dropping input on the tap. Durable fix:
   `networking.firewall.trustedInterfaces = [ "vm-capsule" ];`
8. **git-daemon is unauthenticated.** Fine on a /30 point-to-point link, but
   it is reachable from the host itself too, and `--enable=receive-pack` is
   what makes the update hook load-bearing.
9. **Egress allowlist is unproven** against a real Claude Code session —
   expect to add hosts on first run. `net/egress-allow.txt`, restart
   `capsule-host`, no rebuild.
10. **Dropped since the first cut:** vendored crates
    (`rustPlatform.importCargoLock`) and the pre-seeded `node_modules` from
    doctrine's `web-modules` FOD. Both existed to make an offline capsule
    build; the proxy supersedes them, and dropping them removed this flake's
    dependency on doctrine's flake (and its `pub` / `llm-agents` transitives).
    Worth restoring if you want cold-start builds without network.
