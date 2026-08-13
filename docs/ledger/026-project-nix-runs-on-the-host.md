# NOTES item 26 — a project's flake is code that runs on the host

*State: open — scoped in [contract-flavour.md](../contract-flavour.md), nothing
built.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**"A build input rather than a control" is true about the perimeter and not the
whole story.** [contract-target.md](../contract-target.md) states the asymmetry
that lets the tool set come from the confined side: the allowlist is a control
and the tool set is not, so only the second may be authored by the repo under
confinement. That argument is about what the *guest* may reach, and it holds.

What it does not cover is where the tool set is *produced*. A target's flake is
evaluated and built **on the host, as the host user, with whatever network
access its own inputs declare** — before any capsule exists, and outside every
control this repo builds. The confinement is the VM; nix evaluation is upstream
of the VM.

**On this host that is academic, and the reason is worth stating because it
expires.** The human already runs `nix develop` in the target repo daily; a
capsule evaluating the same flake adds nothing they had not already accepted.
The distinction becomes real the moment the person who *assigns* is not the
person who *owns the host* — a ranch, or doctrine driving assignment
([item 25](./025-assignment-is-a-perimeter-verb.md), which is this same
authority question one layer out, about the perimeter instead of about the
builder).

**The mechanism that answers it mostly exists already.** A fragment's source is
a flake input *of this repo*, so it is named in a file the host owns and pinned
in a lock the host controls. `nix flake update target` is a deliberate host act.
What has to be said explicitly, because "the vocabulary is host-declared" only
implies it:

- a project's fragments and tool sources are **registered by the host at a
  pinned source revision**, not named freely by whoever assigns;
- an assigner may compose from the vocabulary and may never extend it;
- so introducing a new tool source is a host operator's act with a rebuild
  behind it, which is the same "rare and declared against frequent and cheap"
  shape the rest of the flavour split rests on.

**Two things that already point the right way.** A target needing `--impure`
cannot be a target at all ([item 23](./023-second-target.md)), so evaluation is
pure by construction. And a dirty target working tree locks as a `dirtyRev`
rather than refusing, which the same item found by accident — a reminder that
the pin is only as good as the discipline around taking it.

**What this does not claim.** Nothing here is a defence against a hostile
project. A host that builds a repo's flake is trusting that repo's build, and no
arrangement of vocabularies changes that. The claim is narrower and is the only
one worth making: **the set of repos whose nix the host will evaluate is the
host's to declare, and is not widened by an assignment.**
