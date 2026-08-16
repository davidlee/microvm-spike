`capsule-host`'s port check is a **connect from the host**, and `capsule-proxy`
denies RFC1918, so systemd drops the probe and **the port reads as free**.

Hence the explicit `systemctl is-active` refusal in the injected `preflight` —
systemd-shaped, so it lives at the call site in `flake.nix`, **not** in
`perimeter/`, which knows nothing about the jail.