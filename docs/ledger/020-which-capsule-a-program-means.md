# NOTES item 20 — which capsule a host program is talking to

*State: decided, built, run at N=2 on both paths.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Which capsule a host program is talking to.** One bug, in one line, and it
is the thing that stood between the units running at N=1 and running at N=2:
`host/services.nix` built `hostPrograms` once, with the lowest-indexed
capsule's relay socket in `sshArgs`. So `capsule-provision`,
`capsule-collect`, `capsule-inject` and `capsule-baseline` each carried one
capsule's transport in their store path, and a second capsule had no way in
for any of them. `probe/two-capsules.sh` is where it surfaced — it needed two
sets of programs to provision two capsules, and recorded that as a finding
rather than plumbing.

The one-image lever is what makes the fix small. Every capsule runs the same
guest from the same store path at the same address
([item 17](./017-more-than-one-capsule.md)), so the *only* thing that differs
between two of them is the relay socket — and that path is a pure function of
the name (`capsules.socketOf`). N programs would be N store paths differing in
one string. So the name is a run-time value and the transport is derived from
it: one store path, every capsule.

**The seam was already right; it only had to widen.** `sshArgs` was injected
at the call site precisely so the two paths could differ (`host/programs.nix`).
It is now `transport`, a *shell fragment* rather than a value: spliced at the
top of each program, it resolves which capsule this invocation means, strips
that argument out of `"$@"` before the program's own flag loop sees it, and
sets `ssh_cmd`. The devshell injects the direct form, the units inject the
via-socket form, and neither `host/programs.nix` nor the three programs under
it learn anything about namespaces or sockets.

**The CLI question, decided rather than accreted.** Plan C
[item 7](./007-host-config.md) wants a `capsule <name> <verb>` front end; this
needed an answer first, because `capsule-provision <ref>` and `capsule-collect
<quarantine-name>` took different positionals and neither took a capsule. Three
things settled it:

- **A flag, not a leading positional.** `capsule-collect faux` means a
  quarantine today; making it mean a capsule tomorrow is a silent change of
  meaning on a command that already exists. `--capsule <name>` (or
  `--capsule=<name>`) collides with nothing, and every one of the four
  already refuses an unrecognised `-*`.
- **`CAPSULE_NAME` as the session default**, joining `CAPSULE_ROOT`,
  `CAPSULE_STATE` and `CAPSULE_REPO` — you work on one capsule for an hour,
  not one command. Not the *only* form, because `VAR=x prog` is not
  universal: nushell wants `with-env`, and this host's shell is nushell.
- **The default is `capsule`, and it is a value** (`capsules.default`), so the
  single-capsule state this host already has keeps working untyped and the
  `just` recipes' default is the same word by derivation rather than by
  coincidence.

A `capsule` CLI on top of this is now thin: resolve the name, export it, exec.
That is the argument for doing it in this order.

**One argument fewer, not one more.** `capsule-collect`'s positional
quarantine name *was* the capsule name at every call site, so it is gone: a
capsule names its own refs and its own quarantine, at the same paths as
before. The asymmetry closed by deleting half of it.

Two smaller decisions worth freezing, both refusals:

- The devshell's fragment **refuses a name that is not its one capsule**
  rather than ignoring it. Ignoring it is a silent success — "provisioned
  `edge`" while the bytes went to the only capsule there is.
- The via-socket fragment **refuses when the socket is not there**, naming the
  relay unit. Without it the failure is socat's, one layer down, and reads as
  a dead guest.

Not done this way, deliberately: probing for the socket and falling back to
the direct address — which is what `just _guest-ssh` does. It would delete the
injection entirely, and with it the property that `host/programs.nix` knows no
transport: a program that can try both has both baked in. It also turns a
stopped relay into an unroutable-address timeout instead of a refusal.

**Run, and by the probe that found it: `sudo probe-two-capsules`, 28/28.** One
program set, `--capsule` per call, two capsules provisioning over their own
sockets and collecting into their own quarantines. The four assertions that
depend on the transport are the four that would have failed, and the figures
reproduced run 1 inside a tenth of a second ([probes.md](../probes.md)). The
`%q` requoting of `GIT_SSH_COMMAND` is exercised by that run — a provision and
a collect each go through it, over a ProxyCommand with spaces in it.

~~Still unrun: the *module* path.~~ Run — the module's copies of all four are
what provisioned, injected and baselined both capsules at N=2, so the
via-socket form with an absolute `socat` and the `wrap`ped state directories is
exercised.

**The CLI is built, and what it cost was a boundary rather than code.**
`host/cli.nix`: `capsule [<name>] <verb> [args…]`, name first, omitted meaning
`capsules.default`. It resolves a name, picks a copy, execs. Three things it
decided on the way:

- **Where the split falls.** `microvm -c <name>` resolves the instance's name as
  a flake attribute ([item 21](./021-declared-capsule-flake-attribute.md)), so
  *creating* a capsule cannot happen without this checkout and *running* one has
  no business needing it — the units are on the host and a human logged into it
  has no repo. So `just up` keeps the create and the tap refusal, and every
  other run-time verb moved into the program. The recipes that remain are
  one-line delegations kept for their defaults and their comments; `_capsule`
  and `_guest-ssh` are gone rather than wrapped, which is the whole reason to do
  this at all — the alternative was a second implementation of the ssh door and
  the copy-picking.
- **Picking a copy is a front end's latitude; carrying two transports is not.**
  The four programs still refuse rather than guess, which is this item's
  decision and stands. What the front end does is choose between two *copies*
  of one program — the same latitude `just _capsule` already took, now in one
  place. It injects no transport and holds no socket path of its own:
  `capsules.socketOf` applied to a shell expression, as everywhere else.
- **Two refusals, both of them ambiguity rather than failure.** A capsule whose
  name is also a verb is an *eval* error, since `capsule <x> …` could then be
  read either way and both lists are known at build time. And a `--capsule` in
  the arguments of an already-named capsule is refused instead of resolved: the
  programs' own parse takes the last one, so `capsule capsule-b provision
  --capsule capsule` would have succeeded against the wrong capsule quietly.

One store path, installed by both paths, and that is the honest statement of
what it is: unlike the four programs it has no transport, so there is nothing
for a second instantiation to differ in. `.#capsule-cli` as an attribute,
`capsule` as the program — `.#capsule` has been the guest runner all along.

**The door is run, and the thing it was needed for is what proved it.** `capsule
<name> ssh 'tail -1 /work/baseline/history.tsv'` answered 112 s from one capsule
and 121 s from the other — the pair of rows the load round could not tell apart
by prompt, since every guest is `agent@capsule`
([item 21](./021-declared-capsule-flake-attribute.md)). The hostname is still
`capsule` in both, which is the price, not a bug; asking the *volume* is the
answer, and the CLI is what makes asking one command per capsule.

**`status` and the aggregates, and how the blindness actually closed.** `just
status` could not see inside a namespace it did not own, and the fix is not a
way in — `ip netns exec` wants CAP_SYS_ADMIN and a status that needs root is a
status nobody runs. It is *naming the witness*. Every column of `capsule all
status` is readable from the root namespace (`LoadState`/`SubState` of the VM,
proxy and relay units, the socket, the quarantine's ref count), plus one that is
not any unit's opinion of itself: an ssh probe through the capsule's own socket,
because every unit reported health through the evening the VM was crash-looping
in the wrong namespace. What is genuinely inside — each namespace's
`ip_forward=0`, the tap's input drop, the drops between capsules — is
`capsule-perimeter-guard`'s, audited every 10 s with egress bound to it, so its
being active *is* the per-namespace verdict for every capsule at once. The table
prints that as a witness line rather than printing "unknown".

Two decisions inside it:

- **`all` is a name, not a flag**, so it composes with the name-first grammar
  instead of adding a per-verb option. It is refused as a *capsule* name at
  eval, same as a name that collides with a verb.
- **`all` aggregates questions, not actions.** `status`, `branches` and `fetch`
  take it; `start`, `stop`, `setup` and the four programs do not, because what
  to do when the third of five fails is a policy nobody has decided — and an
  action half-applied across N capsules is worse than one refused. When someone
  wants that policy, this is where it goes.
- The probe uses the git channel's ssh relaxation rather than the human's strict
  door (`host/guest-ssh.nix`): a rotated host key is a fact about identity, and
  reporting it as an unreachable guest would be the wrong answer to the question
  being asked. The human's `ssh`/`admin` keep the strict default, because a
  human is there to read the warning.

On the way past, one real bug in the recipe this replaced: `just proxy-log`
still looked for `/var/lib/capsule-proxy/tinyproxy.log`, from before the proxy
became one unit per capsule, so it fell through to the devshell path's log and
reported "no proxy log yet" on a host with two of them.

**Correction: the socket being the identity means its lifetime must be the
capsule's, and it was not.** `capsule-ssh-relay-<name>` bound only to its
*namespace* unit, which is `active exited` and stays up — correct for a
namespace, wrong for the way into a guest. So a stopped capsule kept a live
listener, and because `[ -S "$sock" ]` is the whole test both transports use,
the consequences ran in both directions at once: the devshell's copy
**refused** on a module path that owned nothing, and the module's copy
**hung** — socat accepts the unix connection immediately and then blocks
forwarding to a guest that is not there. Two capsules dead, two proxies dead,
two relays `active running`, and every program on the host convinced the
module path was live.

The fix is one list: `bindsTo` the tap unit as well, which is what the proxy
already does and for the same reason — the tap is what a VM pulls up and takes
down, so both follow the guest instead of the namespace. `ConnectTimeout=10`
in `host/guest-ssh.nix` was already there and is the reason this reads as a
slow failure rather than a wedge, but it is the wrong layer to rely on: a
bounded lie is still a lie, and the honest state of a stopped capsule is no
socket. Note which of the two symptoms is the dangerous one — the refusal is
loud and names the copy to run, so it was the *hang* that cost the time, from
the copy the refusal recommends.

**Second correction: the refusal was rolled out by flag, and `vm-stop` has no
flag.** The set of programs that got the devshell copy's refusal was drawn as
*the ones that take `--capsule`* — which is `host/guest-ssh.nix`'s `direct`, and
therefore the four. `vm-stop` takes its name positionally and consumes no
`transport` at all, so it fell outside a boundary that was never the right one:
the property that matters is **whether a program ssh's at `net.guest`**, and it
does, through `capsule-halt`.

`capsule-halt` looked like it needed nothing, and the reasoning was sound as far
as it went (`host/halt.nix`): it is *namespace-relative*, and both its callers
run it where the guest is directly routable — the unit from inside the capsule's
own namespace via `NetworkNamespacePath`, this program from the root namespace
where the devshell path's tap lives. So it takes an `--identity` and no
transport. What that misses is that `vm-stop` is the caller which can be invoked
on the wrong host shape, and it carries `capsule-halt` there with it.

The failure is worth reading as a composition, because every part of it is
individually correct. The ssh times out at `net.guest`; `capsule-halt` reports
`no guest answering` — the wrong cause, since the guest answers fine through its
relay; `own_vms` then finds no VMM in this shell's namespace, which is right and
is deliberately right, since a bare `pkill -f` on `microvm@capsule` is a power
cut for every namespaced sibling; and the fall-through prints `is down` over a
capsule that is still running. **Two true-in-scope sentences composing into a
false one** — the `pkill -f` trap one level up, where the scoping is correct and
the claim it licenses is not. It reads as a clean teardown, which is the same
thing the scoping exists to prevent.

The fix is `direct`'s second refusal, owed by a program that never selects a
capsule because its argv is the name already: `[ -S "$(socketOf "$name")" ]`,
naming `capsule <name> stop`. Note it is not exercised by anything — it fires
only while a module-path VM is up, and the stubbed cases cannot reach it, since
the socket path is baked and creating one is root's. That places it beside the
privilege class in CLAUDE.md rather than beside the case suites.
