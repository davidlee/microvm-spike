`poweroff` halts the vCPU — the guest even says so, `Power off not available:
System halted instead` — and **the VMM keeps running and keeps the tap open**, so
the next `vm capsule` dies with `Device or resource busy` (EBUSY on TUNSETIFF; a
single-queue tap can only be attached once).

A `reboot` unmounts and then resets, and `reboot=k` makes that reset a VMM exit,
because CPU reset is the one thing firecracker's i8042 stub implements.

**The success path reads like a crash.** It logs `Unexpected exit reason on vcpu
run: Shutdown`, then `Killing vCPU threads`, then `Firecracker exiting
successfully. exit_code=0` — the first two are not errors.

So **ask for a reboot, not a poweroff**. That is `capsule-halt`, used by
`vm-stop` and by the unit's `ExecStop`, and it is why a stop needs a key into the
guest at all.

microvm.nix's own `microvm-shutdown` is `SendCtrlAltDel`, which is **inert here**:
the guest's i8042 driver refuses firecracker's stub outright (`probe with driver
i8042 failed with error -22`), so there is no keyboard to press it on. It is still
worth running *after* the request — its `socat` on the API socket blocks until
firecracker exits, which is exactly the wait a stop needs. Its
`W address is opened in read-write mode` warning is cosmetic.