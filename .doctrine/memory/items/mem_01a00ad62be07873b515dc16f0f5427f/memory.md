Claude Code used to render fine on the serial console but **ignore Enter** (the
same binary over ssh worked). `boot.kernelModules = ["i8042" "atkbd"]` in the
guest fixes it, A/B'd both ways with nothing else changed.

**Neither driver binds anything** — i8042 fails to probe, so atkbd has no port,
and no input device appears. So that is an observation, not an explanation.

Do not build on the mechanism, and do not drop those modules casually. ssh is
still the documented way to run agents.