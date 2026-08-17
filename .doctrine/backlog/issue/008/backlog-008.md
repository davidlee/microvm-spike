# ISS-008: The module's CAPSULE_REPO defeats the profile document's own path

**On the module path, `capsule-provision` pushes from this host's one declared
repo whatever profile it is running.** The document's `path` — the field
`NOTES item 51` moved out of `target.nix` so that a program holds one target and
is told which — is unreachable there.

## The two lines

`host/wrap.nix` supplies five variables as defaults:

```
export CAPSULE_REPO=${CAPSULE_REPO:-/home/david/dev/doctrine}
```

`host/git-channel.nix:134` is the program's own lookup:

```
src="${CAPSULE_REPO:-$profile_path}"
```

The wrapper always *sets* it, so the second `:-` never fires. `$profile_path` is
dead on every wrapped verb.

## Why it is not `ISS-004` already, and why `wrapCases` cannot see it

Same class — a wrapper defeating the program it wraps — one variable over.
`ISS-004` was the opposite direction: the wrapper *hard-exported* and defeated a
caller who set the variable deliberately. That is fixed, and
`host/wrap-cases.nix` pins it: a caller's value survives to the program.

The question nobody asks is the other one — **is the program's own fallback
still reachable when no caller sets anything?** For four of the five variables
the answer does not matter, because the baked default *is* what the module
wants. For `CAPSULE_REPO` it does, because since `item 51` the fallback is not a
baked constant any more: it is a value read from the document the front end just
resolved. `cfg.repo` predates that and still names one target
(`/home/${owner}/dev/${target.name}`, host/services.nix).

`host/git-channel-cases.nix:150` pins *"CAPSULE_REPO still beats the document"*,
and that precedence is deliberate and correct. What no suite pins is the module
path with nothing set, which is the arrangement every real slot runs in.

## What it costs

Nothing today: this host has rendered one document per target and both name the
same repo path only because one of them is doctrine's own render. It costs the
moment a slot runs a second target — a provision on a panopticon slot pushes
doctrine's checkout under panopticon's refs, and the verb exits 0.

`IMP-004`'s run did not reach it: read-only verbs only, deliberately, nothing
near the slot driving `SL-251`.

## The fix candidate, not the fix

**Drop `CAPSULE_REPO` from `host/wrap.nix`'s defaults** and let the document
answer, which is what `item 51` built it to do. `cfg.repo` then has no consumer
on the resolution path and is either deleted or demoted to what its docstring
already half-admits — a host override for a checkout that is not under the
owner's home. That is a decision, so it belongs to whatever slice takes this;
the alternative shape (front end exports `CAPSULE_REPO` per resolved profile)
puts the resolution in the right place but keeps a variable in the way of a
field, which is the thing being complained about.

Either way the missing check is the same, and it is the fourth kind
(`CLAUDE.md`): a case over the *composition* asking whether the wrapped program
reaches the document's `path` when nothing in the environment names a repo.

Evidence rung (`STD-001`): **read from source**, both lines, and consistent with
`host/wrap.nix`'s own account of what a default does. Not run — no verb has been
driven on the module path with a second profile. One rung under `taken`.
