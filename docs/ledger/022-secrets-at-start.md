# NOTES item 22 — secrets at start, and a payload that may be absent

*State: built, unrun on this host.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Secrets at start, and a payload that may be absent.**
[Item 2](./002-agent-credentials.md) built the carrier and left the older path
uncarried: `export ANTHROPIC_API_KEY=…` in `/work/.env` still had to be typed
into every capsule over ssh, and at N that is a ritual per capsule. It needed no
new mechanism, which is the finding — `capsule-inject` already pushes *declared
payloads produced host-side*, and a `.env` is one. So the whole of it is a third
entry in `setup.nix` plus two changes to what surrounds it.

**The direction was never open.** `op` (1Password CLI) renders a template by
talking to a host unix socket, and firecracker has no shares, so a guest can
never reach it: the environment is rendered *here* and pushed. Both supported
shapes are therefore the same interface — a `produce` fragment — and which one
a host uses is a line in the declaration rather than a fork in the code. The
plain file is the shipped default because `op` is unfree and a host that does
not use one should not carry it in the program's closure; the `op` form is
written out in the entry's comment.

**`start` is where it goes, and that changed what a start promises.** A
running VMM was the old promise, and it left a capsule nobody can work in —
`$HOME` is on the volume freshness deletes, so credentials and secrets are
gone with it. So `capsule <name> start` waits for the guest to answer and then
injects the whole list, which is only safe because every payload is
write-if-absent: a restarted capsule keeps what it has, and a repeat is a
no-op rather than a second answer. The wait is bounded on wall clock rather
than on attempts, because a failing ssh costs anything from nothing to
`ConnectTimeout` and N tries is therefore not a duration. `setup` still
injects too: a guest started by hand, or one that rebooted, has had no start
of ours.

**A shared declaration needs a working absent path**, which is the one new
field: `optional = true` means a source that is not on this host is a skip
with a message rather than a failure. Without it the entry is a host-specific
file that every other host fails to start capsules over — the same rule as
`toolsPackage = null` (CLAUDE.md, limb 2). It also collapsed two cases into
one: absence and emptiness are the same fact, since a filter that matched
nothing and a file that is not there both mean there is no payload, and
pushing either replaces a working credential with nothing. `required` says
which of them is a failure, once, instead of every entry saying it and one of
them forgetting.

Not decided, and deliberately: **a rotated secret does not reach a running
capsule.** Write-if-absent means editing the host's `.env` changes nothing
until `capsule <name> inject env --force`, which discards whatever the guest
wrote into that file. Refreshing at every start is one word of policy and
would silently do that discarding N times, so it is left to the human, on the
same reasoning as the credential in [item 2](./002-agent-credentials.md).
