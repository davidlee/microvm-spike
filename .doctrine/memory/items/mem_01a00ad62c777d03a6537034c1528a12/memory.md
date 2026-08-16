**A module's programs are not in its unit graph.** `hostModuleUnits` evaluates
the whole module — worth seconds instead of a rebuild — but it only ever *forced*
assertions, unit names and `serviceConfig` strings. Everything on a human's PATH
lives in `environment.systemPackages`, which nothing read, and nix is lazy: an
argument added to one of `host/cli.nix`'s two call sites made a host rebuild die
on `function 'anonymous lambda' called without required argument 'observe'`
**after both `just build` and `just units` were green.**

Now forced, with **names in the output and paths never** — `builtins.seq` on an
outPath evaluates the derivation, while embedding the string *of* one would make
every program a build input of a text file and turn the eval into a build.

**The general shape: anything built at two call sites needs one construction, not
two careful ones.** `observe` moved into `host/programs.nix` beside the paths it
reads for that reason, which is the same reason `baselineRecord` is exported
there.

**Forcing is not building, and shellcheck is a build.** So the same hole survived
one layer down: a program that is only ever an `ExecStart` — `capsule-netns`,
`capsule-egress-ns`, `capsule-perimeter-guard` — is named by no flake output and
is not in `systemPackages`, and **nothing had ever built one**. A rollback
written into `capsule-netns` passed `just check`, `just build` and `just units`
unread by shellcheck (`NOTES item 37`).

`hostModulePrograms` is the deliberate inversion: a second derivation off the
same evaluation whose text *is* every `serviceConfig` literal, making each one a
build input on purpose. Two derivations, one eval.

**The same hole had two more rooms** (`NOTES item 52`): the module's **activation
scripts** are in neither the unit graph nor `systemPackages`, and the
**`wrap`pers** in `systemPackages` were only ever forced — five programs whose
entire text is the environment this host's copies run with, never shellchecked.
Both are in `hostModulePrograms` now, selected by `capsule` name prefix rather
than hand-listed.

**Carry this forward:** anything the module produces that is neither a unit's
`ExecStart` nor a flake output needs a line there, or nothing builds it.