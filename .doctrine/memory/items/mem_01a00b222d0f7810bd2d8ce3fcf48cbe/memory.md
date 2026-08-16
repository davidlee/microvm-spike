Measured while mutation-testing `wrapCases` (`ISS-004`), and all three cost a
round each.

**A value on the right of an assignment is not word-split.** `export
V=''${V:-/two words/x}` arrives whole with no quoting at all, because assignment
context does no field splitting and no pathname expansion. So the one-`%q`
discipline is right and *cheap*, but a fixture path containing a **space does not
test it** — remove `lib.escapeShellArg` and every case still passes.

**`lib.escapeShellArg` is a no-op on an ordinary path.** Modern nixpkgs returns
the string unchanged when it matches `[[:alnum:],._+:@%/-]+`, so a fixture like
`/fixture/state` is byte-identical escaped or not. Only a value it *does* quote
can see the escaping at all.

**What does discriminate is escaping it twice** — CLAUDE.md's count-of-one rule,
and the live risk. Two levels arrive as a default carrying its own quote
characters, which lands on any case asserting a quoted value.

**A genuinely hostile fixture is not available**, and that is the useful half:
`writeShellApplication` runs shellcheck over the *built* program, so a `$` in a
spliced path is `SC2016` whether it was escaped or not, and a bare `'` is a parse
error. That class is caught one layer before any case suite runs, by shellcheck
rather than by an assertion — so do not go looking for a case to pin it.

Corollary for mutation rounds, and the reason this is written down: **a mutation
shellcheck rejects fails the build without running a single case, and reads
exactly like "nothing went red".** `exec prog $@` unquoted is `SC2068`; `"$*"` is
the honest mutation that gets past and lands on an argument count. Check the
build succeeded before believing a green mutation round.

Related: [[mem.fact.oubliette.wrap-hard-exports-defeat-the-caller]].
