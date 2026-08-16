# CHR-006: Re-take probe-netns-egress's assertion total

**A probe's assertions are only as current as its last run**, and one count was
never captured: `probe-netns-egress`'s last run recorded its **colour and not its
total**.

That is exactly the evidence `STD-001`'s fourth lying instrument is about —
`probe-netns-egress` skips to 27 and still reads green; **33** is what says stage
2b ran. A green with no total is indistinguishable from a vacuous run.

Needs root; the user runs it (`sudo probe-netns-egress`). Set `CAPSULE_KEEP=1`
first — the guest console log lives inside the state directory the probe deletes,
and a log is only ever wanted after a red run.

Evidence rung (`STD-001`): restores **run**. The current evidence is below it.
