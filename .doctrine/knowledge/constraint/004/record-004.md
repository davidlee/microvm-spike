# CON-004: A rotated secret does not reach a running capsule

Every payload is **write-if-absent**. That is what makes injecting at every start
a no-op rather than a clobber — and it is why a rotated secret does not reach a
capsule that is already running.

Refreshing at start would **discard what the guest wrote, silently, N times**, so
it is not policy (`NOTES item 22`). The asymmetry is the point: a clobber is
silent and a staleness is visible, so the design prefers the visible failure.

`capsule-inject --force` is the manual answer.

Related and separately open: **whether an injected credential survives use at
all** (`QUE-003`) — the token rotates on refresh and the capsule holds a copy,
not the shared file, so host and capsule drift and nobody has measured how long
the copy stays good.

Active. Relaxing it means finding a rule that distinguishes *the guest wrote
this* from *the host rotated this*, which nothing currently records.
