# Status — where this stands, and what is next

The one place the current state lives. Read it before picking the work up cold,
and edit it when the state changes rather than adding a second account of it
somewhere. Figures belong in [probes.md](./probes.md), reasoning in
[ledger/index.md](./ledger/index.md); this file says what is true now and what
happens next.

Last updated 2026-08-16, after **[item 51](./ledger/051-the-target-in-four-store-paths.md)'s
step 0 was built**: the seven case suites are out of `flake.nix` and beside what
they pin, one file each — `host/guard-cases.nix`, `host/brief-cases.nix`,
`host/state-snapshot-cases.nix`, `host/baseline-cases.nix`,
`host/observe-cases.nix`, `host/refresh-cases.nix`, `host/policy-cases.nix` —
each a function of `pkgs`, `lib` and **the store path the program ships**, with a
short `import` left at the call site. `flake.nix` 2565 → **1263**; the seven
attribute names, the `packages` set and `just cases` are unchanged, and every
case's log line is byte-identical before and after. The two suites handed a
*fixture* rather than a shipped path — the guard's stubbed kernel, the front
end's pool that is not this host's — came off **unchanged store paths**, which is
the move asserting its own claim; the other five rebuilt only because a markdown
link inside a shell comment had to become `../docs/ledger/…` a directory down.
`just` green, nothing switched, no capsule touched. Step 3 is next and is gated on
the item's three decisions. Before that, the same day, after **that item's first
two steps were built**: the five guest-pushed scripts — `state-snapshot`,
`refresh`, `brief`'s runner, `observe` and `baseline`'s runner — take every value
they are *about* on their command line instead of in their text, so
`snapshotFor`, `refreshFor` and `runnerFor` are gone and each is one store path
where it was one per checkout. Nothing has yet changed about *where* those values
come from — `target.nix`, spelled by the host program that makes the call — so no
program has stopped being a function of the target; that is step 3 onward, and it
is gated on three decisions the item now names rather than one. Two things the
plan did not have: `host/guest-exec.nix`'s `loginRun` had **no argument channel at
all** and is `bash -l -c 'bash -s "$@"'` now, and a value crossing ssh is parsed
by **two** shells so it is escaped twice — `capsule-baseline`'s nested
`bash -l -c "bash '$dir/run.sh' …"` made it three and is the `"$0" "$@"` shape
now. `observeCases` and `baselineCases` are new — those two programs had **no
suite at all** — so `just cases` runs seven, and each was watched going red
against a deliberately broken copy of what it pins. `just` green; nothing
switched, and no capsule was touched. **And the work produced a step in front of
its own remainder**: `flake.nix` is now 2565 lines of which **1341 (52%) are case
suites**, ~530 of them from this session, so the item's step 0 is one file per
suite beside what it pins (`host/<name>-cases.nix`) — behaviour-free, and to be
done before step 3 rather than inside it. Before that, the same day, after
**[item 50](./ledger/050-a-quarantine-outlives-its-assignment.md)'s
read was taken and the reading under it was half wrong**. Two assignments to slot
`e`, one quarantine: the code half behaves as the item predicted — forced,
non-fast-forward, the first assignment's commit left `unreachable` — and the
state half **fast-forwards**, because it was never forced at all. The guest
parents each snapshot on its own `refs/capsule/state/<stage>`, which lives on the
volume and which a provision does not touch, so the chain crosses the reprovision
and is rooted in a commit *this host* wrote. **A refspec's `+` says what a fetch
may do, never what it did.** And `capsule <slot> fetch` is **unforced** where the
collect is forced, so the second fetch is rejected for code and accepted for
state: `~/dev/doctrine` now holds **assignment 1's code beside assignment 2's
state**, under two names that say they belong together, from a verb that exited 1
without naming either half
([probes](./probes.md#two-assignments-one-quarantine)). Nothing was built or
changed; `c`'s quarantine was deliberately left unspent and `e` was already
finished with. Before that, the same day, after **a capsule six hours into a unit
of work was handed whole to another slot, in four commands and without root** —
the c→d migration, and the first run of the composite's *other* origin,
`capsule-provision --state <capsule>`. `capsule c collect` (1.162 s; 31 files,
678701 bytes at unit `251`), `capsule c fetch`, `capsule d provision
refs/capsule/c/heads/work --state c` (9.618 s), cold baseline green in 120 s
([probes](./probes.md#a-capsule-handed-to-another-slot--what---state-capsule-costs)).
`d` holds `c`'s HEAD `18e35c2e5`, its `research/` and `phases/`, and its one
uncommitted worktree edit still uncommitted. **The composite is what made it one
step**: the sequence written down in HANDOVER was `setup` then `capsule d brief
c`, which is exactly [item 47](./ledger/047-a-script-on-stdin-and-the-command-that-eats-it.md)'s
window — a brief taken after a provision refuses on a target whose refresh writes
tracked files, and that is what left slot `e` at `0ab546b6c`. Two untracked paths
in `c` sat outside `statePaths` and were committed there first; `$HOME` did not
travel and cannot. Before that, the same day, after
**[item 42](./ledger/042-a-state-half-no-capsule-has-held.md)
was delivered — and getting there found that the third step of every provision
this repo has ever run was being eaten off stdin**
([item 47](./ledger/047-a-script-on-stdin-and-the-command-that-eats-it.md)).
Slot `e`, declared and never created before today, took the state half for
doctrine's `SL-251` in **one command**: `capsule e provision 582300f14
--state-from-host`, **5.204 s** end to end, of which the target's own refresh is
4.553 s — so the push and the whole state half are **≈0.65 s**, under a fifth of
the step they make way for
([probes](./probes.md#the-delivery-and-what-a-provision-that-carries-its-own-state-costs)).
`research/`, `design.toml`, `design-journal.toml` and `phases/` are in the guest,
the worktree is clean, and everything downstream of the snapshot has now run.

**Three things fired for the first time in that session and only one is the
delivery.** The host-side `code-oid` precheck, taken deliberately against a slot
provisioned one commit behind — one round trip, `Nothing was taken and nothing
was pushed`. `host/refresh.nix`'s **commit branch**, which had never executed in
that file's life. And the push, layout and exhibit checks against a
host-authored tree.

**What blocked it is the finding.** `host/guest-exec.nix`'s `loginRun` is
`bash -l -c 'bash -s'`, so a host-authored guest script *is* the guest shell's
stdin — and doctrine's refresh is a TUI, which drained it and took the rest of the
script with it. Everything below `( ${command} )` in `host/refresh.nix` had never
run: the status check, the `after` snapshot, the commit, all five messages. A
refresh whose command failed reported success, which is exactly the trap that
file's header names as the thing to avoid. Found not by reading but by a **fresh**
capsule's push being refused `Working directory has unstaged changes` ten minutes
after it was provisioned. `</dev/null` on the target's command is the fix; the
suite written to pin it found a **second** defect underneath — `before`/`after`
were `--porcelain` status lines, which name *files* and not *contents*, so a
refresh rewriting an already-modified file read as no change and the dirty-tree
refusal was unreachable in precisely the case it is about. `git diff HEAD` now.
`refreshCases` is 14 cases and the fifth instance of the third kind of check, with
its invocation load-bearing: it runs the script **on stdin** the way a guest does,
because `bash <script>` passes against the broken text.

**And the ordering neither defect causes is settled.** With a refresh that writes
tracked files there is no *after* a provision: it either commits — moving HEAD off
the commit `code-oid` compares against — or leaves the worktree dirty, which the
brief refuses. So the brief moved **inside** the provision at step (2):
`capsule-provision --state-from-host [--stage] [--unit]`, which is the composite
[item 45](./ledger/045-a-brief-is-an-origin-not-a-top-up.md) asked for and item 42
declined to build until somebody wanted it. Observed rather than argued: a
`capsule e brief --from-host` taken straight after the delivery refuses, and the
remedy it names would end in another refresh commit. Item 45's *hit* is a
*deliver* now; its own open question — whether a top-up is a scoped additive verb
or a refusal — is untouched, because this removes the window rather than serving a
capsule already inside it.

Before that, 2026-08-15, after **[item 42](./ledger/042-a-state-half-no-capsule-has-held.md)'s
case arrived in the wild and the verb built for it could not serve it** —
[item 45](./ledger/045-a-brief-is-an-origin-not-a-top-up.md). Slot `c` was two
hours into doctrine's `SL-251` when the out-of-band state half turned out to be
missing from it, and `capsule-brief --from-host` could not deliver it for four
reasons that compound and are **each correct**: the host checkout was two commits
ahead of the guest, so `code-oid` refuses; the guest held one modified tracked
file under a declared path, so the brief refuses; had it not refused it would
have overwritten that file; and a brief is whole-tree, so it would also have
rewritten `phases/`. Committing the agent's edit clears the second by making the
first unfixable, which is the finding: **the window in which a capsule can be
briefed is the window before its agent starts working.** The gap was narrower
than "no state" — the authored tier had ridden in on the code half and the empty
phase sheets had been regenerated by `doctrine boot`, so what was missing was
exactly the ignored tier a push cannot carry: `research/` (92 KiB),
`design.toml` (234 KiB) and `design-journal.toml`. Delivered **by hand** — `tar`
over the door, scoped to those three absent paths, `-k`, seven checksums matched
and nothing overwritten — which is additive and therefore defensible, and carries
no `code-oid`, the shape item 42 rejected `rsync` for. Two things follow: the
open question of whether a top-up is a scoped additive verb or a refusal saying
*brief before you start*, and the argument for
`capsule-provision --state-from-host`, which item 42 declined to build until the
delivery made somebody want it. **None of it is evidence that `--from-host`
works** — nothing pushed, laid out a tree, or ran the precheck, so the delivery
is owed exactly as much as before, and `c` is now the slot that cannot host it.
Before that, after **the sideband arc got an origin that is not a
capsule** — [item 42](./ledger/042-a-state-half-no-capsule-has-held.md), built
and measured, with nothing delivered to a guest yet. `capsule-brief --from-host`
takes a unit's out-of-band state out of `target.path` using
`host/state-snapshot.nix`'s own text — the third instantiation of one
tree-builder, at the human's checkout instead of a guest's — and pushes it in
over the door a brief already had. **Two decisions were owed and both are made.**
A quarantine is **what a capsule sent back**, not a place state lives, so this
keeps *no archive at all*: the ref is dropped either side of the delivery, the
objects it writes are gc's, and `briefCheckSpec` refuses any source that is not a
declared slot. And the untracked sweep is an **argument with no default**, because
"one agent's uncommitted work" is a property of a capsule and is a desk on a
host. Measured on doctrine's live checkout for `SL-251`: **30 entries, 554 KiB,
27–38 ms, and the same tree twice** on a checkout being worked in — with the
counterfactual in the same breath, 34 entries at `all`, three of the four extras
written into the tree by a different process seconds earlier
([probes](./probes.md#a-state-half-authored-on-this-host--the-origin-that-is-not-a-capsule)).
`snapshotCases` is 29 → **43**, `briefCases` 14 → **23**, both watched going red
on a mutation. The item's own first suggestion — `GIT_DIR` at a quarantine — is
**refuted**: a quarantine's HEAD is unborn, so it makes `ls-files -o` call the
whole checkout untracked. **Owed: a delivery** — slot `c` is provisioned at
`de32c856b` and this checkout is at `f49314de8`, so a brief refuses until `c` is
re-provisioned at the commit the checkout is on. Writing that sequence down found
one defect before it was run: `briefDeliver` pushes before the guest speaks,
which from a capsule is harmless (a retry pushes the *same* commit) and from a
host origin is not, because there is no archive and so **every run is a new root
commit** — a refused attempt would leave a ref the retry cannot fast-forward, and
the retry would fail naming a cause that is not the cause. There is a host-side
`code-oid` precheck now, one round trip ahead of the snapshot, so a mismatch
writes nothing anywhere; the guest's refusal stays the control and is now
reachable only by HEAD moving mid-flight. Before that,
after **`capsule <slot> policy <name>` reached root
unattended for the first time, which finishes
[item 41](./ledger/041-a-delegable-verb-that-ends-in-root.md) and takes
[item 36](./ledger/036-a-policy-is-selected-not-named.md)'s last owed
exercise.** `sudo -K`, then `capsule b policy sealed` — no prompt, the proxy
restarted, generation 21 — and `capsule b policy build` back again at 22: the
**in-place restoration**, one slot, out and back, nothing moving but the proxy.
Nothing warm carried it, since no password was typed after the `-K` and a
`NOPASSWD` match records no timestamp. `b` is on `build`.

It took two faults to get there and both were found by running that one
exercise, neither visible to anything in this repo that reads a declaration:
[item 43](./ledger/043-a-grant-that-was-present-and-inert.md), the grant present
and shadowed, and [item 44](./ledger/044-a-rule-matches-a-path-not-a-name.md),
the rule naming a command the program does not run. The instrument common to
both is `sudo -n -l`, which printed a command back three times and meant nothing
each time: it answers *some rule permits this*, never *which matching line won*
and never *whether it would run free*. Before that, after **item 43's switch
landed, the verb prompted anyway, and the reason is
[item 44](./ledger/044-a-rule-matches-a-path-not-a-name.md): the rule names a
command the program does not run.** The rendered sudoers is now exactly right —
no blanket, the grant last — and `capsule b policy sealed` on a cold ticket still
answered `sudo: a password is required` and rolled back. This host sets no
`Defaults secure_path`, so sudo resolves an unqualified command against the
**caller's** `PATH`, and `writeShellApplication` prepends `runtimeInputs`: the
front end's `systemctl` is `/nix/store/…-systemd-261.1/bin/systemctl` and the
rule names `/run/current-system/sw/bin/systemctl`. Two commands.
[Item 41](./ledger/041-a-delegable-verb-that-ends-in-root.md) wrote that reason
down backwards and the paragraph is annotated in place; its *choice* of path
stands, because a store-path rule would lapse at the next systemd bump, silently
and fail-open. **The command is one value now** — `host/proxy-restart.nix`,
imported by the front end that runs it, the module that grants it and
`flake.nix`'s `unrestartable`, which had been green because it paired the module
against itself and never saw the program. Built and confirmed in the built text:
`proxyRestart() { sudo /run/current-system/sw/bin/systemctl restart "$1"; }`.
**Switch owed**, and only a call can settle it — `sudo -n -l` has now printed a
command back and meant nothing three items running. Item 41's rollback has fired
twice, correctly, and is the reason neither fault ever half-applied a selection.
Before that, after **the switch carrying items 39, 40 and 41 landed,
[item 41](./ledger/041-a-delegable-verb-that-ends-in-root.md)'s rollback fired
for real, and the reason it had to fire is
[item 43](./ledger/043-a-grant-that-was-present-and-inert.md): the grant was
present and inert.** With the ticket deliberately cold, `capsule b policy sealed`
answered `sudo: a password is required` and then `capsule: capsule-proxy-b would
not restart, so the selection was undone.` — link back, no document, the refusal
true rather than nearly true, which is item 41's whole claim proven on a host and
the first time that branch has been taken deliberately. The `NOPASSWD` rule it
was supposed to have was in the rendered sudoers, matched the command, and was
listed back by `sudo -n -l`; a `%wheel ALL=(ALL:ALL) ALL` one line below it took
every match, because **sudoers is last-match-wins and a plain definition lands at
priority 1000, where module merge order decides**. The module's rule is
`lib.mkAfter` now, and a third assertion reads the *rendered*
`security.sudo.configFile` and throws on any later untagged line covering the
owner — vacuous in `hostModuleUnits`' standalone eval and firing at the switch,
because the shadowing line belongs to a config this repo does not own. Watched
red at `mkOrder 1600` and green at 1000. **Switch owed, and it has a `~/flakes`
half**: the blanket in `modules/nixos/security.nix` is redundant against nixpkgs'
own `%wheel ALL=(ALL:ALL) ALL` at `mkOrder 600`, and its only effect on this host
is to shadow every `NOPASSWD` rule another module contributes. Until both land,
the `policy` verb still prompts and still rolls back, so a narrowing needs a warm
ticket and every selection is verifiable by reading whether the document was
written. Before that, after **the switch landed and two slots came up with
working proxies for the first time, which finishes
[item 36](./ledger/036-a-policy-is-selected-not-named.md) and proves
[item 39](./ledger/039-a-bind-is-not-a-traversal.md)**. `a` on `build` answered
`HTTP/1.1 200 Connection established` in the same breath as `b` on `sealed`
answered `HTTP/1.1 403 Filtered`, through `capsule-proxy-a` and
`capsule-proxy-b` — **the units, not a probe's proxy**, which is the one thing
every egress figure before today was missing. `b` came back to `200` on `build`.
`capsule b collect` was refused by `mayCollect`, unreachable on a stopped slot
and never triggered before. The `policy` verb's restart branch ran six times
across both slots, and running it found
[item 41](./ledger/041-a-delegable-verb-that-ends-in-root.md): that branch is
`sudo systemctl restart capsule-proxy-<slot>`, this host permits no such rule,
and it worked today only on a ticket a `just up` left warm — so the verb item 36
built to be *delegable* ended in a privilege the assigner has not got, and a
failed restart left the record and link narrowed while the wire stayed wide.
**Fixed and asserted the same evening, and switched since**: the restart moved inside
the record's hook, whose failure is defined to leave nothing moved, so a proxy
that will not bounce puts the link back and writes no document; the module grants
exactly that one restart per declared slot; `policyCases` is 32 → 44 with the
branch and its failure both reachable from a sandbox, and `hostModuleUnits`
throws when a proxy unit has no rule naming its restart. **A rollback beats a
check** — authority is not authentication, and a ticket can expire between the
two. Before that, after **`capsule all status` was found to spend ten
seconds a row proving that this host is not the shape it is**
([item 40](./ledger/040-no-doors-is-not-the-other-shape.md), below):
`host/cli.nix`'s `door` decided which transport reaches a capsule by asking
whether any *other* slot's relay socket was open, and a module-path host with
everything stopped has none — so every row took the direct arm and paid a full
`ConnectTimeout` against an address that is not routable from here. It asks for
the tap now, which is that arm's actual precondition; a ten-slot status is
**0.375 s** against 10.06 s for one row before, with the output unchanged. The
refusal it should have taken instead had never once fired, which is the class
[HANDOVER](../HANDOVER.md) guessed would come next. **On the host since, with
item 41 in the same switch**: `capsule all status` for two slots is 0.55 s.
Before that, after **starting a slot for the first time since item 36
was switched found that its proxy unit has never once run**
([item 39](./ledger/039-a-bind-is-not-a-traversal.md), below): the allowlist each
proxy binds sat under `stateDir`, which the proxy's uid cannot traverse, so the
mount succeeded as root and the open failed as the unit — on every slot, under
every policy, since the switch. The link has its own directory now, `just build`
**throws** on any unit binding a path under a module-declared directory its user
cannot traverse, and the whole of it needs a `~/flakes` switch plus
`capsule b policy sealed` after it. Before that, after **the last claim item 36
does not make got an instrument, and building it found that the probe holding the
first one shares its whole fabric with production**
([item 38](./ledger/038-a-probe-that-became-a-borrower.md), below).
`probe/two-capsules.sh` has a stage 2b: two guests, one aggregator, `build` and
`sealed` at the same moment, and the swap that stops a broken capsule reading as
a refused one. **Run: 40/42, all fourteen green**, `200` against `403` for
`api.anthropic.com` and both swapping when the policies did — and **re-run 42/42**
once the two reds, which were the probe's own stale assertion, read the
construction instead. `probe-netns-egress` re-ran green on the new fabric as a
regression check. **Slot `b` has been on `sealed`** since, which is the first time
a *declared* slot has been — the record and the allowlist link, with the proxy
restart and the `mayCollect` refusal still owed because both want the slot up.
The finding underneath it is larger: `probe/netns-egress.sh` never borrowed
`cap-egress`, `eg-rt`, `10.100/16` or `10.101/30` — `capsules.nix` was written
*from that probe's map*, so the probe became a borrower by standing still, and
its cleanup trap deletes the live aggregator's uplink by name. The fabric is
`probe/harness.sh`'s now and `flake.nix`'s `probeFabric` **throws at eval** on
any string `capsules.nix` declares. Before that, the same day, after **a capsule's namespace teardown was found to
only unname, and the check that should have caught the fix was found not to
exist** ([item 37](./ledger/037-a-teardown-that-only-unnames.md), below). A
`systemctl restart` of one slot's namespace unit failed and left wreckage that
`systemctl stop` could not reach; both netns programs now roll back an aborted
`up` and delete their veth peer explicitly, **switched and instrumented** —
`probe/netns-restart.sh`, 33/33, and 30/3 against a deliberately pre-fix
program, which is also what withdrew this item's first reading of its own
evidence. The larger half is that
`hostModulePrograms` now builds every program the module's units name — nothing
ever had, so shellcheck had never run on `capsule-netns`,
`capsule-egress-ns` or `capsule-perimeter-guard`. Before that, the same day,
after **item 36 was switched onto this host and its one
owed claim was run: a selected policy reaches the wire**, `sudo
probe-netns-egress` 33/33 (below). One guest, two policies in sequence, the
answer changing and coming back. Two capsules on two policies *at once* is still
uninstrumented. It also cost one real bug in `vm-stop`, which reported a
module-path capsule as down while it ran
([item 20](./ledger/020-which-capsule-a-program-means.md)) — fixed, and **now
exercised**: `vm-stop b` against a running module-path slot refuses instantly and
names `capsule b stop`. The exercise cost a demonstration of the store-path trap
in the same breath, worth more than the refusal: the `vm-stop` on the devshell
`PATH` was a **store path predating the fix**, and it did not fail — it spent ten
seconds on `ssh: connect to host 10.99.0.2 port 22: Connection timed out` and
then reported `vm-stop: b is down` **about a capsule that was running**, which is
the exact failure the refusal exists to prevent. Both copies are called
`vm-stop`, and only the one built after the fix has it. Build it, or ask the
installed program.
Before that, the same day, after **the pool — `capsules.nix` declares `a`…`j`,
which is [Plan D](./plan-d-fleet.md) D2's declaration half** (below): built,
switched, and costing 3% of an eval and one page of PID 1 at rest — with the
guard reading `2 of 10 declared` and both running slots undisturbed. The run-time
half (`policy`) is still to come. Before that, the same day, after **the
exhibit's scope — a collect is narrowed to
the unit of work the capsule was assigned, which closes item 32's last open
invariant** (below). **Built, asserted, switched and run**: the same slot, guest
and commit that produced the 1886-entry exhibit now produce a **36-entry** one,
and both host-side refusals fired on the live pair
([probes](./probes.md#the-same-exhibit-scoped--what-the-prediction-was-worth)).
Before that, the same day, after **the sideband arc — a capsule's result has two
halves, and the second one now has a channel, a regeneration step, an extractor
and a way back in** ([items 32](./ledger/032-the-sideband-channel.md),
[33](./ledger/033-provision-is-a-sequence.md),
[34](./ledger/034-adopting-a-guest-authored-tree.md),
[35](./ledger/035-briefing-a-capsule-with-state.md); below). **All four have now
run against live capsules**, after a `~/flakes` switch put the programs that
built them on this host: the extractor on the 1886-entry / 18.6 MiB exhibit item
32 collected, the regeneration inside a provision and standalone, and the brief
moving 1884 files from slot `a` into slot `b` as step (2) of one — the first time
two capsules have been on one story
([probes](./probes.md#what-the-sideband-arc-costs-end-to-end)). The whole arc is
under five seconds of wall clock, and a second collect is 0.48 s. `just check`,
`just build` and `just units` are green, so shellcheck-at-build has seen every
render **that a flake output names** — which did not include the module's own
`ExecStart` programs until
[item 37](./ledger/037-a-teardown-that-only-unnames.md) — and
`hostModuleUnits` has forced the module's three new programs; 34's
logic is asserted against hand-built git objects by hand, and 35's guest half is
asserted **in the build** (`briefCases`, fourteen cases, watched failing on two
mutations). What no run has reached is any of the arc's *refusals* except the two
that happened to fire. Before that,
2026-08-13, after **the fragment vocabulary — built, in the image,
and carrying slot `a`'s first real assignment** (below: `a` is provisioned onto
doctrine's SL-254 slice at `caf7f2a21`, generation 4, warm baseline green in
83 s) — and before that the same day after **D1 + D5
built, switched and run on this host** —
which took one fix, because the eval check that was supposed to catch it could
not see the thing that was wrong (below) — and before that the same day after
Plan D §9 step 3 **deployed** — the rename to
slots, the `mem` drop and `defaultBranch`'s deletion, all three in one
guest-affecting change, now switched on this host with both slots created and
one cold build taken at the new ceiling, **which cost the recommendation that
asked for it** ([item 12](./ledger/012-no-resource-ceiling.md)) — and before
that the same day after §9 step 2's eval
settled where a class lives, and before that after the fleet's contracts were drafted
against a review of [Plan D](./plan-d-fleet.md) — design only, nothing else
built — and before that after secrets at start — which closes Plan C item 7 —
the `capsule` CLI, and the load figure before it, and before that 2026-08-12,
when the units ran at N=1 and `probe-netns-egress` re-ran 27/27 behind them —
and then after the one bug that stood between N=1 and N=2: a host program's
transport is an argument now
([item 20](./ledger/020-which-capsule-a-program-means.md)), and
`probe-two-capsules` re-ran 28/28 on it with one program set instead of two.
**Since then N=2 has run through the module path** — two capsules declared
([item 21](./ledger/021-declared-capsule-flake-attribute.md)), both provisioned,
injected and cold-baselined green, the unit's `ExecStop` green on both, and the
guard holding two namespaces. **And the load figure is taken**, which closes
step 6 and the last thing Plan C owed before its CLI work: two cold builds at
once cost 112 s and 121 s against a 109 ± 5% sequential control, with neither
capsule reaching its memory ceiling and neither ever reclaimed
([probes](./probes.md#two-cold-builds-at-once)). **And now the pressure half of
it too**, from a second concurrent pair that replicated the durations — so step
6 has nothing outstanding ([item 24](./ledger/024-set-u-not-login-shell.md)).

## Where it got to

- **A capsule was handed to another slot, and the sequence written down for it
  was the wrong one.** The c→d migration, and the first run of
  `capsule-provision --state <capsule>` — the composite's quarantine origin,
  against the host origin
  [item 47](./ledger/047-a-script-on-stdin-and-the-command-that-eats-it.md)
  delivered on `e`. Four commands, no root, no hand-rolling
  ([probes](./probes.md#a-capsule-handed-to-another-slot--what---state-capsule-costs)).

  **The recorded sequence was `setup` then `capsule d brief c`**, which is item
  47's window and would have refused: on a target whose refresh writes tracked
  files there is no *after* a provision, and the proof of that is `e`, still
  sitting at a refresh commit its own brief then refused. The composite puts the
  brief between the push and the refresh, which is the only moment both
  preconditions hold. `d`'s HEAD afterwards is the commit it was provisioned at,
  and `c`'s uncommitted `notes.md` arrived still uncommitted — a worktree edit
  travelling as a worktree edit, which is what `statePaths` is for.

  **What a scoped exhibit costs a human, stated once.** Two untracked paths in
  `c` — a `.doctrine/memory` item and `.doctrine/workflows/drive-slice.js` — sat
  outside `statePaths`, so neither half would have carried them; they were
  committed in `c` first. That is [item 32](./ledger/032-the-sideband-channel.md)
  working as declared and it is also the standing price of it: **the narrower the
  exhibit, the more there is that only a person notices.** `$HOME` is the other
  half and is not fixable at all — `/work/home` is per-volume and firecracker
  shares no filesystem.

  **It made [item 50](./ledger/050-a-quarantine-outlives-its-assignment.md)'s
  read cheap, and the read has since been taken** — on `e` rather than `c`, so
  the migration's own quarantine stays intact. Next bullet.

- **Two assignments to one slot, and the two halves of a result fail in opposite
  directions.** [Item 50](./ledger/050-a-quarantine-outlives-its-assignment.md)'s
  read, on slot `e`: collect, reprovision at a non-descendant, collect again,
  fetch again ([probes](./probes.md#two-assignments-one-quarantine)).

  **The code half is what the item predicted.** `+ 0ab546b6c...592168676 (forced
  update)`, and `git fsck` in the quarantine then reports the first assignment's
  commit `unreachable` — object alive, no name reaching it.

  **The state half is not, and the mistake is worth more than the finding.** The
  item read `+refs/capsule/state/*` in the refspec and concluded *overwrite*; the
  fetch was a **fast-forward**, because the guest parents each snapshot on its
  own `refs/capsule/state/<stage>`, which is on the volume and which a forced
  push to `work` does not touch. **A refspec's `+` is a permission, not an
  account of what happened** — the same class as
  [item 43](./ledger/043-a-grant-that-was-present-and-inert.md)'s `sudo -n -l`,
  which answers *some rule permits this* and never *which line won*.

  **So the chain crosses assignments, and its root is a commit this host wrote.**
  `527596740` at `+1000` is `capsule e provision --state-from-host`; the two
  collects above it are `+0000`, the guest's. Item 42 dropped `--from-host`'s ref
  either side of a delivery precisely so an accidental chain would not become an
  archive nobody decided to keep — and one exists anyway, on the volume, where no
  key in `host/quarantine.nix` reaches it. The timezone is a free authorship tell
  and the only one there is.

  **And the two ends of the channel disagree by construction.**
  `capsule <slot> fetch`'s refspec is `refs/capsule/*:refs/capsule/*`
  (`host/cli.nix:798`) — **unforced**, where every collect refspec is forced, and
  neither file mentions the other. The second fetch is therefore `! [rejected]`
  for code and a fast-forward for state, so `~/dev/doctrine` holds **one
  assignment's code beside another's state** under names that say otherwise. The
  verb exits 1 having half-succeeded, says nothing of its own, and the `fetch)`
  loop does not read that status — so `capsule all fetch` would carry on. That is
  [item 41](./ledger/041-a-delegable-verb-that-ends-in-root.md)'s shape: two
  things that must move together, and no definition of what a failure leaves.

  **Nothing was built.** Three things not to conflate now instead of two, and the
  new one — the state ref's lifetime is the *volume's* — is the only one that
  cannot be decided by naming a quarantine differently.

- **The read that gated volume verbs is taken, and it inverted what it was
  afraid of.** [Item 49](./ledger/049-who-owns-a-state-directory.md), so
  [Plan D §9](./plan-d-fleet.md#9-order-of-work) step 6 — D3 and D4, the volume
  verbs, one of which is currently a hand-typed `rm -rf` — is **ungated**.
  Nothing in microvm.nix reconciles state directories: the only walk of
  `/var/lib/microvms/*` is a read-only activation `echo`, and `microvms.target`
  wants only declared VMs, of which this host has none. So a directory of ours
  owes the units `current/bin/*`, `booted/` and its ownership and nothing else.

  **What is there instead is the mirror image**, and it is why the constraint
  outlived the read: `install-microvm-<name>` carries no `ConditionPathExists`
  unless `updateFlake` is set, so it runs on every rebuild and `ln -sTf`s
  `current` back to the declaration — a slot's chosen runner reverted and
  restarted silently, which is D7's failure arriving by activation. Upstream's
  `toplevel` marker does not cover it; only `~/flakes` declaring no
  `microvm.vms` does, and that line was a comment two repos away holding for an
  unrelated reason. It is an assertion in `capsule-perimeter` now — vacuous in
  `hostModuleUnits`' standalone eval, watched failing in a throwaway eval
  carrying both modules, switched. **Switched is not witnessed here**: an
  assertion that holds renders nothing.

- **A host-authored state half is in a capsule, and the third step of a provision
  had never finished.** [Item 47](./ledger/047-a-script-on-stdin-and-the-command-that-eats-it.md),
  and it closes [item 42](./ledger/042-a-state-half-no-capsule-has-held.md).
  A guest script pushed on stdin is the guest shell's stdin, so the target's own
  command read the rest of it and bash exited 0 with every check below skipped —
  silently, on every provision, for the life of `host/refresh.nix`.

  **It was found by a symptom nothing was looking at.** A capsule created ten
  minutes earlier and never entered refused its next push with `Working directory
  has unstaged changes`. Reading that backwards reached a program whose commit
  branch, whose failure branch and whose five messages were all unreachable —
  and whose own header names the resulting trap in the abstract while describing
  what the program did in practice.

  **Two fixes and a decision.** `</dev/null` on the target's command, at the one
  line this repo did not write, with the rule recorded beside `loginRun` where it
  belongs. `git diff HEAD` instead of `--porcelain` for the before/after pair,
  because a status line names a file and the question is what changed — the second
  defect, found by the case suite the first one needed and invisible while the
  first one was hiding it. And the brief moved inside the provision, because a
  refresh that writes tracked files leaves no moment afterwards when one can land.

  **Delivered in one command**, `capsule e provision 582300f14
  --state-from-host`, 5.204 s of which the state half is ≈0.65 s
  ([probes](./probes.md#the-delivery-and-what-a-provision-that-carries-its-own-state-costs)).
  Three first-ever fires in that session: the host `code-oid` precheck, the
  refresh's commit, and everything past the snapshot.

  **`refreshCases`, and the thing to copy from it.** Fourteen cases against
  command lines no target can be asked to supply, run **on stdin** the way a guest
  runs them — because a suite that invoked `bash <script>` would have passed
  against the broken text, which is item 38's vacuous pass in a new place. There
  is a control case beside the discriminating one so a suite failing everywhere
  cannot be read as this finding, and both halves of the fix were watched red
  separately.

- **The window in which a capsule can be briefed closes when its agent starts
  working.** [Item 45](./ledger/045-a-brief-is-an-origin-not-a-top-up.md).
  Item 42's case arrived for real — slot `c`, `SL-251`, two hours in and missing
  the state half — and the verb built for it refused, four times over and
  correctly each time. `code-oid` (host two commits ahead), the dirty-checkout
  rule ([item 35](./ledger/035-briefing-a-capsule-with-state.md)'s *never a
  person's file*), the overwrite that rule prevents, and whole-tree layout over
  `phases/`. The two escapable ones are not jointly escapable: committing the
  agent's edit moves the guest's HEAD onto a commit the host has not got.

  **A brief is an origin, not a top-up**, and the fix was a hand `tar` scoped to
  the three paths the guest did not have — additive, so no worktree that never
  existed was composed, and unbound, so nothing records which commit that state
  was the state of. Open: whether the answer is a `--only-absent` operation with
  the same validation, or a refusal that says *brief before you start*. The
  second is cleaner and the first is what the day wanted.

  **It is not evidence about `--from-host`.** The case was *hit*; nothing was
  *delivered*. The precheck was not run either — both HEADs were read by hand.

- **A state half no capsule has ever held, and the two decisions it was waiting
  on.** [Item 42](./ledger/042-a-state-half-no-capsule-has-held.md). Items 32–35
  built the sideband arc whole *in the direction it was built for* — one agent
  auditing another — and the other direction arrived first with no motion at all:
  a fresh capsule needs state that has never been inside a capsule, and every
  inbound motion here read from a quarantine, which only a collect makes.

  **The verb is an origin, not a program.** A brief already *is* the inbound
  direction, so what it lacked was somewhere other than a capsule to read from:
  `capsule-brief --from-host [--stage <name>] [--unit <token>]`, with everything
  downstream of *which commit and what code was it of* factored into one
  `briefDeliver` that both origins share — the thing being factored is a security
  control, which is `host/exhibit.nix`'s own reason for existing.

  **A quarantine is what a capsule sent back.** That is the reading the item
  refused to choose between, and choosing it means a host-authored tree has
  nowhere in `collect/` to be — so this keeps **no archive**. The snapshot's ref
  is dropped before *and* after the delivery (before, because a leftover from an
  interrupted run would become the next commit's parent, and an accidental chain
  is an archive nobody decided to keep), and the objects left in the human's
  repository are unreferenced. The alternative reading would have made
  `collect/` silently stop meaning one thing, with a name convention as the only
  thing between a host tree and slot `a`'s exhibit — the class items 37–44 are
  seven instances of. Choosing it also makes the hole item 42 found cheap to
  close: `briefCheckSpec` refuses a source that is not a declared slot.

  **The sweep is an argument with no default.** Item 32 takes
  untracked-but-not-ignored files unscoped because one agent in one capsule works
  on one thing — *a property of a capsule*, which does not travel with the
  program. `snapshotFor`'s text gains `all` or `declared` in argv, exactly as
  `stage` and `unit` already are, and `declared` takes **no sweep at all** rather
  than a narrower one, since `git add -f` over a declared directory already
  stages everything inside it. `dirty.diff` and the `dirty:` count are bounded by
  the same pathspec, being the same whole-repo read by another route.

  **Measured, and the counterfactual is the argument**
  ([probes](./probes.md#a-state-half-authored-on-this-host--the-origin-that-is-not-a-capsule)):
  doctrine's live checkout, `SL-251`, 30 entries and 554 KiB at `declared`
  against 34 at `all` — and three of the four extras were files a *different
  process* had written into the checkout seconds before. The figure the item
  actually asked for is that two runs on a checkout being worked in produced the
  **same tree**.

  **The item's own first suggestion is wrong.** "`GIT_DIR` at a quarantine,
  `--work-tree` at the checkout" breaks every read that precedes the temporary
  index: a quarantine's HEAD is unborn, so `git ls-files -o --exclude-standard`
  calls every tracked file untracked and the snapshot takes the whole checkout.
  One command to refute, and it is the trap `host/state-snapshot.nix` already
  orders itself around one level down.

  **Owed: a delivery, and it is guaranteed to be refused first.** `code-oid`
  stays a reading of HEAD rather than becoming a claim, so the price is
  sequencing — provision `c` at the commit this checkout is on, then brief. As
  things stand `c` is at `de32c856b` and the checkout is at `f49314de8`. Taking
  that refusal deliberately is worth more than avoiding it: it is a refusal
  nothing has ever triggered from this origin.

- **Two slots up, two policies, and the first `capsule-proxy-<slot>` ever to
  serve a capsule.** Closes item 36 and proves
  [item 39](./ledger/039-a-bind-is-not-a-traversal.md);
  [probes](./probes.md#what-the-units-own-perimeter-answered-the-first-time-one-ran)
  has the transcript. `a` on `build` → `200 Connection established`, `b` on
  `sealed` → `403 Filtered`, at the same moment, both *HTTP* answers from live
  tinyproxies rather than the ambiguous `deny` a dead proxy also produces. Then
  `b` on `build` → `200`, so the answer follows the policy on one slot as well as
  between two. **Every egress figure in this repo before today was taken through
  a probe's own proxy** — same construction, which is the argument
  `perimeter/` takes injected fragments to make, but an argument is not a run.

  Also run for the first time: `mayCollect`'s refusal (`capsule b collect` under
  `sealed`, which a stopped slot cannot reach because the transport's socket
  check precedes the policy parse), and the `policy` verb's proxy-restart branch,
  six times.

  **What it cost: [item 41](./ledger/041-a-delegable-verb-that-ends-in-root.md),
  open.** That restart branch is `sudo systemctl restart capsule-proxy-<slot>`.
  This host has no rule permitting it — `sudo -n -l` lists `nft list table inet
  capsule-forward` and `rtcwake`, nothing else — so the verb item 36 built for an
  *assigner* to use ends in a privilege an assigner does not have, and it ran
  today only because a `just up` minutes earlier had left a sudo ticket warm. The
  record and the link move under one lock; the wire is a third thing outside it.
  A failed restart is therefore **fail-open in the one direction that matters**:
  `build` → `sealed` leaves every reader saying `sealed` while the proxy still
  serves `build`. Recommended fix is two things — refuse before writing either
  half, and let the module grant exactly that one restart for the slots it
  declares — and explicitly not a path unit, which would make the perimeter react
  to the filesystem.

  Still not taken, and it is two commands: the **in-place** restoration on one
  slot, `sealed` and back with nothing moving but the proxy. `b`'s two answers
  span a stop and a start.

- **A fallback selected by absence, and the ten seconds a status row spent on
  it.** [Item 40](./ledger/040-no-doors-is-not-the-other-shape.md). `door` in
  `host/cli.nix` picks the way in to a capsule: its relay socket if it has one,
  otherwise straight at `net.guest`. Which of those is right depends on the
  shape this host is running, and it asked *whether any other capsule's socket is
  open* — a module-path host at rest has none, and neither does a host with no
  module on it, so the two are one answer. Every `capsule all status` row took
  the direct arm and spent the whole `ConnectTimeout` on packets that leave by
  the default route. **10.06 s a row; 0.375 s for ten after**, output unchanged.

  The predicate is `/sys/class/net/vm-capsule` now, which is not a better
  inference about the shape — it is the direct arm's own precondition, and a
  test of the precondition cannot be wrong about the case it was guessed from.
  Both live shapes keep their behaviour, including the devshell shape on a
  module-installed host, which is what rules out asking whether the module is
  *installed*.

  **The refusal it should have been taking had never fired.** `no relay socket
  for '<n>', and the module path owns this host` needed some *other* capsule to
  be up, so the ordinary case — nothing running — silently took the arm that
  says the module path does not own this host. That is the class
  [HANDOVER](../HANDOVER.md) had guessed would turn up next, one under items 37,
  38 and 39: **a refusal nothing has ever triggered**. Not case-covered, and it
  cannot be: both arms of `door` are host state, so the evidence is the timings
  ([probes](./probes.md#what-a-fleet-status-costs)) and the output being
  identical row for row.

- **A bind is mounted as root and opened as the unit's user, and no capsule proxy
  had ever started.** [Item 39](./ledger/039-a-bind-is-not-a-traversal.md).
  `capsule-proxy-<slot>` binds its allowlist with `BindReadOnlyPaths`; the link
  was at `stateDir/slot/<name>/allowlist` and `stateDir` is `0750 owner:users`,
  while the proxy runs as `capsule-proxy` — in neither. systemd mounts as PID 1,
  so the unit starts; tinyproxy opens as itself and gets `filter file: Permission
  denied`, every three seconds, on every slot and under every policy.

  **The interesting half is why everything passed.** `policyCases` runs one uid
  and asserted the record and the link move together, which they do.
  `hostModuleUnits` read the `BindReadOnlyPaths` string, which was correct.
  `probe-netns-egress` and `probe-two-capsules` proved a selected policy reaches
  the wire — through the harness's own proxy, in the probe's namespace, **as the
  human**. And the switch materialised the links and was read as the module half
  landing. It did land. Nothing started it, because both slots were idle all day.
  So **a control can be switched and proven and still never have been started**,
  and the witness that existed was `capsule all status`'s unit column, which
  reports `auto-restart` and which nobody read while a slot was up.

  **Fixed by placement, not by permission.** The link is in its own
  `allowlistDir` (`/var/lib/capsule-allowlist`, `0755`), because widening
  `stateDir` to traverse-only would expose `collect/` — every quarantine, already
  `0755` inside it — and that is the one directory that must stay shut. Which
  makes item 36's own rule structural: the proxy has no *way* to the assignment
  record now, rather than no reason to read it. `stopKey` sits outside `stateDir`
  for the shorter version of the same reason.

  **Asserted at eval**, the third pairing of this kind: `hostModuleUnits` reads
  the module's own `d` tmpfiles rules and each unit's `User` and throws when a
  bound path is under a directory that user cannot traverse. A case suite runs as
  one uid and cannot discover a permission — the same gap the guard's
  `CAP_SYS_PTRACE` assertion fills, and the same answer as `probeFabric`'s
  `borrowed`. Watched going red on the pre-fix path: twenty findings, both
  offending prefixes for each of ten slots. `policyCases` gained the one
  assertion every other case in it would pass — that the link is *not* in the
  record's directory.

  **Owed: a `~/flakes` switch, then `capsule b policy sealed`.** tmpfiles' `L`
  creates the new link at each slot's *declared* policy and leaves an existing
  one alone, so `b` — whose record says `sealed` — needs the verb run once after
  the switch to make the two agree. A path move is the one event that can
  separate a record from its link, since it is the one thing neither the verb nor
  its lock is party to.

- **Two capsules on two policies at once has an instrument, and a probe was
  found to be the live fabric.** [Item 38](./ledger/038-a-probe-that-became-a-borrower.md).
  `probe/two-capsules.sh` grew a stage 2b: both capsules leave through one
  aggregator, one on `build` and one on `sealed`, and the host `build` admits is
  asked for by both guests at the same moment — allowed for one, refused for the
  other. Then **the swap**, which is what makes it evidence: stop both proxies,
  bring them back the other way round, and ask again, so each capsule has been
  allowed in one half and refused in the other and neither can be merely dead.
  Fourteen assertions, plus a check that each refusal is an *HTTP* refusal and
  that both proxies were still listening either side of each pair. **Run: 40/42,
  all fourteen green** — `api.anthropic.com` answered `HTTP/1.1 200 Connection
  established` for the capsule on `build` and `HTTP/1.1 403 Filtered` for the one
  on `sealed`, at the same moment, and the two answers swapped when the policies
  did ([probes](./probes.md#run-3--two-capsules-two-policies-at-the-same-moment)),
  then **42/42 on run 4** with the two reds fixed
  ([probes](./probes.md#run-4--the-fix-run)).
  That closes [item 36](./ledger/036-a-policy-is-selected-not-named.md) bar one
  thing, now half-done: **slot `b` is on `sealed`**, which is the first time a
  declared slot has been. `capsule b policy sealed` re-pointed
  `slot/b/allowlist` at `egress-none.txt` and wrote the record at generation 4,
  under the one `flock`, link first; `capsule all status` reads `sealed` in `b`'s
  policy column and `build` in the other nine. What that run could **not** reach
  is everything downstream of the slot being *up*: the verb took the
  `is-active` false arm and printed that the proxy will render `sealed` when it
  starts, and `capsule b collect` refused on the **transport** rather than on
  `mayCollect` — the injected fragment's socket check sits ahead of the policy
  parse, so a slot with no door never gets as far as the policy that would have
  refused it. Both are one boot of `b` away, and `b` is left on `sealed` so they
  cost one. **Both have since run, on that boot** — the `mayCollect` refusal and
  the restart branch, above.

  **The two reds are a third instance of the same class, one level down.** The
  probe asserted a collect landed at `refs/capsule/<name>/<branch>`;
  `capsule-collect` has fetched into `refs/capsule/<name>/heads/<branch>` since
  [item 32](./ledger/032-the-sideband-channel.md) split the code half from the
  state half. The assertion has been wrong since that day and nothing noticed,
  because **nothing runs a probe** — item 37 found programs nothing *built*, this
  finds an assertion nothing *ran*. Fixed by injecting `quarantine.codeRefsOf`
  rather than spelling the convention twice, and **re-run: 42/42**
  ([probes](./probes.md#run-4--the-fix-run)).

  **And the fix costs the probes the host's DoT hop.** `~/flakes` stubs
  `DNSStubListenerExtra` on `10.101.0.1`, the live capsule-facing address, so a
  fabric at `10.111.0.1` falls back to `1.1.1.1` and says so. No assertion
  depends on it — an allowlist matches a name before anything resolves — but it
  is a host-config edit this created.

  **What building it found is the larger half.** A second probe needing an
  aggregator meant hoisting the first one's into `probe/harness.sh` — and the
  first one's *was the live one*. `cap-egress`, `eg-up`/`eg-rt`, `10.101.0.1/2`
  and the whole of `10.100.0.0/16` are `capsules.nix`'s, so `probe-netns-egress`
  refuses to start on this host naming a production namespace, and behind that
  refusal its cleanup trap runs `ip link del eg-rt` on the fleet's uplink. **The
  probe never borrowed anything**: it predates `host/netns.nix`, it verified the
  shape, and `capsules.nix` was then written from its map — that file's own
  header says so. It became a borrower by standing still while the declaration
  moved onto it, which is why the rule needed an enforcer and not a sentence: a
  comment accurate on the day it was written went false with no diff to notice.
  **A third instance settles that it is a class**: `probe/netns.sh`, whose links
  and namespaces really are its own, carves `10.100.<i>.{1,2}` per capsule and
  puts `10.101.0.1/30` and a `10.100.0.0/16` route in the **root** namespace. A
  name check — the obvious fix — passes it cleanly.

  The fabric is the harness's now — aggregator, a veth per capsule by index, NAT,
  resolver detection, both nft tables and the proxy verbs — on names and
  addressing from `flake.nix`'s `probeFabric`, beside which `borrowed` is its
  intersection with every namespace, link, address and network `capsules.nix`
  declares. Non-empty **throws at eval**, in either direction. Watched going red
  on six mutations, one field at a time; `netBase` is the one worth having, since
  it is caught through the *derived* `/16` and a base that moves relocates every
  per-index address at once. `probe-netns-egress` also joined `just build`, which
  had never named it — the same question as item 37's, one notch milder.

- **A namespace teardown that only unnamed, and a whole class of program
  nothing built.** [Item 37](./ledger/037-a-teardown-that-only-unnames.md).
  `capsule-netns`'s `down` deleted the namespace and left the veth peer in
  `cap-egress` to the kernel's reaper, so a fast restart hit `An interface with
  the same name exists in the target netns` — while the aggregator's own `down`,
  five lines up the same file, had always deleted the peer first and said why.
  The aborted `up` then stranded a peer in the *root* namespace and a half-built
  namespace that `systemctl stop` could not clear, because a unit that fails in
  `ExecStart` never runs `ExecStop`. Both programs now have one `undo_up` used
  as `down` and as `up`'s own `EXIT` rollback.

  **What it exposed matters more than what it broke.** `capsule-netns` and
  `capsule-egress-ns` are only ever an `ExecStart` — no flake output, not in
  `environment.systemPackages`, and `hostModuleUnits` deliberately forces an
  outPath without embedding it so that reading the module stays an eval. So
  shellcheck, which runs at build, had never run on either, nor on
  `capsule-perimeter-guard`. `hostModulePrograms` is the exact inversion, a
  second derivation off the same evaluation whose contents are every
  `serviceConfig` literal of every capsule unit — so building it builds them,
  and a program added to a unit tomorrow is checked without that line moving.
  Watched going red on an unused variable while `hostModuleUnits` stayed green,
  which is the demonstration that the gap was real.

  **Switched, and instrumented**: `probe/netns-restart.sh` drives the real
  `capsule-netns` through the seam it already had — every per-capsule value comes
  from its unit's `Environment=` — on addressing that is nobody's capsule. No VM,
  no tap, no guest, under a second. **33/33, and 30/3 against a deliberately
  pre-fix program** ([probes](./probes.md#what-netns-restartsh-established)).

  **The probe withdrew the reasoning the fix was first recorded under.** Six
  hand-run restarts at a 1 ms gap were taken as proof that `down` deletes the
  veth synchronously, on the grounds that no reaper is that fast. It usually is:
  the pre-fix program passes five up/down cycles at ~90 ms each. So the timing is
  a cost figure, not evidence — and the two claims that discriminate are the two
  the race has nothing to do with, an aborted `up` stranding a peer in the root
  namespace and a `down` clearing a peer no namespace accounts for. Both fail
  against the pre-fix program every time. The race is the least instrumentable
  part of this bug and the smallest part of it.

  Still owed: the same teardown driven by a **unit**. The probe runs the program,
  and systemd's ordering, `ExecStop` semantics and start limit are what turned
  this from a failed restart into a recovery.

- **A policy is selected from a declared set now, and it is built.**
  [Item 36](./ledger/036-a-policy-is-selected-not-named.md) is Plan D D2's
  run-time half and [item 25](./ledger/025-assignment-is-a-perimeter-verb.md)'s
  resolution: what a capsule may talk to stopped being named by the project that
  happens to be in it. `policies.nix` is the host's vocabulary — `build`, the
  allowlist this repo has always had, and `sealed`, an empty one with
  `mayCollect` false — and every slot declares an operator-chosen default plus
  the set an assigner may select within, both refused at eval when they disagree.

  **`perimeter/` lost a value rather than gaining one.** `CAPSULE_ALLOWLIST` is
  required with no fallback, since a proxy that picks an allowlist because none
  was named *is* the fleet-wide default being removed. The devshell path resolves
  it from `capsule-host --policy <name>`, refusing without one exactly as a
  program refuses without `--capsule`; the module path resolves it from a per-slot
  symlink that tmpfiles creates at the declared policy with `L`, so the operator's
  declaration is what an unassigned slot runs and an assigner's selection survives
  a boot. The proxy binds that symlink and the whole policy directory read-only
  and **never reads the assignment record** — the front end resolves, which is a
  front end's latitude and never a program's.

  **The ingestion limbs moved too.** `collectMaxPackBytes` and `mayCollect` are a
  policy's, and `capsule-collect --policy <name>` resolves both — refusing
  without one, and refusing a policy that does not permit collecting before it
  opens the door. A **name and not a byte count**: a caller selects from what
  this host declared rather than authoring a bound. The front end fills the flag
  from the slot's record, falling back to the operator's declaration, which is
  the same two steps tmpfiles takes for the allowlist link.

  **`capsule <slot> policy <name>` is the verb**, validated against that slot's
  declared set. It writes the record and re-points the link under one `flock` —
  link first, so the only failure either can have leaves both as they were — then
  restarts that slot's proxy, which is what a policy change costs a running
  capsule. There is a `policy` status column beside `unit`, showing what the slot
  resolves to rather than what its record happens to hold.

  **Checked by `policyCases`**, 28 of them: the front end's own text against
  three slots `capsules.nix` would itself refuse, watched going red on two
  mutations. What no case can say is that any of it reaches the wire —
  `probe/netns-egress.sh` has a two-policy round for that.

  **Switched, and the wire claim is made.** tmpfiles materialised the per-slot
  symlinks at each slot's declared policy, so `/var/lib/capsule/slot/{a,b}/allowlist`
  point at `build`'s file with nothing assigned, and `capsule all status` grew its
  `policy` column. Then `sudo probe-netns-egress` came back **33/33** — the
  perimeter's 27 plus stage 2b's six: one guest, one host, allowed under `build`,
  refused under `sealed`, allowed again once the policy was put back, through a
  real stop and start of the unit. Both directions because a denial after a
  restart is ambiguous, and the *count* is what says the round ran at all, since
  a skip lands at 27
  ([probes](./probes.md#run-3--a-selected-policy-reaches-the-wire)). **`sealed`
  has served something** for the first time. Still open, and named in the probe
  rather than implied: two capsules differing *at the same time*, which needs two
  guests and is `probe/two-capsules.sh`'s shape.

- **The pool is ten slots, declared and switched onto this host.**
  `capsules.nix` says `a`…`j`, which is [Plan D](./plan-d-fleet.md) D2's first
  half and what [item 30](./ledger/030-a-pool-audits-what-exists.md) was the
  precondition for: a slot that never came up is capacity that does not exist, so
  declaring eight more adds no way to deny the host. `just check`, `just build`
  and `just units` green, then switched — **the guard reads `2 of 10 declared`**
  and both running slots kept their VMM pids across it, so item 30's degradation
  read correctly at a size it had never been asked about.

  **Both costs are measured and neither is a cost**
  ([probes](./probes.md#what-ten-declared-slots-cost)). At eval, 3% — +3.0%
  thunks, +3.7% function calls, +1.7% heap — against a fixed cost that is 97% not
  about slots, with a `cpuTime` that came out *lower* at ten because wall clock
  cannot resolve it. At rest, **one page of PID 1** for the seventy-two unit
  instances the eight new slots added, and nothing else moved: three named
  namespaces before and after, no tap, no volume, no VMM.

  **The unit count was wrong before the switch, and it is the finding.** The
  prediction was five units per slot, read off `just units` — what the module
  *generates*. systemd loads **nine** per slot, six of them microvm.nix's own
  templates instantiated per declared instance and three of those inert under
  firecracker; unit *files* grew by three per slot, because a template is one
  file whatever its instance count. A count derived from this repo's declarations
  is not a count of what the host ends up with.

  **Declaring it found what `guardCases` had baked in.** Eleven cases asserted
  `N of 2 declared` against the live `capsules.nix`, so the suite pinned this
  host's fleet size while claiming to pin the guard — and widening the pool would
  have been an edit to eleven expected strings. They take a **fixture**
  declaration now, built by `capsules.instancesOf` so there is no second copy of
  the constructor, with everything else about the declaration still the real
  one. Same seam as the guard's `tools`, checked the same way: pointed back at
  the live declaration once to watch a case go red.

  **What is left of D2 is the run-time half** — `policy` as a field an assignment
  selects rather than a fleet-wide file. The record (D1) already carries the
  field as null.

- **The exhibit has a scope now, and it is declared rather than held in a pair of
  hands.** Item 32's own invariant — *a collect brings back the out-of-band state
  of the work the capsule was assigned, and none that is not* — failed by
  declaration for as long as `statePaths` was a path list, because the unit of
  work is run-time state and that file is a build-time literal. It is a
  **template** list now: `{unit}` is the one hole, the **assignment** fills it
  with an opaque token, and a template with a hole and no unit **refuses** rather
  than falling back to the unscoped list — [item 28](./ledger/028-a-slot-has-no-default.md)'s
  rule at the sharpest place there is one, since the unscoped list is the failure
  being fixed. `capsule-adopt` and `capsule-brief` are untouched and inherit the
  scope by construction, which is what narrowing at the one choke point was for.

  **Four things the build found**, all in
  [item 32](./ledger/032-the-sideband-channel.md). The **token bound admitted the
  thing it was named against**: `checkToken`'s comment has always said "no `..`"
  and `[A-Za-z0-9._-]+` matches it — harmless while a token landed at the end of a
  ref, a path escape the moment one lands mid-path, since
  `.doctrine/state/slice/..` is `.doctrine/state`. Fixed in `checkToken`, so its
  other three call sites get it free. The **refusal is in two places for two
  reasons** — the host's before the door opens, the guest's unreachable and kept,
  because the alternative to an unreachable refusal is a *reachable* substitution
  of the empty string, which is the unscoped collect wearing the scoped one's
  name. The **front end is what fills the hole**, because a program may not read
  host state ([item 20](./ledger/020-which-capsule-a-program-means.md)) and the
  record is front-end written ([item 29](./ledger/029-the-record-is-front-end-written.md)):
  `capsule-collect --unit` in argv, `capsule <slot> unit <token>` into a new
  record field, and an explicit flag wins over the record. And the **verb exists
  only where the policy has a hole**, on the same rule that drops `capsule-baseline`
  for a target with no baseline.

  **Two paths were deleted rather than narrowed.** `.doctrine/dispatch` and
  `.doctrine/state/dispatch` are gone from `statePaths`: dispatch is the mechanism
  capsules replaced, so those paths hold bookkeeping from before this repo
  existed. The measurement counted them as over-collection and they were worse —
  an older answer to the question the exhibit settles. Only the target could say
  so, which is the guinea-pig rule biting in the direction it is meant to.

  **Asserted at build time, then run.** `snapshotCases` is the third kind of
  check's third instance — 29 cases running the snapshot's own text against a
  sandbox checkout holding two units, which is the only way to reach this branch
  without driving a real unit of work in a checkout that holds several. It pins
  the scope, both refusals, that a unit with no state is a *skip*, that the
  generic halves stay unscoped, and the token bound including the two cases it
  used to admit; watched failing on two mutations — a path losing its hole, and
  the bound reverted.

  **And then the host, after a switch, against the tree it was written from.**
  The same slot, guest and commit that produced 1886 entries produce **36**, and
  511 KiB against 18.6 MiB — a 52× cut in entries, better than the ~40-entry
  prediction and for a reason worth having: the five missing are doctrine's
  title-slug alias for the unit, which the prediction reached by grepping for the
  string and a scoped collect cannot reach at all. *Paths that mention the unit*
  is a larger set than *paths under it*, and the smaller one is the right one.
  Three claims that could have gone the other way held: the **one surviving
  symlink is the load-bearing one** (`.doctrine/slice/254/phases ->
  ../../state/slice/254/phases` still resolves, because the other declared path is
  what its target lives under — narrowing either alone would have left a broken
  link and no error); the **chain is intact**, the scoped commit parented on the
  broad one, so the over-collection is an event in the provenance rather than a
  rewrite of it; and **both host-side refusals fired on the live pair** — `b` has
  no recorded unit, so `capsule b collect` refused and named both remedies, and
  `--unit ..` refused on the bound. `capsule a adopt` then laid all 36 out, 46
  filesystem entries, no broken link
  ([probes](./probes.md#the-same-exhibit-scoped--what-the-prediction-was-worth)).

  One thing came along because widening the CLI's argument list ran into it:
  `programVerbs` is built in [host/programs.nix](../host/programs.nix) now rather
  than at each of `host/cli.nix`'s two call sites. That is the same duplication
  that cost a host rebuild when `observe` was added to one of them, and the same
  fix.

- **A capsule's result has two halves, and the second one is built end to end.**
  `capsule-collect` brought back `refs/heads/*` and nothing else, which reports a
  nine-phase run as one sha: doctrine's runtime tier is gitignored *on purpose*
  and is also what an audit reads, and whatever the agent left uncommitted exists
  nowhere else at all. Three items, one arc, and each one is the next step of the
  one before.

  **The channel** ([item 32](./ledger/032-the-sideband-channel.md), **run once
  against live slot `a`**): a second, non-branch history in the guest's own object
  store at `refs/capsule/state/<stage>`, built through a *temporary* index so the
  agent's real index never learns the paths, with `code-oid` in the commit message
  binding the state to the commit it was the state *of*. `capsule-collect` grows a
  second refspec and takes both halves in one `--atomic` fetch, so nobody observes
  a result commit without the state that goes with it. The refspec stays
  host-authored: the guest chooses what is in its refs and never where they land.
  First run, with the guest still working: 18.6 MB, 1886 files, both refs in one
  transaction, nothing stopped.

  **The regeneration** ([item 33](./ledger/033-provision-is-a-sequence.md),
  built, unevaluated): dropping `.doctrine/state/boot.md` from `statePaths` on the
  rule *state a consumer regenerates per checkout does not travel* leaves a
  positive half nothing implemented. `target.nix` grows `refresh`
  (`doctrine boot`), run by `capsule-provision` after the push and separately as
  `capsule-refresh`. A provision is a three-step sequence — push, materialise the
  state half, regenerate what neither may carry — and this is step (3), landing
  alone and useful on every ordinary provision.

  **The way back in** ([item 35](./ledger/035-briefing-a-capsule-with-state.md),
  built; **guest half asserted at build time**, unrun against two capsules):
  `capsule-brief <source>[:<stage>]`, and `capsule-provision --state` as step (2)
  of a provision — one capsule's collected state into another's checkout, which is
  the case item 32 built the whole thing for and the one motion it did not have.
  Two decisions in it. **The host validates and the guest only lays out**, which
  was item 34's open question: the guest is the confined side, so a control that
  runs there is one the confined thing is in a position to not run — and that is
  what turned item 34's check into `host/exhibit.nix`, one construction spliced
  into both programs rather than the copy a security control must never be. And
  **`code-oid` stops being a note**: nothing had ever read it, and this reads it as
  a refusal, because `git add -f -- <dir>` stages *worktree* content, so a state
  tree is only ever the state of one commit and laying it over another composes a
  worktree that never existed anywhere. No override. Two smaller things fall out:
  `.capsule/` is dropped at layout, since `dirty.diff` on disk is untracked content
  the *next* collect carries again as though this agent wrote it; and a brief may
  replace the code's version of a file and never a person's, so it refuses a
  checkout with uncommitted tracked changes.

  **The extractor** ([item 34](./ledger/034-adopting-a-guest-authored-tree.md),
  built; **shell asserted against hand-built git objects**, and now **run against
  the real exhibit**):
  `capsule-adopt <dir>` validates a guest-authored tree and lays it out with
  `read-tree`/`checkout-index` rather than `archive | tar -x`. The finding is what
  the checks turned out to be. Item 32 predicted "modes and prefixes"; the path
  class was **already refused twice** — `transfer.fsckObjects=true` at collect
  errors on `hasDotdot`/`hasDotgit`, and `read-tree` refuses `invalid path` again
  — while what nothing anywhere held was a **symlink target** (fsck passes
  `-> /etc/passwd`; a checkout writes it; the escape is the next thing that greps
  the exhibit) and a **gitlink** (silently an empty directory, which is evidence
  replaced by a plausible absence). `..` in a target is still not the test:
  doctrine's `.doctrine/slice/254/phases -> ../../state/slice/254/phases` is
  inside the root and load-bearing, so the rule is lexical resolution within the
  root. Measured: `git archive | tar -x` on the hostile tree plants both symlinks
  and the empty gitlink directory, exit 0, silent.

  **Run, on the tree it was written from.** `--list` and then a real layout into
  an empty directory, against slot `a`'s collected `implementation` state:
  1886 entries / 18.6 MiB out, 2171 filesystem entries and 23 MiB in, **253
  symlinks and no broken link** — the first evidence that resolution-within-the-
  root admits the trees it has to admit, which a `..` ban would not have. No
  gitlink in it, so that class stays hand-asserted only. It ran on the *in-tree*
  copy pointed at the module path's quarantine (`CAPSULE_STATE=/var/lib/capsule`),
  because the host's installed copy predates item 35's `host/exhibit.nix` — which
  is the same staleness that blocks the rest of the arc, below.

  Two smaller things came out of it. `host/quarantine.nix` is one construction for
  where a quarantine lives and what its refs are called, now that two programs
  read it — it collapses two of the three copies of that convention and leaves the
  one `perimeter/` needs for its own reason. And **`capsule-adopt` is the first
  host program with no transport**: it reads a host-owned repository and writes a
  host-named directory, and a transport fragment refuses whenever there is no way
  in to the guest — which is the state a finished capsule's exhibit is adopted in.
  So `selectCapsule` (*which* capsule) is now injected separately from `transport`
  (*how to reach* one), and it is identical on both paths where `transport` is not.

- **A guest's tools compose now, and the amenities are what paid for it.**
  `fragments.nix` is the host's fragment vocabulary — `agents` (`claude`, `pi`,
  `rg`, `fd`, `tree`, `jq`, `bubblewrap`) and `dev-facilities` (`helix`, `tmux`,
  `btop`, `nushell`) — `extras` in `flake.nix` is one selection for the fleet,
  and `vm/capsule.nix` composes it onto the target's floor. So
  [contract-flavour.md](./contract-flavour.md)'s `compose(floor, extras)` is
  built, with the two owners in two files instead of one implicit list
  ([item 31](./ledger/031-the-fragment-vocabulary.md)).

  **A slot wanting tmux is what started it**, and the useful part is where the
  three obvious homes fail: `target.nix`'s `extraTools` says *doctrine* needs
  tmux, and `vm/capsule.nix`'s `systemPackages` is where `claude-code` already
  was — the split the contract calls the whole design, left implicit at exactly
  the place it matters. That line is absorbed rather than left beside the new
  one, which is the same one-construction rule the `observe` argument cost a
  rebuild to learn.

  **The agents come from `llm-agents` directly**, not from `~/flakes/pub`'s
  `unjailed`, because that attrset *is* `inherit (llm-agents.packages.…)
  claude-code pi` — same derivations, and going through `pub` would have added
  five lock entries for none of them. It supersedes
  [item 3](./ledger/003-claude-code-unfree.md): the `allowUnfreePredicate` and
  the `pkgs ? claude-code` guard are both gone, since the derivation is created
  in another eval.

  **Built, refreshed and worked in.** `just check`, `just build` and `just
  units` green; the refusal watched failing on a misspelt fragment name before
  it was kept; then the image built and `just refresh a` put it under the
  running slot. The cost is **+0.5 GiB of closure (11.9 → 12.4 GiB) and +100.9
  MiB of erofs**, and the risk that motivated measuring it — llm-agents dragging
  a second nixpkgs in — did not happen: its `claude-code` arrived as `2.1.224 →
  2.1.229` ([probes](./probes.md#figures)). `bwrap` runs in the guest, so
  unprivileged userns survives `lockKernelModules`; its empty-sandbox `execvp`
  error reads like a missing kernel feature and is not one
  ([item 31](./ledger/031-the-fragment-vocabulary.md)).
- **Plan D D1 and D5 are installed and have run** — the assignment record and the
  status columns, the pair Plan D calls cheapest-useful because a fleet has to be
  legible before it can be administered. Three new files and no second
  implementation of anything: [host/observe.nix](../host/observe.nix) is the
  observed half, [host/record.nix](../host/record.nix) the desired half, and
  `host/cli.nix` reads both onto one row. `just build` and `just units` green, the
  switch landed, and all three verbs exercised against the installed copy:
  `capsule a status` printed fourteen columns for one ssh per row, `capsule a
  purpose "hacking"` answered `generation 1`, and `capsule a record` read it
  back. The record's first real write is `/var/lib/capsule/slot/a/assignment.json`
  — before it, that directory did not exist, which is what an unassigned fleet
  looks like from the outside. A second `status` then read the write back as `gen
  1` / `purpose hacking`, which is the actual join between the two halves and the
  only part a single pass would have missed.

  ~~One column still reads `-` on `a`~~ — `collect` has run for `a` since, as the
  first exercise of the sideband channel (item 32), so `refs` counts real refs in
  a real quarantine and the column's first number and the quarantine's first use
  arrived together. The one directory under `/var/lib/capsule/collect` belonging
  to the old `capsule` is still dead weight. Every other column answered, `mem cur/peak` at the figure a
  built slot has held since its baseline
  ([probes](./probes.md#the-first-cold-build-at-a-6144-ceiling)).

  **What the first record shows is two kinds of absent, and both are deliberate.**
  `policy`, `extras`, `image` and `profile_snapshot` are written as null or `[]`,
  because a record should say for itself which half of the contract is built;
  `base` is not a key at all, because nothing has provisioned this slot *through
  the front end* since the record existed. So absent-as-null means the mechanism
  is unbuilt and absent-by-omission means nothing has happened yet — and the `gen`
  column reading `-` before that write is the same statement one level up.

  **The switch cost one fix, and the interesting half is that nothing here could
  have caught it.** `host/cli.nix` is imported at two call sites — `flake.nix`'s
  and the module's — and `observe` was added to one, so a host rebuild died on
  `function 'anonymous lambda' called without required argument 'observe'` after
  both `just build` and `just units` had passed. Two changes, one per cause:
  - `observe` is built in [host/programs.nix](../host/programs.nix) now and
    exported, so neither caller constructs it and neither can omit it. That file
    is where it belongs rather than merely where it is convenient: it already
    names two of observe's three guest paths, and `baselineRecord` was already
    exported *for this reader specifically*. The header there admits the widened
    scope — everything the human runs at a capsule, plus the one script a capsule
    runs about itself.
  - `hostModuleUnits` forces `environment.systemPackages` as well as the unit
    graph. It read assertions, unit names and `serviceConfig` strings, and a
    module's *programs* appear in none of those — so any missing argument on the
    module's copy of any program was invisible to it, which is the whole class
    this derivation exists to catch. `builtins.seq` on each outPath, names into
    the output and paths never: embedding a store path would make `just units` a
    build instead of an eval. Its output has two sections now, `units:` and
    `programs:`, and five programs is the expected count.

  **D5 first, then D1**, inverting the plan's order for a reason that paid off:
  the guest round trip is what settles where `base.oid` comes from, and D1 is the
  half that is expensive to retrofit. The probe is pushed over the door on stdin
  rather than baked into the guest closure — `host/baseline.nix`'s own runner set
  that precedent and gave the two reasons (host-side policy about a measurement,
  and a volume outlives any program), and it means a status column can change
  without `microvm -u` per slot. It leaves nothing on the volume at all, unlike
  baseline's, because a question should not.

  Six observed columns — `head`, `dirty`, `baseline`, `age`, `disk`, `mem
  cur/peak` — for **one** ssh per row rather than one per column: the probe's own
  reply is the reachability proof, so `answers` stopped costing a round trip of
  its own. A dead guest is still a row of `-` and never a hang. Two of them are
  worth naming: `age` is arithmetic on **one** clock, because a baseline stamp is
  minted host-side precisely so both ends agree on a run's name, so the
  guest-is-UTC-and-this-host-is-AEST trap has no way in; and `mem cur/peak` earns
  its place from the 6144 finding, since nothing hands memory back until a stop
  and peak is how a human picks which idle slot to reap.

  D1 is the record at `/var/lib/capsule/slot/<name>/assignment.json` —
  `flock`-guarded read-modify-write, generation bumped by the write and not by any
  caller, `schema` and the four absent fields appended after the caller's filter
  so neither can be forgotten or forged. Verified: twenty concurrent writers land
  on generation twenty with no lost update and no half-written document, and a
  `purpose` containing jq syntax or shell metacharacters is stored as data —
  values reach jq as `--arg`, never as filter text. Two verbs, `record` and
  `purpose`; the writer of `base` is `capsule <slot> provision`.

  What the contract left to the implementation was four questions of mechanism,
  and all four were answered from rules already here rather than from anything new
  ([item 29](./ledger/029-the-record-is-front-end-written.md)): `base.oid` is
  **measured** off the guest's HEAD rather than resolved a second time host-side;
  the **front end** writes the record and `capsule-provision` still does not, so
  calling the program directly bypasses it exactly as it bypasses every other
  thing a front end does; the record is **module-path only** and under `slot/`,
  which a reader may search for and a writer may not; and `generation` is written
  but not yet **checked**, because the field is the expensive half to retrofit and
  the check is an argument added to a verb once anything detached exists. No field
  moved, which is the artifact doing its job.
- **The capsules are slots now — `a` and `b` — and the change carries two others
  that wanted the same rebuild.** `sizes.mem` is 6144
  ([plan-d](./plan-d-fleet.md) §0), and `target.nix` has no branch field at all:
  the guest's branch is the constant `work`, spelled once as `workBranch` in
  `flake.nix` and threaded to its two consumers, which closes L13 by subtraction
  ([contract-target.md](./contract-target.md)). **Deployed, and both slots have
  run.** The old capsules were stopped, `~/flakes` switched, `a` and `b` created
  from this checkout, and both started — which is also the first run of
  secrets-at-start ([item 22](./ledger/022-secrets-at-start.md): two payloads
  pushed into each fresh volume, `env` skipped as `optional` on this host, and
  the write-if-absent messages read as pushes rather than skips because the
  volumes were new) and of `capsule-baseline`'s login-shell fix
  ([item 24](./ledger/024-set-u-not-login-shell.md)). `a` then took a cold
  baseline: **110 s to green**, against 109 / 115 / 104 sequential at the old
  ceiling.

  **And the ceiling's own measurement went against Plan D §0.** The cut was
  supposed to be what makes four hot slots fit, and it changes nothing about
  what a slot costs: a built slot holds ~6.1 GiB of `anon` at *both* ceilings
  (6141 of 8192, 6095 of 6144), because the VMM holds every page the build ever
  touched rather than a share of what the guest was offered. So four hot slots
  cost ~30 GiB either way, the cut is free rather than a saving — no wall clock,
  no guest pressure, 3.4 GiB free inside the guest — and the only thing that
  returns memory is still a stop
  ([probes](./probes.md#the-first-cold-build-at-a-6144-ceiling),
  [item 12](./ledger/012-no-resource-ceiling.md)). Two traps came with it:
  `anon` at 99.2% of a ceiling can be coincidence, and all-zero
  `memory.events` is not headroom when no `MemoryMax` is set. `just build` and
  `just units` are green, so nothing on the change is owed. The old state
  directories `/var/lib/microvms/capsule{,-b}` are dead weight now.

  What the rename cost beyond `capsules.nix` is the interesting half, and it is
  [item 28](./ledger/028-a-slot-has-no-default.md): **`capsules.default` is
  deleted**. A default was defensible while the one capsule was called `capsule`
  and becomes a verb acting on a slot nobody chose the moment a name carries no
  meaning. So the four programs take `--capsule`/`CAPSULE_NAME` and refuse
  without one; the `capsule` front end resolves an unnamed verb to *the slot that
  is up*, refusing when none or several are — a host-state answer, which is a
  front end's latitude and never a program's
  ([item 20](./ledger/020-which-capsule-a-program-means.md)); and the justfile's
  fifteen literal `capsule` strings are gone, the delegating recipes passing no
  name and the lifecycle ones (`up`, `refresh`, `load`, `proxy-log`,
  `reset-known-hosts`) requiring one. `vm`/`vm-stop` lost their defaults with
  them, and `vm-stop` now asks *any* declared slot's guest to halt rather than
  the one literally named `capsule` — which had quietly become a power cut for
  every other name.

  One thing had to come back under a different noun: `.#capsule` is the guest
  **image**, declared beside the slots, because a runner is `microvm@capsule` in
  the process table and every probe both builds that attribute and matches that
  string. A side effect worth having: a probe's namespace is `cap-capsule`, which
  is no slot's, so `probe-freshness` can no longer land on a declared slot's
  socket.
- **Plan D §9 step 2 is done: `mem` is runner-only, and `vcpu` is not.** Two
  `toplevel.drvPath`s, with and without a forced `microvm.mem`, came back
  **identical** — so capsules at 6144 and 8192 share one erofs, the mem drop is
  free of the image, and a class varying `mem` costs ~1 KB. The claim it was
  asked to support does not survive intact, though: `vcpu` reaches the closure
  through `target.nix`'s cargo `jobs`, so per-slot vCPU is a 3.0 GiB image and a
  `microvm -u` per slot. **The eval could not have found that** — it forces the
  option, and the guest config reads the `specialArgs` value, so it returns
  identical paths for a coupling that is real; a grep over every consumer is
  what found it ([item 27](./ledger/027-a-class-is-not-always-a-kilobyte.md)).
  The coupling is the guinea-pig capability working, so the correction is to the
  cost model and not to the derivation, and the plan's "classes cost a kilobyte"
  is now a predicate over a *(class, profile)* pair.
- **The fleet's contracts are drafted, and nothing is built against them yet.**
  [contract-assignment.md](./contract-assignment.md) and
  [contract-flavour.md](./contract-flavour.md) are new, and
  [contract-target.md](./contract-target.md) has an ownership column over its
  existing fields. The point of doing this before
  [Plan D](./plan-d-fleet.md) D1 is one assumption: `target.nix` fuses a
  project's semantics with the host's perimeter policy, which is invisible while
  a target is a build-time literal and becomes an authority hole the moment
  assigning a project is a run-time verb
  ([item 25](./ledger/025-assignment-is-a-perimeter-verb.md)). A persistent
  record written first is where that would have survived. Three other things
  came out of the same review and are amendments to Plan D rather than new work:
  a flavour's tools need not come from the repo being confined; a profile is
  pinned per assignment generation while a policy is live; and `defaultBranch`
  is deleted rather than given the run-time override it lacks.

  **Two of those are now decided rather than open**, after a second review
  round. `defaultBranch` is **deleted outright** — the guest's branch becomes
  the constant `work` and no contract has a field for it. An interim draft kept
  an optional `workBranch` on the profile and two slices of one project refuted
  it: a name that identifies the work is not project state, and collect already
  lands everything as `refs/capsule/<slot>/*`. It has only two consumers (the
  guest's seed, and `capsule-provision`'s symref check and push refspec);
  `capsule-collect` fetches `+refs/heads/*` and never read it, which both this
  file's plan and the contract had wrong. And a flavour is **composed, not
  selected**: a project declares a tool *floor*, an assignment adds *extras*
  from a host-declared vocabulary, the image is what those compose to and is
  identified by its store path — so an unbuilt composition is a build, and
  whether `assign` waits or refuses is a per-host declaration.

  **Three things the second round added.** *Pinning needs retention, not just a
  digest*: the record keeps the profile's bytes and a gcroot keeps the image,
  because every reference here is a name that re-resolves — one rule applied
  three times, alongside `base.ref`/`base.oid`. *`path` is not project state*
  either; it becomes a host-held `profile → source` binding, and one an assigner
  may never spell, since `capsule-provision` reads that repo as the human. And
  *a project's flake is code that runs on the host*, upstream of the VM, so
  fragment sources are host-registered at a pinned revision
  ([item 26](./ledger/026-project-nix-runs-on-the-host.md)). Nothing is built;
  the branch deletion is guest-image-affecting and wants to ride an existing
  rebuild rather than earn one. Deliberately **not** drafted: an execution
  contract — doctrine has no requirements to give it yet and the likely shape is
  an outbox rather than a synchronous verb
  ([contract-doctrine.md](./contract-doctrine.md), Role 3).
- **Contention at N=2 is measured, and it is not io.** A second concurrent pair
  of cold builds — 113 s and 118 s, replicating 112 / 121 — stalled **0.033% of
  its wall clock on cpu and 0.002% on io**, with zero reclaim on either unit
  ([probes](./probes.md#pressure-under-two-concurrent-cold-builds)). io being
  the smaller by an order of magnitude reverses what Plan C's disk table had
  this repo expecting. The figure is an upper bound, because the window is each
  cgroup's life rather than the build — at 0.03% that is enough to settle it.
  Two things made it available at all, and both are the point: cpu/io `total=`
  is cumulative, so it survived the run being unsampled, and nothing had been
  stopped, so the cgroups still held it. `just load` now reads those totals at
  both ends and refuses when a pressure file is unreadable, since PSI off would
  otherwise report *no contention* where it means *no measurement*.
- **A `set -u` script must not be the login shell, and this one was.**
  `capsule-baseline`'s runner ran as `bash -l run.sh`, and NixOS's
  `/etc/bash_logout` opens by reading an unset guard variable — fatal under `set
  -u`, which **replaced the script's exit status with 1**. So every baseline
  since the last guest rebuild reported a red build while the build itself went
  green: `start` detaches before the login shell exits, so the volume's
  `history.tsv` was right and the terminal was wrong, which is the property
  [item 19](./ledger/019-baseline-build-and-figures.md) built the program
  around. Fixed in-tree by making the runner a child of the login shell rather
  than its script — one process, environment still inherited
  ([item 24](./ledger/024-set-u-not-login-shell.md)). **Shipped** on the rename's
  switch, since the module path runs the installed copy. Whether the host-side
  exit status is now green is not separately recorded — the cold build at 6144
  was read off `history.tsv`, which was always the truthful end.
- **doctrine's guest has nix-ld now, and its baseline has the sizing fix.**
  Cherry-picked off `second-target`, where they were found —
  [item 23](./ledger/023-second-target.md) came with them, so the citations in
  both files resolve here. Neither is target-shaped, which is the whole reason
  they belong on this branch too: every non-nix-native toolchain needs a
  `/lib64` loader and none of them supplies a different one, and one `du -sm`
  over several paths charges a hardlinked inode to whichever argument came first
  regardless of whose paths they are. cargo happens to show neither, so doctrine
  is where they are least likely to be exercised and most likely to rot. What
  did *not* come across is that branch's `status.md`: present tense is
  per-branch, and this branch's present is doctrine. **The guest changed**, so
  it wants a new image and `sudo microvm -u <name>` (`just refresh <name>`)
  before an existing capsule runs it.
- **A start now leaves a capsule you can work in, and it cost no mechanism.**
  Plan C item 7's last piece: `capsule <name> start` waits for the guest to
  answer and then pushes every payload `setup.nix` declares, so a `/work/.env`
  is no longer typed into each capsule by hand. The whole of it is a third
  declared payload — `$HOME/.config/capsule/<name>.env`, else `.../env`, to
  `/work/.env`, with `op inject` as the same interface and one line away — plus
  two changes around it: `optional`, so a host with no source for a payload
  skips it by name instead of failing, and a bounded wait in `start`, because a
  running VMM was the old promise and it left a capsule nobody can work in.
  Absence and emptiness became one fact in `capsule-inject` on the way past,
  which is one control flow per payload instead of two. Write-if-absent is what
  makes injecting at every start safe, and it is also the cost: a secret changed
  on this host does not reach a capsule that already has one without `capsule
  <name> inject env --force` ([item 22](./ledger/022-secrets-at-start.md)).
  **Run**, on the first start of each renamed slot: two payloads pushed into each
  fresh volume — `claude-credentials` 921 bytes, `claude-identity` 990 — and
  `env` skipped by name, which is `optional` doing its job on a host with no
  source for it. Worth reading carefully once: because both volumes were new,
  every payload reported as a push, and the *identical* byte counts across two
  slots are one host source produced twice rather than any shared state. No host
  directory can be mounted into a guest at all, so a shared `/work/home` is not
  a shape this can take.
- **There is a `capsule` CLI, and the justfile got smaller rather than larger.**
  `host/cli.nix` — `capsule [<name>] <verb> [args…]`, name first, omitted
  meaning `capsules.default`: `start`, `stop`, `created`, `ssh`, `admin`,
  `setup`, and the four programs by name. The split it draws is the one that
  matters: `microvm -c` resolves an instance name as a flake attribute, so
  **creating** a capsule needs this checkout and **running** one must not — the
  units are on the host and a human logged into it has no repo. `just up` keeps
  the create and the tap refusal; `_capsule` and `_guest-ssh` are deleted rather
  than wrapped, and the recipes that remain are one-line delegations. One store
  path, installed by both paths, because unlike the four programs it carries no
  transport ([item 20](./ledger/020-which-capsule-a-program-means.md)). It needs
  no host rebuild to be useful, since the devshell's copy picks the module's
  copy of each program; a rebuild only puts `capsule` itself on a host with no
  checkout. **Run: the door, `start` and `stop`.** The door proved itself
  against the load round's own ambiguity — `capsule <name> ssh 'tail -1
  /work/baseline/history.tsv'` returned 112 s from one capsule and 121 s from
  the other, the two rows that were indistinguishable by prompt
  ([probes](./probes.md#two-cold-builds-at-once)) — and `just down capsule-b &&
  just up capsule-b` went green through the delegations: the guest visibly
  unmounting, `Deactivated successfully` with no timeout, then the guard back at
  two namespaces. ~~**Unrun: `setup`**~~ — **run**, and every verb of the CLI has
  now been exercised: `capsule a setup edge` took the renamed slot from created
  to a green cold baseline in one command, which is also the whole of the 6144
  measurement's provenance
  ([probes](./probes.md#the-first-cold-build-at-a-6144-ceiling)). **In-tree since,
  unbuilt:** the ambiguity refusal now names the likely transposition, because
  `capsule ssh a` refused correctly and unhelpfully the first time two slots were
  up — name-first means `a` was read as a command for the guest, and the message
  never said so. It hints and does not reorder, for
  [item 28](./ledger/028-a-slot-has-no-default.md)'s reason.
- **`just status` can see every capsule now, and the way it does is the point.**
  `capsule all status` is a row per capsule — created, VM / proxy / relay unit
  state, door, whether the guest *answers*, refs collected — and a witness line
  for what no unprivileged reader can see. The namespace's own `ip_forward=0`
  and the three drops are `capsule-perimeter-guard`'s, audited every 10 s with
  egress bound to it, so the table names it rather than printing "unknown"; `ip
  netns exec` wants root and a status that needs root is a status nobody runs.
  `all` is a name rather than a flag, and it aggregates *questions* only —
  `branches` and `fetch` take it too, `start`/`stop`/`setup` refuse it, since a
  half-applied action across N capsules needs a policy nobody has decided
  ([item 20](./ledger/020-which-capsule-a-program-means.md)). Run against the
  live pair: both rows `running`/`running`/`running`, both guests answering, and
  it correctly reports **no** collected refs for `capsule-b` while finding
  `capsule`'s one ref in the devshell path's quarantine. `_quarantine` and
  `_guest-ssh` are gone with it, and `just proxy-log` was quietly broken — it
  looked for the pre-per-capsule log path.
- **The netns boot is verified.** `sudo probe-netns-boot`, 9/9 — firecracker
  comes up with its tap created inside a namespace, the guest boots and answers
  ssh in there, and the tap, the guest and its ssh port are all unreachable from
  the root namespace. ssh and git both cross a unix socket into it unprivileged,
  which also closed item 18's unmeasured `ProxyCommand`. It needed no host
  config: the boot was never systemd's question. **Nothing in the netns shape is
  unverified now** — see [probes.md](./probes.md).
- **The perimeter survives the move into a namespace.** `sudo
  probe-netns-egress`, 27/27 on the first run — the real capsule, the real
  `capsule-proxy` joined to its namespace, the guest getting a 200 for an
  allowlisted host and a 403 for one off the list, and getting nowhere at all by
  any other route even holding the default route guest root can add. The
  ip_forward control flips it both ways, and the two drops the earlier probes
  called for (the tap's input drop, the aggregator's interface-pair drop) are
  each verified by removing them and watching the wall fall over. **This was the
  last unverified claim in the netns shape.** It also found what the plan's unit
  inventory had left out, and that this host needs a `~/flakes` DNS edit before
  a capsule can resolve through its own chain — both in
  [probes.md](./probes.md).
- **The netns shape is wired, as units.** `host/netns.nix` is
  `probe-netns-egress` translated into systemd: the aggregating namespace, a
  namespace per capsule with `ip_forward=0` in it, a veth each, the three drops,
  host NAT and forwarding, and the resolver stub — which is a module option now
  rather than a `~/flakes` edit, so that half of NOTES item 7 comes home.
  `host/services.nix` generates the per-capsule units around it: the proxy
  joined to its namespace, the ssh relay on `/run/capsule/<name>/ssh.sock` as
  the human, and drop-ins on `microvm@<name>` and
  `microvm-tap-interfaces@<name>` that put both in the namespace and fix
  microvm.nix's `Restart=always`. The guard is rewritten around the namespaces
  and holds all of them at once. **Run at N=1 and N=2 on Sleipnir.** `just
  units` stays the eval-level check this repo can do without a host, and it grew
  a second job on the way: it refuses a newline in any `serviceConfig` value,
  because that is what a whole evening went to (step 5).
- **A host program takes its capsule as an argument, and two capsules have used
  it.** `--capsule <name>`, `CAPSULE_NAME`, or `capsules.default` — one store
  path for provision, collect, inject and baseline, serving every capsule,
  because the relay socket is derived from the name rather than baked. This was
  the one bug between the units at N=1 and N=2. **`sudo probe-two-capsules`
  re-ran 28/28** with one program set instead of two, reproducing run 1's
  figures inside a tenth of a second and strengthening the withdrawn-ceiling
  finding on the way past ([probes.md](./probes.md)).
  [item 20](./ledger/020-which-capsule-a-program-means.md) has the decision and
  the CLI shape that follows. **The module path's copies are run too now** —
  they are what provisioned, injected and baselined both capsules — and they
  refuse rather than time out when the devshell's shadow them on `PATH`. `just
  provision | inject | baseline | collect | setup <name>` picks the copy that
  can reach the capsule named.
- **A stop is a reboot, and that makes it clean.** The thing standing between
  N=1 and two capsules building at once was that `systemctl stop microvm@<name>`
  is a power cut on a mounted volume. It is not a missing signal, it is the
  wrong one: firecracker's only shutdown signal is an i8042 keystroke and this
  guest's driver refuses its stub (`error -22`), while a guest *reboot* unmounts
  and then resets — and `reboot=k` turns that reset into `Firecracker exiting
  successfully. exit_code=0`, measured, with nothing killing it. `host/halt.nix`
  is that request, one program for both paths, and the identity is a host-owned
  stop key rather than the human's: an `ExecStop` has no ssh agent, and the `+`
  prefix that would make it root would also drop it into the root namespace
  where the guest is unroutable
  ([item 11](./ledger/011-host-side-runs-as-you.md)). A capsule with no readable
  stop key now refuses to start. `vm-stop` lost its `SendCtrlAltDel` fallback in
  the same change, since it was inert. **Run on both paths now.** The unit's
  `ExecStop` went green on the second rebuild — `capsule-halt: reboot
  requested`, the guest visibly unmounting on the console, `Deactivated
  successfully`, no timeout, for both capsules. The first rebuild is what found
  that the drop-in carrying it had never parsed (step 5).
- **The serial console takes TUI input now**, which reverses a gotcha that has
  stood since the beginning: `boot.kernelModules = ["i8042" "atkbd"]` makes
  Enter work in claude on the console, A/B'd both ways. No input device appears
  and i8042 does not even probe, so the mechanism is unknown and the fix is
  recorded as an observation ([item 11](./ledger/011-host-side-runs-as-you.md)).
  ssh stays the documented way to run an agent.
- **The instances are declared.** `capsules.nix` — a value, and a short one:
  which capsules exist, each one's namespace, its way in
  (`/run/capsule/<name>/ssh.sock`) and its uplink /30 to the aggregator, plus
  the aggregator itself. The index is declared rather than positional and two
  capsules cannot share one; a name over 11 characters is refused, since it is
  on the wire twice and IFNAMSIZ is 15. `net.nix` is untouched and stays flat:
  under netns every capsule has the *same* tap, /30 and MAC, which is what one
  guest image means. Nothing consumes it yet beyond the socket path `flake.nix`
  was already spelling — the units in the next step are what it is for.
- **Probes grew a shared harness.** `probe/harness.sh` carries check / observe /
  measure / report *and* the whole capsule-in-a-namespace boot, because
  `netns-boot.sh` asserts and `freshness.sh` measures the same shape.
  `flake.nix`'s `probe` builder concatenates harness + script and injects
  `net.nix`/`target.nix` values as a quoted prelude.
- **Freshness has run twice, 22/22 both times.** Run 1 needed two corrections,
  both of them the harness measuring itself rather than the capsule; run 2 is
  clean and carries a valid teardown. 8.31 s to a usable fresh capsule, a cold
  boot indistinguishable from a warm one — the difference *changed sign* between
  runs, which is the strongest form that claim can take at n = 2 — one 12175 MiB
  image shared by every capsule, and ~296 MiB of volume per instance of which
  260 MiB is empty filesystem. All in [probes.md](./probes.md), the only copy.
- **Two capsules building at once is measured, and RAM is not what binds.**
  Fresh volumes, same commit both sides, so concurrency was the only variable:
  **112 s and 121 s** to green against 109 / 115 / 104 sequential — ~5% at the
  tail — with unit peaks of 7774 and 6801 MiB inside the declared 8192 and
  `memory.events` zero everywhere, so those are true high-water marks. The
  pair's own peak is a **bound**, [7774, 14575] MiB, because the slice that
  would have settled it had its peak set in an earlier session: a unit's cgroup
  is destroyed by a stop, a slice's is not. `just load` reads every peak at
  start as well as at end for that reason, and writes them beside the samples.
  Figures and the host's other load in
  [probes.md](./probes.md#two-cold-builds-at-once).
- **A capsule cannot say which capsule it is**, and this is where that stopped
  being theoretical: one image means every guest is `agent@capsule`, so the two
  `history.tsv` rows were indistinguishable by prompt and the differing
  durations were the evidence. The price is
  [item 21](./ledger/021-declared-capsule-flake-attribute.md)'s, knowingly paid.
  What was missing was a way to *ask*: `capsule <name> ssh <cmd>` and `capsule
  <name> admin <cmd>` pass a command through (`just ssh`/`just admin` delegate),
  and the door refuses instead of falling through to an unroutable `net.guest`
  when the named capsule has no relay socket but another capsule does — the
  timeout-that-reads-as-a-dead-guest the four programs were already taught to
  refuse ([item 20](./ledger/020-which-capsule-a-program-means.md)).
- **Two capsules run at once, 28/28, twice.** One runner store path, two
  namespaces, two volumes, two base commits; all four independences hold and the
  second capsule costs 0.18 s of boot. Figures in [probes.md](./probes.md).
- **It withdrew a number this repo had been quoting.** "16 GiB per capsule is
  what binds at N" was read off `target.nix`, never measured, and travelled as a
  finding into three documents and into that probe's own design. Measured: the
  declaration is a **ceiling**, not a charge — two booted capsules cost ~1.5 GiB
  between them. What binds at N is what capsules *touch*, which is unmeasured.
  Struck in place in [item 12](./ledger/012-no-resource-ceiling.md), because the
  way it spread is the more useful artefact.
- **A capsule is 4 vCPU / 8 GiB now**, down from 8/16 (`target.sizes`). Not a
  consequence of the correction — it is the interactive-capsule target, and the
  correction cuts the other way — but the ceiling is what a runaway build
  converges on, so it is the number that bounds one.
- **`capsule-inject` exists** — the non-git half of provisioning, host-initiated
  over the same ssh channel, as the human. `setup.nix` declares what leaves this
  host; the program knows no filename, format or key name. Two payloads: the
  token whole (`.credentials.json` is nothing else), and four keys of
  `.claude.json`'s ninety. **Run, and the agent starts signed in** — so four
  keys is enough and no capsule needs its own credential.
- **The capsule has static build config**, rendered from `target.sizes` into the
  closure and linked onto the volume by the seed (`target.nix`'s `guestConfig`).
  Until now it built with full debuginfo and an incremental cache — the untuned
  build every existing volume figure was taken against. **It cost one file and
  took `/work/doctrine` from 6.9 GiB to 1.1 GiB** for the same workload.
- **8 GiB is measured, not assumed.** Four scope runs at 4 vCPU / 8 GiB: an idle
  agent is 344 MiB and flat, a warm build peaks at 3980 MiB, the two together at
  4114, and a build from `cargo clean` at **4513 MiB** — with **zero pressure
  events** in all four, so those are true high-water marks. ~3 GiB of headroom
  stands. Figures and provenance in [probes.md](./probes.md); the sampling
  method is part of the finding, since the first run's numbers died with the
  terminal that printed them.
- **`capsule-baseline` exists and has run green, and the cold build is
  measured.** The third of the three setup problems (design.md), and the last
  step of making a capsule usable: it runs `target.nix`'s `baseline` — for
  doctrine `just web-build test` — in the guest's checkout under a login shell,
  detached, and writes its log plus one line of `/work/baseline/history.tsv`
  **on the volume as it goes**. The host attaches to watch and may leave;
  re-running attaches to the run in flight. Run 1 on a deleted volume: **109 s
  to green**, ~1.1 GiB of volume, and the record proves its own coldness — the
  caches totalled 123 MiB before and `.cargo` alone was 144 MiB after. Figures
  in [probes.md](./probes.md);
  [item 19](./ledger/019-baseline-build-and-figures.md).
- **Time-to-interactive is ~2 minutes, and ~93% of it is that one build.**
  8.31 s to provisioned, seconds of `capsule-inject`, then 109 s of baseline —
  from separate runs, so it is an order of magnitude rather than a stopwatch.
  Every other figure this repo has taken is noise beside it, which is worth
  knowing before optimising any of them.
- **Four of REQ-450's five axes are green; the fifth is not a row.** Checkout,
  repository and temporary state hold on a capsule nothing has used, and runtime
  now holds too. Process is deliberately unrowed: a capsule is a separate
  kernel, so no delta can falsify the reading, and a permanently green row is
  misleading evidence rather than extra assurance (doctrine DEC-189).
- **Disk is the limit, not CPU.** The volume dominates the image, nothing
  reclaims it (no discard), so the planning number is the 32 GiB cap and
  freshness is a disk policy.
  [Plan C](./plan-c-multi-capsule.md#disk-is-the-practical-limit) has the N
  table.
- **A real workload found a real limit.** `bun install` hung with no error and
  no log line: tinyproxy at `MaxClients 32` against bun's default concurrency of
  48, 32 connections queued on a listener nothing would accept. Now 128 /
  Timeout 300 (`49d2d2b`). General form in
  [item 9](./ledger/009-egress-allowlist-unproven.md) — a proxy turns any
  client's parallelism into a shared resource, and it fails as a hang, not a
  refusal.
- **`~/flakes` is switched**, not just edited: 9418 is out of the tap's firewall
  stanza and the `capsule-git` group is gone from the live system.

## Next, in order

The round just finished was *make one capsule usable interactively, then size it
honestly*. Each step was there because the next was meaningless without it.

**It is done.** The capsule boots at 4 vCPU / 8 GiB with `guestConfig` on
its volume and a signed-in agent in it, it is sized honestly, and one command
takes a fresh one to green and says what that cost. Next is Plan C:

1. ~~`sudo probe-netns-egress`~~ **done, 27/27** — see above. The shape it
   proved is what the next two steps assemble out of units, so they are
   bookkeeping against a known-good result rather than experiments on a live
   host.
2. ~~`capsules.nix`~~ **written** — see above.
3. ~~Host-module netns wiring at N=1~~ **run, and it holds.** All seven units
   active on the first start after the rebuild; `capsule-perimeter-guard`
   reports `1 capsule namespace(s) verified`. Verified by hand from inside the
   guest, which is the part that could not be argued from the probe:
   - no default route, and `curl --noproxy '*'` to a raw address exits 7
     (`COULDNT_CONNECT`) — the namespace's own `ip_forward=0`, with no host
     sysctl involved.
   - allowlisted host 200 through the proxy, non-allowlisted 403 from tinyproxy,
     immediately rather than as a timeout — so the resolver stub the probe had to
     fall back from works, and a denial is a denial rather than a name that would
     not resolve.
   - `capsule-provision` and `capsule-collect` both over the relay socket, at
     [full speed](./probes.md).
   The acceptance test then re-ran with the units stopped: **27/27 again**, and
   this time without the DNS fallback — the module's stub answers, so the
   capsule keeps the host's DoT chain and the probe says so
   ([probes.md](./probes.md)). Nothing the units did invalidated a claim the
   probe had made by hand. Two traps the first start cost, both now in
   [CLAUDE.md](../CLAUDE.md): `microvm -c … -f` takes no fragment, and a missing
   create fails as an unrelated dependency error.
4. ~~The transport is baked into a store path~~ **fixed, and run at N=2.** All
   four host programs now take `--capsule <name>` (else `CAPSULE_NAME`, else
   `capsules.default`) and derive the relay socket from it, so one store path
   serves every capsule and `host/programs.nix` still knows no transport. The
   seam widened rather than moved: `sshArgs`, a value, became `transport`, a
   shell fragment injected at the same call sites. `capsule-collect`'s
   positional quarantine name is gone — it was the capsule's name at every call
   site — so the asymmetry closed by deleting half of it. The CLI question Plan
   C item 7 wanted is decided in
   [item 20](./ledger/020-which-capsule-a-program-means.md), including what a
   `capsule <name> <verb>` front end is left to do. **`sudo probe-two-capsules`,
   28/28** — the acceptance test is the probe that exposed the bug, and it now
   runs one set of programs twice. What that run does *not* cover is the module
   path's copy of the same programs, which needs a host rebuild.
5. N=2 through the module. **Run, and it holds** — two capsules on one image
   through the units, both provisioned, injected and cold-baselined green (115 s
   and 104 s, two different base commits, [probes](./probes.md)); the unit's
   `ExecStop` green on both; the guard reporting two namespaces. What it cost is
   below and in [CLAUDE.md](../CLAUDE.md): the drop-in carrying the stop had
   never parsed. **What is left of this step is the load figure** — two cold
   baselines at once, on fresh volumes, against those three sequential runs as
   the control, with `just load` sampling the host. The first thing that sampler
   measured is already a finding: a capsule that has built once holds most of
   its ceiling until it is stopped, and the slice holding both peaked at 16305
   MiB ([probes](./probes.md)).

   The wiring, for the record: `capsule-b` is index 1 in `capsules.nix`, and
   every declared capsule is now an attribute of `nixosConfigurations` bound to
   *one* value, because `microvm -c <name>` resolves the instance's name as a
   flake attribute and the per-instance `mkVm` that would satisfy it is a second
   guest image ([item 21](./ledger/021-declared-capsule-flake-attribute.md)).
   The same rebuild carries one small fix: the ssh relay declares
   `SuccessExitStatus=143`, since socat exits on SIGTERM itself and left the
   unit `failed` after every ordinary stop.

   **It took two rebuilds, because the first one found that the `microvm@<name>`
   drop-in had never parsed**: the stop-key `ExecStartPre` was multi-line, which
   systemd reads as unbalanced quoting, so the namespace, the `ExecStop` and
   `Restart=no` behind it were dropped and both capsules crash-looped in the
   root namespace — while both proxies, both relays, both sockets and the guard
   all reported health. That is the whole reason it cost an evening, and it is
   why `just up` now asserts the VM stayed up and `hostModuleUnits` refuses a
   newline in any `serviceConfig` value. Also closed on the way past: item 20's
   unrun half — the module's copies of all four programs are what provisioned,
   injected and baselined both capsules.

6. ~~The load figure~~ **taken, on fresh volumes, and it holds**: 112 s and 121
   s for two concurrent cold builds against the three sequential runs as
   control, both units inside their ceiling with zero reclaim
   ([probes](./probes.md#two-cold-builds-at-once)). It cost one correction to
   its own instrument rather than to the capsules — a slice's `memory.peak`
   outlives the units in it, so the pair figure is a bound and `just load` now
   says which peaks it actually set. ~~No `.vm/load.tsv` was taken, so cpu and
   io pressure under concurrent load are still unmeasured.~~ **Measured, by a
   second pair the next morning**, and again without a sampler: the cumulative
   `total=` fields outlive the run as long as nothing is stopped, so 0.033% cpu
   and 0.002% io came out of the live cgroups afterwards
   ([probes](./probes.md#pressure-under-two-concurrent-cold-builds)). **This
   step is done.** What no run has yet is a time series — the totals say how
   much, never when.
7. **What is left of Plan C item 7** — two of three pieces done:
   - ~~the `capsule` CLI~~ **written and run** — see above and
     [item 20](./ledger/020-which-capsule-a-program-means.md).
   - ~~`status` and the aggregates~~ **written and run**, and the blindness is
     closed by naming the guard as the witness rather than by finding a way into a
     namespace.
   - ~~Per-capsule secret injection at start~~ **written and run**, on the first
     start of each renamed slot. The two shapes
     turned out to be one interface that already existed — a `produce` fragment in
     `setup.nix` — so what was built is a declaration, an `optional` field for a
     payload no host is required to have, and the wait that lets `start` push the
     list ([item 22](./ledger/022-secrets-at-start.md)). Two payloads landed in
     each fresh volume and the optional one skipped by name.

   **So item 7 is closed.** Next is Plan C's
   [order of work](./plan-c-multi-capsule.md#order-of-work) item 8 — a second
   target, if it is still wanted.

Then the rest of Plan C's
[order of work](./plan-c-multi-capsule.md#order-of-work).

### And then Plan D, whose first three steps are where this now is

[Plan D §9](./plan-d-fleet.md#9-order-of-work). Step 1 is done — `~/flakes`
overrides the input with `git+file:///home/david/dev/microvm-spike` on
`system-switch`, so declaring a slot is commit-then-switch and no longer a push.
Step 2 is done and narrower than it was asked to be (above). **Step 3 is
deployed**, and it was a sequence rather than a rebuild, because the two live
capsules were named after names that no longer exist:

1. ~~Stop both capsules **first**~~ — done, and it had to be: the units are
   generated per declared slot, so a host rebuild carrying the rename leaves two
   VMMs whose namespace, proxy and relay units have gone, and a stop needs the
   `ExecStop` that went with them.
2. ~~Host rebuild (`~/flakes`), then `sudo microvm -c a` / `-c b`~~ — done, from
   this checkout, since a slot is created by name against a flake attribute
   ([item 21](./ledger/021-declared-capsule-flake-attribute.md)). One trap on
   the way, and it is CLAUDE.md's `-f` gotcha from the other end: `sudo microvm
   -c a` with no `-f` defaults to the flake at `/etc/nixos`, which is not a git
   repo on this host, and it fails as a fetch error naming neither the missing
   flag nor the reason. `just up <name>` is the path that passes it.
   `/var/lib/microvms/capsule{,-b}` are now dead weight — recreate rather than
   migrate, [plan-d](./plan-d-fleet.md) §0's call, since a `mv` would want both
   gcroot symlinks re-pointed and the volumes are worth less than the care.
3. ~~A fresh `capsule a setup <ref>` and a per-unit `memory.peak` off that first
   cold build~~ — **taken, and it refutes what it was taken for** (above,
   [probes](./probes.md#the-first-cold-build-at-a-6144-ceiling)).
4. ~~`just build` and `just units`~~ — **green**, though they ran behind the
   deploy rather than ahead of it. The shipped shell had been rendered by hand
   and shellchecked, which is not the same as shellcheck running at build, so the
   ordering was luck rather than coverage.

**So step 3 is closed.** ~~Then **D1 + D5**~~ — **built against
[contract-assignment.md](./contract-assignment.md), switched, and run** (above).
§0's four-hot recommendation is rewritten, since a fleet plan that sizes slots by
ceiling was sizing them wrong.

Next: **D2, the pool. Its half of L12 is built, switched and run — L12 is closed**
([item 30](./ledger/030-a-pool-audits-what-exists.md)): the guard holds one
invariant with two limbs — every declared-and-present namespace passes its audit,
and every running capsule's VMM is inside its own declared namespace — so an
absent slot is skipped, a present-and-wrong one still refuses the whole host, and
the exclusion-list version is refused because it is persistent exception state
nothing clears. **Not a mode**: no boolean, no override, no second path.

  Witnessed on this host with `a`'s guest running and `cap-b`'s unit stopped: the
  guard started at `1 of 2`, went to `2 of 2` one audit cycle after
  `capsule-netns-b` started, and back to `1 of 2` when it stopped — `proxy-a`
  active throughout. The old guard refused at the first of those and took `a`'s
  egress with it, so that host state used to be unrecoverable without starting an
  unrelated slot first.

  **It cost one live refusal, and the class is new here**: the guard's
  `CapabilityBoundingSet` had no `CAP_SYS_PTRACE`, so `ip netns pids` returned a
  list with the `microvm`-owned VMM silently missing and limb two reported
  `microvm@a.service (pid …) is not in cap-a` — a correct check naming a cause
  that was not the cause. `hostModuleUnits` now refuses a guard without that
  capability, because nothing else paired a program's needs with its unit's
  permissions ([CLAUDE.md](../CLAUDE.md) has the A/B that proves this class:
  `systemd-run -p CapabilityBoundingSet=…` beside plain `sudo`).

  It came with **a third kind of check**, and that is the reusable part:
  `guardCases` (`just cases`) runs the real guard's text at build time with `ip`,
  `systemctl` and `sleep` stubbed — eleven cases, including the two that a weaker
  design passes, and the suite was watched failing before it was kept. What makes
  it possible is that `host/guard.nix` takes its `tools` as an argument, because
  `writeShellApplication` prepends `runtimeInputs` to `PATH` and no test can stub
  around that. Same seam as `transport`, so it is the pattern for any host-side
  program whose interesting branches a live host can only reach destructively
  (CLAUDE.md). The rest of D2 is to declare `a`…`j` once and make assignment
run-time state, which is what turns the record's three inert fields (`policy`,
`extras`, `image`) into ones something selects. It wants L12's degraded guard mode
in the same change: on the first start of *any* capsule the guard pulls in every
declared namespace, so one of ten that will not come up denies the whole host.

### And before either of those, the sideband arc has two things owed

It is in flight rather than finished, and one of the two is cheap.

1. ~~**`just build` and a host run for items 33 and 34.**~~ **Half done.** `just
   check`, `just build` and `just units` are green, so `alejandra` has run and
   `hostModuleUnits` has forced the module's copies of `capsule-refresh`,
   `capsule-adopt` and `capsule-brief` — which was the specific class that cost a
   host rebuild when `observe` was added to one of `host/cli.nix`'s two call
   sites. ~~What is left is **the host run**~~ — **all four steps have run, and
   items 33, 34 and 35 have each now met a capsule**
   ([probes](./probes.md#what-the-sideband-arc-costs-end-to-end)). `capsule a
   adopt --list` and a real adoption first, then `just provision b
   audit/SL-254` for `capsule-refresh` inside a provision (and `just refresh b`
   standalone, idempotent), then `capsule a collect` → `capsule a fetch` →
   `capsule b provision <oid> --state a`, which is the first time two capsules
   have been on one story. The whole arc costs **under five seconds of wall clock
   in total**, and a second collect is 0.48 s because the quarantine already
   holds the blobs.

   **It needed a `~/flakes` switch first, and the reason is worth keeping.** The
   block was not merely `capsule-brief` being absent from this host: item 35
   changed `host/git-channel.nix`, so the installed `capsule-provision` was a copy
   with no `--state` flag at all. Running the arc against it would have exercised
   the pre-35 program while reading as a green run — the trap a stale
   `capsule-collect` already cost this arc once. The adoption sidestepped it by
   running the in-tree copy at the module path's quarantine
   (`CAPSULE_STATE=/var/lib/capsule`), which only works because `capsule-adopt`
   has no transport; a provision cannot, because it goes through the relay.

   `a` is no longer driving SL-254, so the constraint that shaped this whole arc
   is off and both slots may be started, stopped and provisioned freely.
2. ~~**Scope the exhibit at collect**~~ — **built, switched and run** (above,
   [item 32](./ledger/032-the-sideband-channel.md)), exactly as the design had it,
   plus a bound that turned out to admit `..` and a duplicated argument list that
   turned out to be in the way. `just check`, `just build` and `just units` green;
   `snapshotCases` 29/29, watched failing on two mutations; and 36 entries against
   1886 on the live pair
   ([probes](./probes.md#the-same-exhibit-scoped--what-the-prediction-was-worth)).
   **So the sideband arc owes nothing.**

## Open, and nothing should claim these closed

- ~~**The `policy` verb ends in a privilege the assigner has not got**~~ —
  **fixed and asserted, switch owed**
  ([item 41](./ledger/041-a-delegable-verb-that-ends-in-root.md)). The restart is
  inside the record's hook now, so a proxy that will not bounce puts the link
  back and writes no document; the module grants that one restart per declared
  slot. **Nothing here can tell you it landed** — `policyCases` proves the logic
  and `hostModuleUnits` proves the rule is declared, and only a slot whose proxy
  actually restarts under a delegated user proves the rule *matches*. The
  sudoers path is the one thing in it that a test cannot check, because sudo
  resolves against `secure_path` at run time.
- **Which of build / run / start / trigger / *take* does the evidence cover?**
  Five findings in two days, each green everywhere it was looked at: item 37
  found programs nothing built, item 38 an assertion nothing ran, item 39 a unit
  nothing started, item 40 **a refusal nothing had ever triggered**, item 41 **a
  branch nothing had ever taken**. That last pair is the largest remaining seam —
  a branch can be built, evaluated, shellchecked and shipped while the condition
  selecting it has never once been true, and nothing here distinguishes that from
  a branch that works. Worse, item 41's *first* run passed on an accident of
  environment, which is what a first run is least likely to expose. The list of
  refusals and branches in that state is further down this section and it is
  long.
- **A namespace teardown is instrumented as a *program* and not as a *unit*.**
  `probe/netns-restart.sh` runs `capsule-netns` directly, 33/33
  ([item 37](./ledger/037-a-teardown-that-only-unnames.md)). What is outside it
  is systemd: ordering, the fact that a unit failing in `ExecStart` never runs
  `ExecStop`, and the start limit — two of which are what turned this bug from a
  failed restart into a recovery. That is a live-host claim and probably not a
  probe's shape.
- ~~**The flavour composition has never been in an image.**~~ Built, refreshed
  onto slot `a`, and a real workload has built on it — and it cost **+0.5 GiB of
  closure and +100.9 MiB of erofs**, with no second toolchain, since
  llm-agents' `claude-code` landed as a version bump
  ([probes](./probes.md#figures),
  [item 31](./ledger/031-the-fragment-vocabulary.md)). `bwrap` works in the
  guest, which was the one named doubt. What is *not* measured: whether an agent
  actually prefers any of it, which only the slice will say.
- **Extras are fleet-wide, so the record's `extras` and `image` are still
  inert** — and `"extras": []` in a live record now reads as a lie it is worth
  being able to answer: the *fleet* composes `agents` and `dev-facilities` at
  build time, and that field means *this assignment selected none*, because
  nothing selects yet. One list for every slot is what keeps one image;
  per-assignment selection, the store-path identity, the gcroot that retains it
  and the refusal to recompose under a dirty volume are all still Plan D D7.
- ~~**6144 has never run.**~~ Run, and it answered the opposite question to the
  one asked. The cut costs nothing (110 s to green, no guest pressure, 3.4 GiB
  free in the guest) **and saves nothing**: a built slot's `anon` is ~6.1 GiB at
  either ceiling, so a per-slot cost at 6144 is a per-slot cost at 8192 and
  [plan-d](./plan-d-fleet.md) §0's four-hot arithmetic does not follow from it
  ([probes](./probes.md#the-first-cold-build-at-a-6144-ceiling)). What replaces
  it is narrower and unmeasured: **how many hot slots actually fit**, which is
  now a question about ~7.5 GiB per built slot against this host's 60.4 GiB and
  whatever else runs on it, and **whether any ceiling low enough to cut the
  charge is low enough to squeeze the guest** — 6144 was not, and nothing says
  where that boundary is. §0's recommendation needs rewriting rather than
  re-running.
- **`generation` is written and never checked.** The refusal half — a command
  stating the generation it acts for, so a stale controller is told rather than
  obeyed — waits for D6. Nothing today can be stale, so nothing today notices the
  field is inert.
- **`capsule-provision` called directly still writes no record**, deliberately
  ([item 29](./ledger/029-the-record-is-front-end-written.md)). So a slot can be
  provisioned with no `base` pinned, and the only thing that says so is a missing
  key and a `-` in the `gen` column. ~~Slot `a` is in exactly that state now.~~
  No longer: `a` was provisioned through the front end onto doctrine's SL-254
  slice, so its record carries `base.ref = edge` and the measured
  `base.oid = caf7f2a21…` at generation 4. The hole is still there for the next
  slot provisioned by the program directly.
- **The two copies of the CLI are one store path by construction and nothing
  checks it.** `flake.nix` and `host/services.nix` both import `host/cli.nix`,
  and the claim that this is one derivation rather than two rests on the two
  argument sets being equal — which they were not, for `observe`, until a host
  rebuild said so. `hostModuleUnits` now forces the module's programs, so a
  *missing* argument is caught at eval; a **different** argument would still
  produce two silently identical-looking programs. **Narrowed by subtraction:**
  every argument that could differ now comes from one place — `programVerbs` was
  the last one built at both call sites and moved to
  [host/programs.nix](../host/programs.nix), so the two imports are the same
  `inherit` over the same values plus five ambient ones. Nothing checks that
  either; there is just less left to be wrong.
- **`microvm -c capsule` would create a capsule with no perimeter.** The guest
  image is a flake attribute beside the slots — it has to be, since probes build
  `.#capsule` and match `microvm@capsule` — and `microvm -c` resolves any
  attribute. That instance would have no namespace, proxy or relay unit, so it
  boots into the root namespace. `capsule` and `just up` refuse the name because
  it is not declared; nothing else guards it
  ([item 28](./ledger/028-a-slot-has-no-default.md)).

- ~~**Egress under netns is unproven.**~~ Proven, 27/27
  ([probes.md](./probes.md)). What replaces it is narrower: the same perimeter
  built out of systemd units rather than a probe's `ip`/`nft` calls, and DNS
  through the host's own chain — the probe had to fall back to a public
  resolver, so that half is unproven until `~/flakes` grows the stub address.
- **The byte/disk bound on collect.** `ulimit -f` bounds one packfile, not the
  transfer — many small objects or a delta bomb go past it. A quota or a
  dedicated filesystem for the quarantine is the host-shaped answer. The state
  half has its own ceiling in a different place and for a different reason
  (`stateMaxBytes`, checked *in the guest* before the commit, because the fetch is
  atomic and an over-budget state half must skip rather than take the code refs
  down with it) — and `capsule-adopt` adds none: it reports the byte count and
  lets a human decide, since the operator reading 18.6 MB is the control.
- ~~**The exhibit's scope is wrong, and only a pair of hands narrows it.**~~
  Built: `statePaths` is a template, the assignment fills the hole, and a hole
  with no unit refuses (above, [item 32](./ledger/032-the-sideband-channel.md)).
  ~~What replaces it is that no capsule has collected through it.~~ One has:
  36 entries against 1886 on the same slot, guest and commit, after a switch, with
  both host-side refusals fired on the live pair
  ([probes](./probes.md#the-same-exhibit-scoped--what-the-prediction-was-worth)).
  What replaces *that* is narrower and is one thing: the **`--unit` on a target
  with no hole** refusal is still build-time only, because every target on this
  host has one — it needs a second target, not a second run.
- ~~**`capsule-adopt` has never seen the real exhibit.**~~ It has: `--list` and a
  real layout, both green, 253 symlinks and no broken link
  ([probes](./probes.md#the-first-exhibit-adopted--and-what-it-costs-to-over-collect)).
  What replaces it is narrower — **the mode class is still hand-asserted only**,
  because no target carries a gitlink, so the one check nothing else anywhere
  holds has never been exercised by a tree a capsule wrote.
- ~~**Items 33 and 34 are unevaluated nix.**~~ ~~**None of items 33, 34 or 35 has
  run against a capsule.**~~ All three have, on the module path, after the switch
  ([probes](./probes.md#what-the-sideband-arc-costs-end-to-end)). What replaces
  them is one thing and it is narrower: **the arc has only ever run forwards.**
  Every refusal it met was one of the two that happened to fire (a
  non-fast-forward push, and the ambiguity of an over-collected tree); the
  `code-oid` mismatch, a dirty destination worktree and an over-budget state half
  have still never been reached by a real capsule.
- ~~**`capsule-brief` has never moved a real tree.**~~ It has: 1884 files, 18.6 MB,
  capsule `a`'s `implementation` state into `b`'s checkout as step (2) of a
  provision, over the relay socket. **What that run found is a gloss that does not
  fit its own target**: `b`'s worktree is clean afterwards and the program says
  `differs from its HEAD in 0 paths`, because every path doctrine declares is
  gitignored — so a brief carries the runtime tier and *not* the other agent's
  uncommitted tracked edits, which live only in the exhibit's `.capsule/dirty.diff`
  and are dropped at layout by design. Slot `a` was dirty in exactly that way
  (`M skills-lock.json`) and none of it reached `b`. The count is truthful and the
  sentence beside it describes a case doctrine does not produce. Cold and warm are
  both priced — 1.14 s for the three-step provision, 0.63 s for a repeat brief —
  and there is no colder case, since the `code-oid` refusal puts the destination
  at the state's own commit every time.
- **Whether an injected credential survives use.** The token rotates on refresh
  and the capsule holds a copy, not the shared file — so host and capsule drift,
  and how long a capsule's copy stays good is unknown. `capsule-inject --force`
  is the answer until it is measured. (The transport half of "non-git
  provisioning inputs" is closed: `capsule-inject` uses it.)
- **A rotated secret does not reach a running capsule either**, and for the same
  reason: every payload is write-if-absent, which is what makes injecting at
  every start a no-op rather than a clobber. Editing this host's `.env` changes
  nothing until `capsule <name> inject env --force`, which discards what the
  guest wrote into that file. Refreshing at start would do that discarding
  silently, N times, so it is not policy
  ([item 22](./ledger/022-secrets-at-start.md)).
- **Quarantine retention** (doctrine has DEC-193 proposed). Two pieces of stale
  state on this host are the near-term case for it: `/var/lib/capsule/collect/`
  holds a `faux.git` from before a capsule named its own quarantine, and
  `/var/lib/capsule/doctrine.git` is the served mirror
  [item 18](./ledger/018-git-channel-direction.md) deleted the *service* for.
  Both are out-of-band cleanups, not flake changes.
- **Nothing outside a capsule's namespace can independently confirm its
  `ip_forward=0`.** This is what is left of `just status`'s blindness after
  `capsule all status`: the guard is the only reader of the inside of a
  namespace, so if the guard is wrong it is wrong alone. It holds egress bound
  to itself, which is why that is acceptable rather than merely unavoidable.
- ~~**Throughput over the unix socket.**~~ Measured on the first real
  provision/collect pair: **93.7 MiB/s out, 117.9 MiB/s back**
  ([probes.md](./probes.md)), against the tap's ~100 MiB/s each way. The relay
  is not a bottleneck on bulk. What the same session did find is per-packet:
  `socat` sets no `TCP_NODELAY`, so interactive echo clumped until the unit
  gained `,nodelay` — and that fix is shipped but unmeasured.
- ~~**The cold build under freshness**~~ — measured, 109 s, one run
  ([probes.md](./probes.md)). What stays open is that the *freshness probe*
  still cannot take it: its namespace has no upstream, so the price and the 22
  assertions come from different runs and should not be quoted as one result.
- ~~**What N capsules cost under load.**~~ ~~**Pressure under concurrent load is
  unmeasured.**~~ Both measured at N=2 — wall clock and memory
  ([probes](./probes.md#two-cold-builds-at-once)), then cpu and io stall from a
  second pair ([probes](./probes.md#pressure-under-two-concurrent-cold-builds)).
  Three narrower things replace them. **Nothing has a time series**: the stall
  figures are cumulative totals over each cgroup's life, so they bound how much
  and say nothing about when, and `just load` has still never sampled a build.
  **N=2 is not N.** And the **ratchet** remains the term that decides how many
  fit: a capsule holds most of its ceiling until it is stopped — measured now as
  6141 MiB of `anon` held for a guest reporting 481 MiB used, because
  firecracker has no balloon and no free-page reporting — so those peaks are not
  additive across a working day.
- **Time-to-interactive is not 8.31 s.** "Usable" in [probes.md](./probes.md)
  means *provisioned* — that is the freshness probe's own definition. An
  interactive capsule is boot + provision + setup + a cold baseline build, and
  because `/work/home` is on the volume that freshness deletes, **setup is paid
  per fresh capsule**. `capsule-inject` being fast and idempotent is a
  requirement, not a nicety.
- ~~**A relay outliving its VM is fixed in-tree and unshipped.**~~ Shipped:
  `~/flakes` has relocked since, and this host's installed relay binds the tap
  unit as well as the namespace, while its `capsule-baseline` carries
  `ConnectTimeout`. So the hand-stop of `capsule-ssh-relay-*` is no longer
  needed here. The reasoning stands in
  [item 20](./ledger/020-which-capsule-a-program-means.md) — a socket is the
  identity, and a unit bound only to a namespace outlives its guest.
- ~~**`capsule-baseline`'s login-shell fix is in-tree and shipping.**~~ Shipped:
  the rename's `system-switch` carried it, along with secrets-at-start, both
  reaching this host by `git+file:` against committed HEAD rather than by a push.
  What is *not* separately recorded is a host-side green exit — the cold build at
  6144 was read off `history.tsv`, which was truthful either way, so the fix is
  shipped and unwitnessed ([item 24](./ledger/024-set-u-not-login-shell.md)). The
  next baseline is where it shows.
- **The corrected `capsule-baseline` sizing has never produced a record.** It
  was written against a diagnosis and verified by hand over ssh, and now it is
  on a branch whose target cannot exercise it: doctrine shares no inodes between
  `target/` and `.cargo`, so its split reconciles either way. The next
  panopticon baseline is the real check, and doctrine's next one only says the
  fix did no harm ([item 23](./ledger/023-second-target.md)).
- **The guest's clock is UTC and this host is AEST.** A guest file mtime read
  against a host clock is ten hours out, which is enough to make tonight's run
  look like last night's and cost real time. Baseline stamps are UTC by design
  (they are the host's, and named to need no quoting); it is `ls` in the guest
  that misleads.
- `vm --help` creates `.vm/--help/`. Every argument is a VM name. Papercut.
- ~~**A journal tail reports the wrong event when the request never reached
  systemd.**~~ Fixed in-tree, **unshipped** — `capsule` is a store path, so this
  one needs a host rebuild. `capsule <name> start` printed `did not stay up`
  followed by the *previous boot's* clean shutdown when `sudo` had no tty, which
  reads as a VMM that crashed on this start; `stop` had the same shape against an
  already-stopped unit, and its own comment called that tail "the evidence". Both
  now take an epoch before the request and scope the tail to it, through one
  `unitTail` rather than two careful call sites, and **an empty tail is printed as
  a finding** — a unit that logged nothing is a unit nothing happened to. `start`
  also keeps `systemctl`'s exit status instead of discarding it, so a start that
  never ran says so before the tail rather than after it. The `--since "@<epoch>"`
  scoping is verified both directions against a live unit; the two message
  branches need a stopped or failing unit and are unexercised.
- ~~**`just ssh` runs your command substitutions on this host.**~~ Fixed in-tree,
  unshipped-but-not-needing-a-rebuild (a justfile is not in the closure). It cost
  a wrong reading during the sideband arc's own host run: `just ssh b 'git -C
  /work/doctrine rev-parse --short HEAD'` answered with a host-side sha, which
  read as a capsule that had not been provisioned. `{{cmd}}` is text the recipe's
  shell parses, so `$(…)` runs here; `quote(cmd)` sends one word and lets the
  remote shell expand it. `capsule <name> ssh` was always right, because a program
  takes argv — the fix makes the two agree ([CLAUDE.md](../CLAUDE.md)).

## Do not re-derive these

All of them cost time already. The long forms are in
[ledger/index.md](./ledger/index.md), [CLAUDE.md](../CLAUDE.md) and Plan C's
[traps](./plan-c-implementation.md#traps-already-paid-for).

- the forward drop does not stop cross-capsule reach
- a per-instance kernel cmdline does not buy one guest image
- `StrictHostKeyChecking=accept-new` does not fix a *changed* host key
- a denial-only network test passes for the wrong reason; assert both directions
- a probe that borrows the production addressing tests production
- sudo strips `SSH_AUTH_SOCK`, and the guest's key is `~/.ssh/id`, which ssh
  does not try by default — a root-side ssh gets `Permission denied` while ping
  keeps working
- devshell programs are store paths: an edited program is stale on `PATH` until
  it is rebuilt, and it will look like your fix did nothing
- firecracker EPERM on the tap means *no tap* (it tried to create one), not a
  wrong owner; EBUSY means a VMM outlived its guest
