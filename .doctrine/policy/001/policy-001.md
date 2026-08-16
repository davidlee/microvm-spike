# POL-001: The perimeter is host-side

## Statement

**Every control that makes the confinement mean anything runs on the host, where
the guest cannot reach it. Never move a control from the host into the guest.**

Four limbs:

1. **Egress filtering is host-side.** The tinyproxy allowlist runs on the host.
   Guest-side settings — proxy env vars, the unprivileged `agent` user,
   `receive.denyCurrentBranch` — are **convenience and clumsiness-guards, not
   security**.
2. **No default route in the guest.** The only egress is the proxy. Adding NAT or
   a gateway would silently void the allowlist — **and so would leaving the host
   forwarding for the tap**, since guest root can add the route itself. Guest
   kernel hardening (`lockKernelModules`) raises the cost of getting that root;
   it is **not** what makes the claim true.
3. **Root in the guest is reachable only by ssh key from the host.** The agent
   has no sudo and no su, by design.
4. **Git is not a control at all any more.** The host initiates both directions
   and the guest has no remote, so what used to be a ref restriction enforced by
   a hook is now **the absence of a channel** (`NOTES item 18`).

**Part of the perimeter is not in this repo**, and anything proposed here that
assumes the host is unconfigured — or that tries to compensate for it guest-side
— is wrong twice.

## Rationale

A control the confined party can reach is not a control. The guest runs an agent
that can edit anything it can see, so every guest-side setting is a statement
about convenience and never about authority.

**The drop is verified at run time, not assumed.** Unverifiable-and-forwarding is
a **refusal to start**, and forwarding coming up mid-session **kills egress**.
Do not soften that to a warning — *a warning is what it had while the drop was in
fact missing from the host config.*

## Scope

**Applies to** both shapes, which are one at a time:

- **The devshell path.** The firewall port, the forward-chain drop on the tap,
  and the sudoers rule that makes the drop readable live in the host's NixOS
  config (`~/flakes`), not here — README *Host requirements*. It is one port now,
  not two: dropping 9418 there is an outstanding host-config edit
  (`NOTES item 18`).
- **The module path.** The tap is inside a namespace `host/netns.nix` creates, so
  the control is that namespace's own `ip_forward`; the sudoers rule and the
  `latent` state are gone, and the host config's remaining job — forwarding, NAT,
  the resolver stub — the module installs itself.

`capsule-host` refuses while a `capsule-proxy-*` unit is active, which is what
keeps them one at a time.

## Verification

- **Run time**: `capsule-perimeter-guard` reads each namespace's `ip_forward` and
  refuses the fleet's egress rather than proceeding unverified.
- **Build time**: `guardCases` proves the guard's logic against a stubbed kernel.
  `hostModuleUnits` asserts two pairings the sandbox cannot reach — a program
  that reads `/proc` against a unit that may, and the module's tmpfiles rules
  against each unit's `User`.
- **Live**: `probe/netns-egress.sh` asserts **both directions**, because a
  denial-only network test passes for the wrong reason.

Two gaps this policy does not close, both recorded: **only the guard can read the
inside of a namespace** (`CON-005`), so if the guard is wrong it is wrong alone;
and **`microvm -c capsule` would create an instance with no perimeter at all**
(`RSK-005`), because `microvm` is upstream of the front end that refuses the
name.

## References

- `NOTES item 18` — the git channel's direction, and the daemon deleted rather
  than confined.
- `NOTES item 39` — a control switched, proven, asserted, and never started.
- `docs/threat-model.md` — what the confinement claims.
- `mem.fact.oubliette.a-bind-is-not-an-access`,
  `mem.fact.oubliette.proc-read-needs-cap-sys-ptrace` — two ways a host-side
  control fails silently.
