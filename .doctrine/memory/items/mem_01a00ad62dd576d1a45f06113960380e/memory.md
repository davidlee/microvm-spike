just interpolates a recipe's arguments as **text**, so the recipe's own shell
parses them before anything is sent: `just ssh b 'echo $(hostname)'` answered
`Sleipnir`.

It is **not** word-splitting — that was the documented and survivable half. It is
a diagnostic that **reads as the capsule's and is the host's**, which is the one
failure a door exists to prevent, and it is **silent because both ends have a
`hostname`**.

`capsule <name> ssh` never had it, because a program takes argv.

`just ssh`/`just admin` now `quote(cmd)` and pass one word, with the empty case
kept distinguishable since no command means an interactive shell.

**Any new recipe that forwards `*args` into a program has this until it quotes**,
and the general rule is that `{{...}}` is text substitution and never an
argument.