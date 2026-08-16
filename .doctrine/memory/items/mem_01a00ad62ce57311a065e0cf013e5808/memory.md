`host/services.nix`'s `wrap` builds a package under the **same name** whose whole
text is `CAPSULE_STATE`/`CAPSULE_REPO` and `exec <inner>`. The five that keep
host state (`capsule`, `capsule-collect`, `capsule-provision`, `capsule-adopt`,
`capsule-brief`) are **three lines each** in `/run/current-system/sw/bin`.

So grepping one **reports a program that does not have the flag**, and every
generation shares the wrapper's store path whenever nothing it embeds moved —
which reads as *this host never rebuilt*.

**Both readings are wrong in the same direction and they corroborate each
other**: an interactive `PATH` here can also hold a third, staler `capsule` that
really is behind, so a verb list taken from `which capsule` agrees with the bad
grep and nothing contradicts either.

**Ask the program, don't read it** — `/run/current-system/sw/bin/capsule all
status`, or follow the `exec` line to the inner store path.

Cost a session, concluding the host was a version behind when it was current.