# ISS-002: vm --help creates a VM state directory named --help

`vm --help` creates `.vm/--help/`. Every argument is treated as a VM name; there
is no flag parsing at all.

Papercut. Cheap, and the failure mode is litter rather than damage.

Evidence rung (`STD-001`): **triggered**, by accident, which is how it was found.
