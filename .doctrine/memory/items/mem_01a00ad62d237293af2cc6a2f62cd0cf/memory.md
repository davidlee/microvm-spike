A Ctrl-C could leave tinyproxy holding the port. `capsule-host` preflights the
port, reaps a stray matching its own config path, and uses `wait -n` with an
INT/TERM trap. If a bind fails anyway, look for strays with `ss -lntp`.

**`wait -n` must name its pids.** Bare `wait -n` waits for the next job to change
state, and a child that exited **before** the call has already been reaped and
forgotten — so `capsule-host` sat blocked on its watch loop, **with its services
dead at bind time, looking healthy and serving nothing.**

`wait -n "${children[@]}"`: with explicit pids bash keeps each status until waited
on.