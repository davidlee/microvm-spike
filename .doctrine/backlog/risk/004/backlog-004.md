# RSK-004: The two copies of the CLI are one store path by construction, unchecked

`flake.nix` and `host/services.nix` both import `host/cli.nix`. The claim that
this is **one derivation rather than two** rests entirely on the two argument
sets being equal — which they were **not**, for `observe`, until a host rebuild
said so.

`hostModuleUnits` forces the module's programs, so a **missing** argument is
caught at eval. A **different** argument would still produce two silently
identical-looking programs, and nothing would say so.

**Narrowed by subtraction rather than checked**: every argument that could differ
now comes from one place. That is a real reduction and it is not a control — the
next argument added at one call site reopens it.

The general shape, which is the part worth keeping: **anything built at two call
sites needs one construction, not two careful ones.** `observe` moved into
`host/programs.nix` beside the paths it reads for exactly this reason, and
`baselineRecord` is exported there for the same one.

Note the reading trap when investigating: the module's programs on `PATH` are
**wrappers**, so grepping one answers about the wrapper. Ask the program.

Evidence rung (`STD-001`): **build** proves each evaluates; nothing **compares**
the two.
