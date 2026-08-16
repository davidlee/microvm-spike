# EVD-006: A scoped collect took 36 entries against 1886

The same exhibit, collected two ways:

| collect | entries |
| --- | --- |
| whole state tree | **1886** — 1633 files, **253 symlinks**, 18.6 MiB |
| scoped by the assignment's `{unit}` token | **36** |

That ratio is the argument for `statePaths` being a **template** list rather than
a path list: each entry may hold one `{unit}`, filled at collect by an opaque
token the assignment carries, and **a hole with no unit refuses rather than
collecting everything** (`NOTES item 32`).

The 253 symlinks are the other half of why extraction needed care — a symlink
*target* sails through both refusals that catch a `..` path component, and
doctrine's own tree has load-bearing `..` targets that resolve inside the root.

Source: `docs/probes.md`, *The first exhibit, adopted* and *The same exhibit,
scoped*.

The general shape this is evidence for: **the policy says where the hole is, the
assignment says what fills it, and the token is bounded** so it can name an
instance and never widen a perimeter.
