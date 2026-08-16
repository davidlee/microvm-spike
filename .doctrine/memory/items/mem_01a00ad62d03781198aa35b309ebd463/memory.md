The CLI appends `#nixosConfigurations.<name>.config.microvm.declaredRunner`
itself, so `-f …#capsule` asks for that attribute **of** `packages.capsule` and
the error reads as a missing output.

With **no `-f` at all** it defaults to the flake at `/etc/nixos` — not a git repo
on this host — and fails as `fatal: '/etc/nixos' does not appear to be a git
repository`, **naming neither the missing flag nor the fact that it substituted a
path you never typed.**

Use `just up <name>`, which passes `{{justfile_directory()}}`. It also needs root,
for `/var/lib/microvms` and the gcroots.

`microvm -u` takes no `-f`, **correctly** — it re-reads the flake ref recorded in
`/var/lib/microvms/<name>/flake`, which for every slot here is the bare path
`/home/david/dev/oubliette`. A bare path reads the **working tree**, so a refresh
picks up an uncommitted `flake.lock`. After a guest change use
`just refresh-build <name>`, which reads `ActiveState` rather than `is-active` —
`auto-restart` is the worst moment to update under.