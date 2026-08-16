# Plan E — a room: a shared guest that is not a capsule

Not a plan yet: what a plan has to settle, and what the answers cost. Written
after the fleet shape landed (items 30, 36), which is the prerequisite — the host
module already runs N namespaced guests, so the question here is not *can it* but
*what does a guest that is not a capsule cost the design*.

Scope: *one microVM on this host, several humans logged into it over ssh from a
tailnet, no egress, disposable.* The worked example is a DIY chat room — friends
ssh in and talk to each other through whatever they improvise, a shared tmux
socket or a file and `tail -f`. The mechanism is mostly userland and mostly out
of scope, with **one exception that is a boundary fact and not a detail**: how
the room is furnished decides whether the identity ssh established survives past
the door. That is [below](#5-identity-ends-at-the-door-unless-the-furniture-keeps-it).

**This is a second instance of the machinery, not a second feature of the
capsule.** The capsule is *one agent, one repo, one unit of work*: a target
checkout, a git channel in both directions, provision and collect, an assignment
record, a per-project egress policy. A room has none of those. Everything below
follows from refusing to make it a slot.

## Where this stands

Nothing is built. Where the *work* is up to is `doctrine backlog list`; figures
are [probes.md](./probes.md); the reasoning this leans on is in the
[ledger](./ledger/index.md), chiefly items 18, 28, 32, 37 and 38.

## The one-line answer

Possible, small, and most of it is ordinary NixOS. `vm/hello.nix` already proves
a non-capsule guest is a supported thing, `mkVm` and `vm/common.nix` are the
seam, and every capsule already reuses `net.nix` unchanged because each lives in
its own namespace. **A room needs no new address, no new port allocation and no
index** — only a namespace name and a listener.

## The shape

**Ingress is a dumb forward, not a login to the host.** A `.socket` unit in the
root namespace, free-bound to the tailnet address; a `.service` with
`NetworkNamespacePath=` the room's and `Accept=yes`, whose whole body is
`socat STDIO TCP:<net.guest>:22`. The accepted file descriptor crosses the
namespace boundary because descriptors are not namespaced — the same trick the
existing ssh relay uses with a unix socket, which crosses because sockets are
filesystem objects and there is no mount namespace here. Nothing routes, nothing
forwards, nothing on the host authenticates.

**No DNAT.** Forwarding into a capsule's namespace is the one thing the module
path's perimeter *is*: the control is that namespace's own `ip_forward`, and
`capsule-perimeter-guard` tears egress down when forwarding appears. A port
forward would trip that, correctly. A userspace relay does not involve it.

**Not the capsule's relay socket.** Its *existence* is the signal every host
program uses to choose its transport — a relay socket for a named capsule means
the module path owns this host. A room that connected through one, or bound its
lifecycle to one, would couple ingress to transport selection. Independent unit,
`BindsTo` the tap for the reason the relay itself does: a namespace unit is
`active exited` and stays up, so anything bound to it outlives every stopped
guest and accepts connections into a namespace where nothing listens.

**The forwarder holds nothing.** `DynamicUser`, empty `CapabilityBoundingSet`,
`NoNewPrivileges`. The capsule's relay runs as the owner so the socket is hers;
a network-facing forwarder wants the opposite.

## Rejected: a forced command on the host's sshd

The tidy-looking alternative is an `authorized_keys` entry on this host —
`command="socat STDIO UNIX-CONNECT:…",no-pty,…` — which needs no new port, no
firewall edit and no listener, and authenticates on an sshd that is already
exposed and already hardened.

Rejected on the owner's judgement, and the reason generalises: **that is a
restriction on a credential, not the absence of one.** The key authenticates to
this host; whether it yields anything more than one capsule depends on options
staying correct in a config *this repo does not own*, with no instrument here
able to see them. That is the shape of items 43 and 44 — a grant that is present
and inert, and a rule that matches a command nobody runs — and both of those
were found only by exercise, on a control this repo *does* declare. A room's door
should not be one more thing whose correctness lives in `~/flakes` and is
checkable only by trying it.

So the guest admits or refuses on its own rules, and the host's part is a pipe.

## What replaces host-side authentication is not authentication

An unknown party occupying the guest becomes a supported state. That costs less
than it sounds, because the guest was always assumed hostile: no shares (a
firecracker constraint, not a policy), no default route, no path to the host, and
guest-authored output already treated as attacker-shaped at collect (item 34).
**The host does not get weaker. The only question is what an occupant can
reach.**

For a room the answer is *nothing*, and that is the design's best property
arriving for free. A guest here has no way out by construction and the proxy is a
separate opt-in unit; a room simply does not run one. No allowlist, no policy, no
`build`-versus-`sealed`, and no exfiltration path, because there is nowhere to
send anything. The closed room that took this repo four sessions to guarantee for
capsules is a room's default state.

Which also settles the rule about controls never moving into the guest. That rule
protects the *host* from the guest. Here the guest's sshd decides who may sit in
a sealed box that cannot reach the host, the LAN or the internet — a different
direction, and the walls are still host-side. If it were ever given egress, the
allowlist would become an exfiltration path for anyone who got in, and the
control for that already exists as `policies.nix`. A room with egress should
declare a narrow selectable set, not `everything`.

## What a plan has to settle

### 1. `capsule-netns` gains an absence, not a kind

The program does namespace, lo, forwarding off, resolver, veth to the
aggregator, default route, and the tap guard rule — with `addr` as a separate
verb, a `down` that refuses while a VMM is in the namespace, and rollback on an
aborted `up`. A room wants that minus the uplink half.

A second, smaller program is the trap: the room's namespace would get a version
that never learned [item 37](./ledger/037-a-teardown-that-only-unnames.md)'s
three lessons, which cost a session and a recovery. So the uplink block should be
conditional on its own environment variables being empty. The program then knows
that *a namespace may have no uplink* — a value, the same shape as
`toolsPackage = null` degrading rather than breaking — and never learns what a
room is. One construction, two callers.

### 2. The namespace name is declared and asserted disjoint

`capsules.nix` derives `ns = "cap-<name>"` and rejects names over 11 characters
or `egress`. A room cannot borrow that prefix without reading as a capsule, and
cannot pick freely without eventually colliding with a slot declared later —
which is precisely
[item 38](./ledger/038-a-probe-that-became-a-borrower.md): a thing became a
borrower by standing still while the declaration moved onto it, with no diff to
notice. So the room declares its own name and an eval-time intersection against
`capsules.nix`'s namespace set throws, copying `probeFabric`/`borrowed` rather
than inventing a second answer.

### 3. Amnesia is a choice, and it should be made explicitly

Guest roots are tmpfs, so `/home` is guest RAM unless it is put on a volume. No
volume means the room forgets itself at every reboot and "burn it down" is a
restart; a volume means scrollback survives and burning down is a delete. Both
are defensible and the default should be stated rather than inherited.

### 4. Who may knock, and who may sit

The tailnet is the outer control and it lives in someone else's config — same
category as the firewall port and the forward drop, which
[item 7](./ledger/007-host-config.md) already establishes as part of the
perimeter that is not in this repo. Bind to the tailnet address, open
the port per-interface (`networking.firewall.interfaces.tailscale0`), and treat
LAN exposure as a separate declared decision with a worse story, never as a
side effect of binding broadly. Inside, "permissive" should mean *permissive to a
declared list*: `users.users.<friend>` with `openssh.authorizedKeys.keys`,
password auth off, no wheel and no sudo. Root stays reachable only by the host's
key.

### 5. Identity ends at the door unless the furniture keeps it

The obvious furnishing is a shared tmux socket, and it has a property that is
easy to miss: **the tmux server's uid is the uid every pane runs as.** Clients
are only terminals; the shells live in the server. So a shared socket is a shared
identity — attaching to one is equivalent to running commands as whoever owns it.
It is also a shared *screen*: same characters, same cursor, interleaved input if
two people type at once. Good for pair-driving one terminal, slapstick as a chat
medium. (`new-session -t <name>` at least gives each client its own current
window, against plain `attach`, which shares even that.)

So the sane arrangement is a dedicated unprivileged user owning the server, and
the consequence is stated rather than discovered: ssh authenticates *alice*, and
alice's identity ends at the door. Inside, everyone is `room`. For a disposable
box that is honest and cheap — but it means no per-person accountability in the
room and no `$USER` worth stamping a message with.

```nix
users.users.room = { isSystemUser = true; group = "room"; home = "/srv/room"; };
users.groups.roomies.members = [ "alice" "bob" "carol" ];

systemd.tmpfiles.rules = [ "d /srv/room 2770 room roomies -" ];  # setgid: the socket inherits the group

systemd.services.room-tmux = {
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "forking";
    User = "room";
    UMask = "0007";
    ExecStart = "${pkgs.tmux}/bin/tmux -S /srv/room/sock new-session -d -s chat";
    ExecStop  = "${pkgs.tmux}/bin/tmux -S /srv/room/sock kill-server";
  };
};

users.users.alice.shell = pkgs.writeShellScriptBin "join" ''
  exec ${pkgs.tmux}/bin/tmux -S /srv/room/sock new-session -t chat
'';
```

**Which is the argument for not doing the chat in tmux at all.** The identity
worth having is the one ssh already established, and the way to keep it is to let
each person's *own* shell do the writing:

```sh
say() { printf '%s <%s> %s\n' "$(date +%H:%M)" "$USER" "$*" >> /srv/room/log; }
tail -f /srv/room/log
```

`/srv/room/log` at `0660`, group `roomies`. Appends this small are atomic on an
`O_APPEND` descriptor, so lines do not shred, and `$USER` is the kernel's answer
rather than a claim — because each person is running as themselves. That is the
whole of it, and it needs no server at all.

Two variants worth knowing. `write`/`wall` is the same idea with no history and
no setup, though it wants `mesg y` and a `write` binary setgid `tty`, which on
NixOS is a `security.wrappers` entry rather than a given. And the properly-built
version is a socket-activated listener reading `SO_PEERCRED`, so the kernel names
the speaker and a nickname cannot be spoofed — unnecessary, and obviously the
correct thing to build.

The two compose rather than compete, which is probably the answer: tmux as the
shared *screen* — a pane already running `tail -f`, plus a window someone can
drive live when there is something to show — and the log as the chat. Presence
and a shared surface from one, identity and scrollback from the other.

### 6. One fork bomb should not be a denial of service against the room

Per-user limits, and a decision on `hidepid` — which is probably *off*, since
mutual visibility is half the point of a shared box.

## Two operational costs, known in advance

**A permanently-running room blocks the probe suite.** Probes refuse when
`any_vm_running`, deliberately unscoped, and that is the only thing the unscoped
question is for. A room that is up all the time means no probe runs on this host
without stopping it first. Take that as-is rather than soften a safety refusal —
but know it now, rather than discovering it six weeks in when a probe refuses and
the reason is a chat room.

**`vm-stop` reaps a non-slot VM rather than halting it.** A room with people in
it wants the graceful path — reboot, not poweroff, via the stop key, for the
reasons in CLAUDE.md's firecracker notes. `vm/stop-key.pub` is already a value a
guest can carry, so the room can have a clean `ExecStop`; what needs deciding is
whether `vm-stop`'s branch learns about it or whether a hard kill is accepted.

## What it touches

| file | what |
| --- | --- |
| `vm/room.nix` | new — users and keys, sshd, limits, home on a volume or not, motd. Most of the work, and it is ordinary NixOS. |
| `flake.nix` | one line in `vms`; the `vm-stop` branch if a graceful halt is wanted |
| `rooms.nix` | new, tiny — namespace name and drop port, with the disjointness assert |
| `host/netns.nix` | uplink block conditional on empty environment variables |
| `host/room.nix` | new — netns unit, tap unit, `.socket` plus `.service` |
| `~/flakes` | the port, on the tailscale interface only |

The room's units belong **inside the existing NixOS module** rather than beside
it: that is what gives them the newline check, the bind-versus-user pairing and
`hostModulePrograms`' shellcheck for free, and those are worth more than the
tidiness of a separate module.

## Why this document exists

Two reasons, and neither is the chat room.

It is the first thing built here that is **not** an instance of *confine an agent
working on a repo*, so it is the first real test of whether the machinery
underneath — namespaces, taps, one image, the halt semantics, the ingress relay —
is separable from the product. If a room cannot be built without teaching
capsule code what a room is, the seam is in the wrong place, and that is worth
knowing whether or not anybody ever chats through it.

And it is a case where several of this repo's sentences stop being true quietly.
`net.nix` opens with "no bridge, **no LAN exposure**". Item 18's inversion says
the host initiates both directions and the guest has no inbound channel. Item
32's collect is unscoped because one capsule is one agent doing one thing. None
of those is a bug and none of them survives a room unqualified — which is the
[item 42](./ledger/042-a-state-half-no-capsule-has-held.md) pattern again, a true
sentence going false because the thing it described acquired a second shape.
Anything built from this plan should annotate them in the same commit.
