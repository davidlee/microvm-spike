# RSK-005: microvm -c capsule would create a capsule with no perimeter

The guest image is a flake attribute sitting beside the slots, and **it has to
be** — probes build `.#capsule` and match `microvm@capsule`, so `capsule` must
stay a real attribute even though it is not declared in `capsules.nix`.

`microvm -c` resolves **any** attribute. So `microvm -c capsule` creates an
instance with no namespace, no proxy and no relay unit: it boots into the **root
namespace**, where the perimeter does not exist.

What guards it: `capsule` and `just up` refuse the name because it is not
declared (`NOTES item 28`). **Nothing else.** The refusal is in the front end, and
`microvm` is upstream of the front end.

Severity is the reason this is tracked rather than filed: every other item here
is about evidence, and this one is about the perimeter. It is a hole reachable by
a plausible typo from a root shell.

Related trap when reading the situation: **`microvm -c … -f <flake>` takes no
fragment**, and omitting `-f` defaults to `/etc/nixos` and fails naming neither
problem.

Evidence rung (`STD-001`): reasoned, never **triggered** — and deliberately so.
