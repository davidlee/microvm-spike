Host keys live on the capsule's volume, so a fresh capsule presents new ones at
the same address — `known_hosts` refuses, and since the git channel rides ssh
that **blocks provisioning** rather than merely annoying `just ssh`.

`accept-new` does **not** fix it: the host is *changed*, not unknown.

`guestSsh` in `flake.nix` disables the check and keeps no record, injected via
`sshCommand`. **Sound only because the link is a host-created /30 with one peer**
— change it in the same commit as any change to the transport, and don't "fix" it
with a capsule-scoped `known_hosts`, which just accumulates one stale key per
capsule.