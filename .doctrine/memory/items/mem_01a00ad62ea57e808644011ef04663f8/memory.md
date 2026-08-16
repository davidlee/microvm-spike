The `oubliette` input is `github:davidlee/oubliette`, so `nix flake update
oubliette` needs the commit **pushed** — but `just system-switch` passes
`--override-input oubliette git+file:///home/david/dev/microvm-spike`, a symlink
to this checkout, and **that is what actually lands**. A lock update alone
changes nothing.

The override reads **committed HEAD** there, and it will happily build from a
**dirty** tree — after which the next build from HEAD **silently loses whatever
was dirty**.

Related: **a generation bump is not evidence a code change landed.** Four
consecutive rebuilds here had nothing between them.