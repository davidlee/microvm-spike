Check `pgrep -af 'microvm@'` — **not** whether the console returned, and not
whether the guest answers ping.

Related and sharper: **a VMM is identified by its namespace, never by its name.**
The one-image lever means every capsule runs the same runner from the same store
path, so all of them are `microvm@capsule` in the process table. `pkill -f` on
that name is a power cut for the siblings, and it reads as a clean teardown while
doing it.

`vm_running`, `wait_vm` and `halt_guest` all take a namespace and scope
themselves with `ip netns pids`. The unscoped question survives as
`any_vm_running`, which is what a probe's refusal wants and the only thing it is
for.