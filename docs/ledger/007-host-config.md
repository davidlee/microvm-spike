# NOTES item 7 — host config — the accept, the forward drop, and checking the drop

*State: resolved, plus one host edit outstanding ([item 18](./018-git-channel-direction.md)).*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

~~**Host config.**~~ Done; the stanzas are in README "Host requirements", and
the first attempt was wrong in a way worth recording.
`networking.firewall.trustedInterfaces = [ "vm-capsule" ]` opens the
*interface*, not the two ports — `firewall-nftables.nix` renders it as `iifname
{ … } accept`, so every service bound to `0.0.0.0`/`*` on the host became
reachable from inside the jail (here: sshd, caddy on 80 and 8080, dictd, steam's
27036, LLMNR). Loopback-bound services were never exposed: guest packets are
addressed to the tap, not to `127.0.0.1`. The scoped form is what belongs in the
host config — `networking.firewall.interfaces."vm-capsule".allowedTCPPorts = [
3128 ];` — and *not* plain `allowedTCPPorts`, which would also open the proxy on
the LAN and the tailnet. It was `[ 3128 9418 ]` until the git channel inverted
([item 18](./018-git-channel-direction.md)); dropping 9418 is a host-config edit
and a rebuild, not something this repo can do.

The input chain was only half of it. **The tap must also not be a transit
path**: the guest has no default route, but a guest with root can add one,
after which the sole remaining question is whether the host forwards.
`net.ipv4.ip_forward` is global and not ours — docker and tailscale both set
it — so the guarantee cannot rest on it being 0. A standalone nftables table
dropping `iifname`/`oifname "vm-capsule"` in the forward hook is the control.
Deliberately *not*
`networking.firewall.filterForward`, which flips the whole host's forward
policy to drop (`firewall-nftables.nix` renders `policy drop` on the forward
chain) and whose `extraForwardRules` land in an allow-list chain that cannot
express a drop anyway. A separate table needs no cooperation from the
firewall's: a `drop` verdict in any chain is terminal for the packet.

IPv6 on the tap is host stack the guest can reach for no benefit, and is
turned off by `capsule-net` before the link comes up rather than by a
boot-time sysctl, which would fire before the interface exists.

**And it is now checked rather than documented.** A control that lives in
someone else's file and is never read is a control you find out about
afterwards — it was in fact missing from this host's config until the check
was written, with `ip_forward` at 0 the whole time, which is exactly the
failure the check exists to surface.

The two halves fail differently and that is what decides how much machinery
each deserves. Omit the *allow* (interface-scoped ports) and the guest
reaches nothing: loud, self-announcing, no verification needed. Omit the
*drop* and everything works normally until a guest gains root and adds a
route: silent, and worth spending on. So only the drop is verified, and this
repo cannot install it — a `drop` in any chain is terminal, so a table here
could add denials, but nothing here can grant the accept that the host
firewall would still be dropping. Deny-side controls can be self-installed;
allow-side controls can't. Hence: check, don't install.

Verification reads live kernel state (`nft list table inet capsule-forward`),
not a stamp file or the config text, because the failure mode being guarded
is "the config no longer matches the kernel". That read needs CAP_NET_ADMIN,
so it depends on a NOPASSWD sudoers rule for exactly that one command,
naming `/run/current-system/sw/bin/nft` — a store path can't work, since the
two flakes have separate nixpkgs pins and sudo matches the command string
literally. No rule means no verdict, which resolves to `latent`: safe only
while nothing forwards, and reported as such rather than passed.

**All of the above is the tap shape, and the module path has now left it.**
Under netns the tap is inside a namespace this repo's units create, so the
control is that namespace's own `ip_forward` — nobody else writes it, there
is no race with docker, no sudoers rule, and no `latent` state: unverifiable
is a refusal, because an answer these units cannot read is their own fault
and not someone else's config. What the host still owns is forwarding and
NAT for the *proxies'* egress, which the module installs itself and on which
nothing about a guest's confinement rests. This paragraph's machinery stays
exactly as it is for the devshell path, which still has a tap in the root
namespace and still needs every word of it (`host/netns.nix`,
`host/perimeter-check.nix`).

Three states, one definition shared by `capsule-net` and `capsule-host`
(`perimeterChecks` in `flake.nix` — Linux-shaped, hence at the call site and
not in `perimeter/`): `dropped` verified, `latent` unverifiable but nothing
forwards, `open` forwarding live and unverifiable → refuse. Preflight alone
would only prove the perimeter held at start, so `capsule-host` also
supervises a `watch` child that re-checks, and exits — tearing the proxy
down with it — if forwarding comes up mid-session or the tap's
address vanishes. Losing egress is the correct outcome; continuing to serve
it past a missing control is not. `watch` is an injected fragment for the
same reason `preflight` is: `perimeter/` must not learn what nftables is.
