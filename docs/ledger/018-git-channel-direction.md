# NOTES item 18 — which way the git channel points

*State: measured, inverted, done.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Which way the git channel points — measured, inverted, and done.**
Asked because doctrine wants to know how a result leaves a capsule; answered
with two commands, and the answer deleted more than it added.

It used to be that the **guest pushed**: the host ran `receive-pack` as a
live service on a port the guest could reach, and the ref hook, the
`capsule-git` group and the mirror-sync uid all existed to confine that. The
host now **initiates both directions** over the ssh channel that already
existed — `capsule-provision <ref>` pushes history in, `capsule-collect`
fetches work out into a host-side quarantine repo.

**Both directions run, n = 1, on Sleipnir, on the devshell tap shape.** For
doctrine — 66.4k objects, 32 MiB — each direction moves at ~100 MiB/s over the
tap, so the link is not the cost. The push needs
`receive.denyCurrentBranch=updateInstead`, which accepts an unborn HEAD and
leaves a populated worktree, so provisioning is one host action with no bare
intermediary and no guest-side step. It refuses once the worktree is dirty —
mid-session re-provisioning is the thing that costs, and a bare
`/work/origin.git` plus a guest-side local clone is the fallback if that
matters. Freshness ([item 17](./017-more-than-one-capsule.md), `REQ-450`) means
never re-provisioning, so those two decisions hold each other up: if anything
ever needs a mid-session re-provision, both move together.

**`denyCurrentBranch` only governs the branch HEAD names, and that is
load-bearing.** Push a branch the guest's HEAD does not point at and the
guard never applies: the ref lands, the worktree is untouched, and nothing
says so — a capsule with history and no files. So the guest's HEAD must name
the branch provision pushes to. It does, twice over: `capsule-seed` passes
`--initial-branch` explicitly rather than leaning on `init.defaultBranch`,
and `capsule-provision` checks the guest's advertised HEAD symref before
pushing and refuses if it has moved — which is the case that actually
happens, an agent running `git checkout -b`. `git ls-remote --symref` does
the check over the git transport, so the program still knows only a URL; an
empty repo advertises no symref at all, which is why the seed has to
guarantee the first one.

**A correction that was itself wrong, worth recording as method.** This rule
was found by a reproduction that concluded the original probe had only
appeared to work — `git init` giving `HEAD = refs/heads/master`, so the push
of `edge` bypassing the guard. That is not what happened here: the probe ran
`git init` *inside the guest*, where `/etc/gitconfig` sets
`init.defaultBranch = edge`, so HEAD was on `edge` and `updateInstead` did
apply. Verified after the fact — `git config --show-origin` reports
`file:/etc/gitconfig edge`, `/work/scratch` HEAD is `refs/heads/edge`, and its
worktree is populated. The rule is real and the fix is worth having; the
retraction was an artefact of reproducing in a different environment, which is
the same `n = 1` trap in the other direction.

**Both programs then ran against a real fresh capsule**, which is what the two
hand commands only modelled. Provision: 32 MiB in, worktree populated at the
named commit on `edge`, clean. Collect: 32.10 MiB out at 118 MiB/s,
`transfer.fsckObjects` passed, `ulimit -f` untouched, and exactly one ref
landed — `refs/capsule/capsule/edge`, no `refs/tags/*`, which is the
`--no-tags` claim holding in practice rather than in argument.

**The first collect per capsule always pays a full transfer**, and that is the
price of quarantining rather than a defect: a host-authored repo cannot share
objects with `~/dev/doctrine`, so 32 MiB crosses the link and a second copy
lands on disk even though the host already had every object. Later collects
are incremental, which is most of why the quarantine is kept. `--depth` would
cut the first one and breaks the second step into the real repo;
`objects/info/alternates` pointing at the target repo would remove the copy
and make the exhibit non-self-contained, which defeats the point of keeping
it. So the cost stands: N capsules is N full first-fetches and N × repo on
disk. Trivial at 3-4 on a dev machine, not at ranch scale — and it is the
per-instance disk figure that was asked for.

The doubled segment in `refs/capsule/capsule/edge` is the default instance
name meeting the namespace, not redundancy: the quarantine is per capsule
*and* the refs are namespaced, because `just fetch` merges several capsules'
refs into one real repo and that is where the name has to survive. It reads
correctly the moment a capsule is called anything else.

**Git over the netns unix-socket `ProxyCommand` now runs**, which
[item 17](./017-more-than-one-capsule.md) had only crossed with socat and raw
bytes: `probe/netns-boot.sh` does `git ls-remote --symref` against the guest
through the socket, as the human, with the guest in a namespace — the same call
`capsule-provision` makes before it pushes. Still not measured: throughput over
the socket (the tap did ~100 MiB/s each way), and whether `transfer.fsckObjects`
rejects anything the old push path accepted.

**The refspec does not fully decide the destination.** The fetch also wrote
`refs/tags/*`, outside the `refs/capsule/<name>/*` namespace it was given,
via automatic tag following. Harmless into a disposable quarantine repo, but
`--no-tags` is what makes "the host chooses where guest refs land" true as
stated, and the unqualified version of that claim should not be repeated.

**Nor does the guest stop initiating connections to the host** — the proxy is
one, and tinyproxy is the larger of the two C parsers of guest-authored
input. What the inversion removes is any host service that parses guest git
input. That is the claim worth making; the stronger one is wrong.

**The finding that decides it was a live defect, not the probes.** The guest's
`origin` was dead while both new directions worked. `capsule-gitd` is up and
reachable; `upload-pack` refuses inside — git 2.55 `detected dubious ownership`,
because the daemon runs as `capsule-git` and `capsule-sync` creates the mirror
as the human. So [item 1](./001-what-has-been-run.md)'s "exercised in both
shapes" is stale for this half: the unit path's git channel had stopped serving.
Fixed where it broke — `GIT_CONFIG_*` on the unit, which is the `command` scope
and so counts as the protected configuration `safe.directory` insists on. Needs
a host rebuild to take effect, and is the safe direction of that exception: the
serving uid trusts a repo the human owns. The reverse is the escalation below,
and has no exception.

Underneath that is the reason the check exists. The mirror is `2775` group
`capsule-git` with `core.sharedRepository=group`, because the push design
*requires* two uids to share one repo — the human syncs it, the daemon serves
and receives into it. So `hooks/` and `config` are writable by the daemon's uid,
and `capsule-sync` and `just fetch` both run git in that repo **as the human**.
A compromised `receive-pack` — the precondition the uid split exists for —
writes `hooks/post-receive` or sets `core.hooksPath`, and the next sync executes
it as you. [Item 11](./011-host-side-runs-as-you.md)'s "the uid serving the
mirror has no path to the tree the mirror came from" is therefore not true: the
path is the human's next sync. It is also the same shape as doctrine's rule
about never running trusted git in a capsule-authored repository, reached from
the host end instead of the guest end.

**The inversion removes the precondition rather than the bug.** No repo is
written by two uids anywhere: the host pushes from a repo only the human
writes, fetches into a quarantine repo only the human writes, and the
guest's repo is only the guest's. No setgid, no `sharedRepository`, no
`safe.directory` exception, nothing for a compromised daemon to leave behind
— because there is no daemon.

**What went**, and the `safe.directory` fix above went with it, having lasted
one commit: `perimeter/`'s `sync`, `gitd`, `pushGuard`, export marker and
`gitPort` — leaving it the proxy and nothing else, which is what the perimeter
now is; `host/services.nix`'s `capsule-gitd` unit, `capsule-git` user and group,
and setgid state directory; the mirror itself, since it *was* the two-uid repo;
`net.nix`'s `gitPort`; and the guest's `capsule-clone` and `capsule-push`,
leaving the guest with no capsule-specific program at all. What arrived is
`host/git-channel.nix` — two programs, no service, jail-shaped transport
injected at the call site on the same seam as `preflight`/`watch`. One of the
two ports leaves the host's own firewall stanza too
([item 7](./007-host-config.md) — outside this repo, so it is a README change
and a rebuild you do). In PLAN_C it retires the per-capsule git daemon entirely,
and with it the whole "one gitd uid or N" question.

**It also finishes the single-image goal in
[item 17](./017-more-than-one-capsule.md) for free.** The base commit was one of
the two per-instance values that had to leave the guest's closure, and
`capsule-clone` baked it in exactly as it baked the remote. It is now an
argument to a host command — required, not defaulted, because a capsule's pin
should be stated at every provision — so the only value left in the closure is
the address, which netns already handles.

Five things it costs or leaves open, none of them fixed by pretending
otherwise:

- **`index-pack` still parses guest bytes host-side.** True of every option
  including bundles. `transfer.fsckObjects` is on, and `ulimit -f`
  (`target.collectMaxPackBytes`) bounds the packfile — but **that is a
  backstop on one file, not a bound on the transfer.** RLIMIT_FSIZE: a pack
  of a million small objects never trips it and still fills the disk, and a
  delta bomb never trips it and still eats `index-pack`'s memory. A real
  bound needs a quota or a dedicated filesystem for the quarantine directory
  (disk), `ulimit -v` or a `MemoryMax` cgroup around the fetch (expansion),
  and `--depth` (input) — the first of which is host config, the same
  category as the nftables drop. **Do not read the `ulimit -f` as closing
  this.**
- **The quarantine is persistent, not fresh**, which is a deviation from what
  was accepted: kept so a second collect is incremental, and because the
  repository is the retained exhibit. The execution-context rule is
  untouched — it is host-created, host-configured, and the guest can write
  neither its config nor its hooks — only freshness changed. Recorded here
  rather than left to be discovered.
- **The sha is the pin; the quarantine repo is the exhibit.** So reaping the
  quarantine is when the exhibit expires, and nothing here sets that
  retention. First concrete instance of a knob that was deliberately left
  unspecified upstream.
- **Non-git provisioning inputs have no program.** The guest boots empty and
  gets one push, which carries committed objects only. Uncommitted files,
  gitignored working material, generated config and secrets have no carrier
  — today's `/work/.env` is still made by hand over ssh. The *transport*
  exists and is already host-initiated; what is missing is anything that uses
  it, and a worker needing a `.env` is how that gets discovered rather than
  decided.
- **The agent loses the ability to hand work over.** `capsule-push` was the
  guest's own act; now only the host pulls. A workflow regression rather than
  a security one, and the only thing the inversion makes worse.

**The first thing a fresh capsule broke was `known_hosts`, and it was the git
channel that made it matter.** The guest's host keys live on its volume, so a
new volume means new keys at the same address; a real capsule hit exactly that.
Before, ssh was convenience and a changed key annoyed `just ssh`. Now the
channel rides ssh, so it blocks provisioning outright — and freshness
([item 17](./017-more-than-one-capsule.md), `REQ-450`) means it fires on *every*
capsule, not occasionally. `StrictHostKeyChecking=accept-new` is not the fix: it
accepts hosts that are unknown, and this one is *changed*.

So `guestSsh` in `flake.nix` turns the check off and keeps no record
(`UserKnownHostsFile=/dev/null`), injected through `sshCommand` — the seam
that exists for exactly this, so `host/git-channel.nix` still knows only a
URL. `vm-stop` takes it too, or a fresh capsule's key would send its shutdown
down the API-socket fallback. **It is sound only because of what the link
is:** a /30 this host created, one peer, nobody on it to be in the middle. A
bridge, a LAN or another machine invalidates it, and it has to change in the
same commit that changes the transport. A capsule-scoped `known_hosts` file
was the tidier-looking option and is worse — it accumulates a stale key per
capsule and reintroduces the failure it was meant to fix. `just ssh` and
`just admin` deliberately keep the strict default: a human is there to read
the warning. Under netns none of this is needed, because the socket path is
the identity ([item 17](./017-more-than-one-capsule.md)).
