# CON-003: capsule-provision called directly writes no record

`capsule-provision` called **directly** writes no assignment record. Deliberate
(`NOTES item 29`): **the record is front-end written.**

Consequence, which is the part worth knowing: a slot can be provisioned with **no
`base` pinned**, and the only things that say so are a missing key and a `-` in
the `gen` column of `capsule all status`.

This is the same boundary as profile resolution — which name a verb on a slot
means is the **front end's** act, because a program that reads host state to pick
a target is `NOTES item 20`'s mistake. A program that wrote its own record would
be choosing its own assignment.

Two related traps:

- **`CAPSULE_STATE` moves the quarantine and not the record.** The record's root
  is the literal `/var/lib/capsule`, deliberately — a slot is a module-path thing
  — while `quarantineOf` *searches* both homes because either shape can collect.
  So a devshell `capsule <name> unit|purpose|provision` writes the **live**
  record whatever `CAPSULE_STATE` says. There is no throwaway root to try one
  against: the generation only goes up, so an experiment is a hand-edit to undo.
- **A provision is the one verb that reads this host's profile directory**
  (`NOTES item 52` step 3), because the act that sets a pin cannot be governed by
  it.

Active, and not a candidate for relaxation — the alternative is a program that
chooses its own assignment.
