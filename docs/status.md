# Status — retired

**This file held the present tense and no longer does.** It is kept as a
redirect, not as a document: roughly forty places in this repo link to it,
including four items of the frozen [ledger](./ledger/index.md), and the same
reasoning that froze the ledger rather than renumbering it (`ADR-002`) applies
here — the citation graph is the hazard, not the file.

**Nothing is added below.** A tombstone that grows a section is the thing
[item 54](./ledger/054-status-grew-a-changelog.md) was written about, arriving
one file later.

| what it held | where that is now |
| --- | --- |
| **Now** — what is true on this host at this moment | **derived, not authored.** `capsule all status` answers it: slots, units, purposes, profiles, policies, the `*`/`!` pin markers, and a unit column that distinguishes `running` from `auto-restart`. Ask the program, don't read one — the module's copies on `PATH` are wrappers |
| **Recent** — five evicting entries | `git log`. That was already the rule; the five entries were the compensation for commit messages that had stopped carrying the session, which is item 54's finding |
| **Next, in order** | `doctrine backlog list` — `CHR-001`…`CHR-003` are the three live exercises, `IMP-001`…`IMP-004` the Plan D steps and the second target, `IDE-001` the parked skill-driven slice |
| **Open** — claims nothing should call closed | split by the work-intake membership test, which is what it had conflated: **something to do** → `doctrine backlog list` (`RSK-001`…`RSK-006`, `ISS-001`, `ISS-002`, and seven chores); **something that is** → `doctrine knowledge list` (`CON-001`…`CON-005`, `QUE-001`…`QUE-005`) |
| the standing caveat at the top of **Open** | `STD-001` — *ask which verb your evidence covers*. Nine rungs, from `NOTES item 1` |

Read [.doctrine/project-orientation.md](../.doctrine/project-orientation.md)
first; `ADR-001` records why governance moved and on what terms.

**One trap this move does not remove.** `unit` and `purpose` on a slot name the
*confined* project's entities. `SL-251` and `SL-254` in a slot's record are
doctrine's slice ids, in doctrine's corpus. An `SL-`/`ADR-`/`REQ-` id in this
repo's `.doctrine/` is this repo's and means nothing there (`ADR-001` term 2).
