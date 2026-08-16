`capsule-provision` on `PATH` in the devshell ssh's straight to `net.guest`,
which is **unroutable from the root namespace** once the tap is in a namespace.
The module's copy of the same program goes through the relay socket.

**Same name, same source, different `transport`.**

The devshell's copies **refuse rather than time out**: a relay socket for the
named capsule means the module path owns this host, so they name the copy to run
instead of ssh'ing at an address that is no longer routable from here. It used to
be a timeout against `10.99.0.2`, which reads as a dead guest.

**Refusing, not choosing** — a program that can try both transports has both
baked in (`NOTES item 20`). `just provision | inject | baseline | collect | setup
<name>` picks the reachable copy, which is a recipe's latitude and not a
program's.