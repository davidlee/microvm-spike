# NOTES item 17 — more than one capsule at a time

*State: scoped — [Plan C](../plan-c-multi-capsule.md).*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**More than one capsule at a time — scoped, not started.**
[Plan C](../plan-c-multi-capsule.md) is the list of what a plan has to settle,
with the costs attached. The three things worth knowing without reading it:

- **The deciding cost is the guest image, not the plumbing.** Tap, MAC and
  /30 reach the guest through its config today, and its store image is
  generated per config, so the obvious design pays N image blobs — N × disk,
  and N × *pack* time on every `dev-tools` bump. Not N × build: the closure
  is almost entirely shared. Getting the per-instance values out of the
  closure buys one image and N small runners, and there are two of them, not
  one: the guest's address, and the **base commit**, which a capsule is
  usually pinned to and which `capsule-clone` baked in the same way it baked
  the remote. A kernel param does *not* work for either — it lands in
  `toplevel` and so in the closure. See the netns option below, which makes
  the guest bit-identical without any of it.

  **Both halves are now closed, and the image is measured.** The base commit
  went as a side effect of [item 18](./018-git-channel-direction.md): the guest
  boots with an empty repository and `capsule-provision <ref>` is what puts
  history in it, so the ref is an argument to a host command and never reaches
  the closure. The address goes with netns. And the measurement that was
  supposed to decide this is in — [probes.md](../probes.md) has the closure, the
  per-instance blob and what each was taken with. It prices the N-blob design
  rather than forbidding it, which is why the recommendation rests on netns
  being verified and not on the disk number.
- **No daemon, and the premise that suggests one is wrong.** Nix runs nothing at
  run time here: `vm` is build-then-exec. Everything a dispatcher would do is
  systemd's, and microvm.nix's host module already models it — which is why the
  VMM half of [item 11](./011-host-side-runs-as-you.md) should be done *with*
  this work rather than before or after it. Per-instance ceilings stop being
  optional at N anyway ([item 12](./012-no-resource-ceiling.md)).
- **A capsule can reach another capsule's tap, and the forward drop is not
  what stops it.** B's tap address is a *host* address, so a packet from A
  to it is INPUT, not forward, and Linux accepts an address on any interface
  from any interface. The drop never sees it. Precondition is guest root —
  the same precondition the drop itself exists for — and what actually holds
  the line today is the units' `IPAddressAllow`/`Deny`, which the foreground
  path has no equivalent of. So the tempting host-config simplification (one
  wildcard `iifname "vm-cap*"` accept, written once and never touched again)
  is exactly wrong: it *grants* the reach. The accept has to pair iifname
  with destination address. The drop can still be a wildcard.
- **A netns per capsule dissolves most of the above, and has been probed:
  it holds.** Identical /30 and MAC in every capsule (so one image, with no
  DHCP and no boot-time step), no path from A to B, and — because
  `net.ipv4.ip_forward` is per-netns — a forward control that is *ours*
  rather than one shared with docker and tailscale. `probe/netns.sh` models
  two capsules and a guest that already has root: it cannot reach the
  upstream, cannot reach the other capsule, and cannot be reached from
  outside even by something holding a route to it, while a process in the
  namespace reaches the internet normally. Flipping the namespace's
  `ip_forward` to 1 lets the guest straight out, which is what proves the
  switch is the thing doing the work.

  The plumbing went with it. A tap can be created directly inside a capsule
  namespace, or created in the root namespace and moved in — and after a move it
  is *gone* from root, so nothing there can delete it out from under the guest.
  Either way a process inside can bind an address on it. Creating it inside is
  the plan, because `tap-up`/`tap-down` are namespace-agnostic and putting the
  namespace on that unit makes stop symmetric with start
  ([item 11](./011-host-side-runs-as-you.md)); the move is the fallback. And ssh
  gets in over a unix socket (`/run/capsule/<name>/ssh.sock`, an `ssh`
  `ProxyCommand`), since the filesystem is not namespaced — no privilege, no
  port allocation, no socket-activation fd passing, and identical guest
  addresses never reach `known_hosts` because the socket path is the identity.

  The host module takes the namespace without a patch — verified against the
  pinned source, see [item 11](./011-host-side-runs-as-you.md). **And the boot
  is no longer a question either**: `probe/netns-boot.sh` (`sudo
  probe-netns-boot`) puts the real capsule in a namespace with its tap created
  inside it and the runner started in there as you — 9 assertions green. The VMM
  comes up, the guest boots and answers ssh in the namespace, its NIC carries
  traffic on the namespaced tap, and the tap, the guest and its ssh port are all
  unreachable from the root namespace. ssh and git both cross a unix socket into
  it unprivileged. No host config was needed to establish any of that, which is
  the other result: the boot was never systemd's question.

  Netns applies to the **host-module path only**. The devshell path keeps
  working with no rebuild and no root, which a namespace cannot do, so the
  foreground path stays the current tap shape at N=1 — the same split
  `capsule-host` and `host/services.nix` already have.

  Three costs it found: a guest can reach its own capsule's *egress*
  address (weak host model again, one scope down — bind explicitly, drop on
  the veth); whatever aggregates the capsules' egress forwards, so
  proxy-to-proxy needs an interface-pair drop; and DNS needs
  `DNSStubListenerExtra=` plus `/etc/netns/<ns>/resolv.conf`, since loopback
  is per-namespace and `127.0.0.53` is not in it.

  **All three now have their fix verified, and so does the thing none of
  those probes had in it: the perimeter.** `probe/netns-egress.sh`
  (`sudo probe-netns-egress`) joins the real `capsule-proxy` to the real
  capsule's namespace and asks the real guest to get out — 27 assertions,
  green on the first run, [probes.md](../probes.md). The allowlist answers
  200 for a host on it and 403 for one off it; guest root holding the route
  it can always add reaches neither the internet nor the aggregator; each
  denial is paired with the control that removes the thing supposedly doing
  the work and watches it fall over. Egress under netns was the last
  unverified claim in this shape and is no longer one.

  Two findings from it that change what the next step is, rather than
  confirming what was expected:

  - **The unit inventory in Plan C undercounted.** "One oneshot unit and two
    drop-ins" is the *namespace*; a working perimeter also needs a veth per
    capsule to an aggregating namespace, that namespace's forwarding and its
    two drops, and NAT plus forwarding on the host. All host-side, none of
    it in the guest — but it is the difference between one unit and a
    module.
  - **The DNS fix is a `~/flakes` edit this host does not have**, and the
    probe fell back to a public resolver rather than pretending otherwise.
    That fallback silently loses the DoT hop, which is precisely the
    property [item 7](./007-host-config.md)'s chain exists for. So the netns path's DNS claim is
    *unproven*, not merely unwired, until the stub address and its port-53
    input allow land. Do it in the same change as the units, not after.

  The consequence worth reading this item for: it largely retires the "part of
  the perimeter is not in this repo" problem in [item 7](./007-host-config.md).
  The control becomes a sysctl inside a namespace this repo creates, the host's
  input chain leaves the guest path, and the runtime nftables verification plus
  its sudoers rule go with them. The host still has to forward and masquerade —
  but for the *proxy's* egress, with nothing about the guest's confinement
  resting on it. Cost is that namespace creation is root-side, so the host
  module stops being optional.

Mixed targets stays deferred, with the instance record carrying its own target
so it remains a relaxation rather than a rewrite
([item 16](./016-target-agnostic.md)).
