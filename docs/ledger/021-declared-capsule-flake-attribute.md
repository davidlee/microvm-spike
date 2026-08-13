# NOTES item 21 — a declared capsule needs a flake attribute, and all of them are one value

*State: built and run at N=2.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**A declared capsule needs a flake attribute, and all of them are one
value.** Declaring a second capsule in `capsules.nix` generated its
namespace, proxy and relay units — and then `sudo microvm -c capsule-b -f .`
had nothing to create from. The CLI appends
`#nixosConfigurations.<name>.config.microvm.declaredRunner` itself
(CLAUDE.md), so *the instance's name is a flake attribute*, while
`nixosConfigurations` was a two-entry literal: `hello` and `capsule`.

The obvious fix is the wrong one. `mkVm name ./vm/capsule.nix` per instance
reads as one line of `mapAttrs`, and it sets `networking.hostName = name` — the
hostname is *in the closure*, so that is a second guest, a second 12 GiB image
and a second thing to keep in step, for a string. The one-image lever
([item 17](./017-more-than-one-capsule.md)) is not an efficiency here; it is
what makes an instance cheap enough to be a unit start rather than a design
change.

So the mapping is to a single value: `capsuleVm` is built once, and every
declared capsule is bound to *it* rather than to a rebuild of it. Identical
modules would already produce an identical derivation, but binding the same
value says so at the point someone would otherwise add a per-instance
argument — the property stops depending on nobody noticing that the
hostname, or the index, or the socket path, could be threaded in "just for
this one". What differs between two capsules stays exactly what differed
before: a namespace, a volume, a state directory, a relay socket.

The price is the one plan-c-implementation.md already named: the hostname is
`capsule` in every guest, so the prompt inside one does not say which. Paid
knowingly, and not with `systemd.hostname=` on the cmdline — a per-instance
cmdline is a per-instance closure again, by another route.
