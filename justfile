# capsule — firecracker agent jail. README.md is usage, docs/ is everything else.
#
# The **devshell** path's lifecycle (capsule-net, capsule-host, vm, vm-stop, and
# the git channel's capsule-provision / capsule-collect) comes from the devshell
# and is not wrapped here — each is already one command. What is here is the
# stuff that has no home otherwise: the pre-commit gate, the questions that need
# more than one command to answer, and the **module** path's create step, which
# is the one part of a capsule's life that needs this flake.
#
# Everything else about a running capsule is `capsule <name> <verb>`
# (host/cli.nix) and the recipes below delegate to it, because a capsule outlives
# this checkout: the units are on the host and a human logged into it has no repo.
# Where a recipe still exists, it is for its comment or for the flake it needs.
#
# **No recipe spells a capsule's name.** The delegating ones default it to the
# empty string and let `capsule` resolve an unnamed verb to whatever is up — one
# answer, in one place, rather than the word `capsule` fifteen times here, which
# was invisible while the default capsule was called that and wrong the moment it
# was not. The recipes that use the name for something of their own — creating,
# updating, a log path, a cgroup — **require** it, which is also the right
# posture: making and destroying a slot is not a thing to do to whichever one
# happens to be running.

# Every nix file that is ours. Explicit, so nothing walks .direnv or .vm.
nix_paths := "flake.nix net.nix target.nix capsules.nix fragments.nix setup.nix perimeter host vm"

# the gate: everything parses and is formatted
default: check build units

# addresses and ports come from net.nix or they drift
# --json, not --raw: the ports are integers and --raw refuses to coerce one
_net key:
  @nix eval --json --file net.nix {{key}} | tr -d '"'

# same for the repo under confinement — target.nix or it drifts
_target key:
  @nix eval --json --file target.nix {{key}} | tr -d '"'

# and for the host's controls, which are not the target's — policies.nix
_policy key:
  @nix eval --json --file policies.nix {{key}} | tr -d '"'

# the proxy's log, wherever this host keeps it. A capsule is a *directory* under
# the module's proxy state — one proxy per capsule since the units went
# per-namespace — so this takes the name; the devshell path has one proxy and one
# log, and ignores it.
_proxy-log name:
  #!/usr/bin/env bash
  set -euo pipefail
  for f in "/var/lib/capsule-proxy/{{name}}/tinyproxy.log" \
           "${CAPSULE_PROXY_STATE:-${CAPSULE_STATE:-${CAPSULE_ROOT:-$PWD}/.vm/host}}/tinyproxy.log"; do
    [ -f "$f" ] && { echo "$f"; exit 0; }
  done
  echo "no proxy log yet — start capsule-host or capsule-proxy" >&2
  exit 1

# parse + format, no eval and no build: cheap enough for every edit
check: parse fmt-check

# every nix file parses — and `--parse` never evaluates, so it cannot build
parse:
  #!/usr/bin/env bash
  set -euo pipefail
  find {{nix_paths}} -name '*.nix' -print0 | xargs -0 -n1 nix-instantiate --parse >/dev/null
  echo "parse: ok"

# format
fmt:
  alejandra -q {{nix_paths}}

# assert formatting without mutating it
fmt-check:
  alejandra -c {{nix_paths}}

# the host-side scripts — shellcheck runs at build, so this is the real lint.
# capsule-baseline, capsule-refresh, capsule-adopt and capsule-brief exist only
# while the target declares a `baseline` / a `refresh` / any `statePaths`; a
# target that omits one drops that line, and the build says so rather than
# skipping it.
# `guardCases` is here rather than in its own recipe on purpose: a case that
# fails fails the build, which is the only way a check gets run every time.
build:
  nix build --no-link '.#capsule-cli' \
    '.#capsule-host' '.#capsule-net' '.#vm-stop' '.#capsule-halt' \
    '.#probe-netns' '.#probe-netns-boot' '.#probe-freshness' \
    '.#probe-two-capsules' \
    '.#capsule-provision' '.#capsule-collect' '.#capsule-inject' \
    '.#capsule-baseline' '.#capsule-refresh' '.#capsule-adopt' \
    '.#capsule-brief' \
    '.#hostModuleUnits' '.#hostModulePrograms' \
    '.#guardCases' '.#policyCases' '.#briefCases' '.#snapshotCases'

# which units the host module generates, without rebuilding a host — the only
# mechanical check the NixOS half has
units:
  @cat "$(nix build --no-link --print-out-paths '.#hostModuleUnits')"

# what a host-side program's logic decides, against a substitute for the one
# thing tying it to this host: the guard against a stubbed kernel, the brief
# runner and the state snapshot against a throwaway checkout. All three are
# verdicts a live host can only produce destructively or expensively — by
# unnaming a namespace under a running guest, by dirtying one capsule's worktree
# to watch another refuse it, or by driving a real unit of work in a checkout
# that holds several.
cases:
  @cat "$(nix build --no-link --print-out-paths '.#guardCases')"
  @cat "$(nix build --no-link --print-out-paths '.#policyCases')"
  @cat "$(nix build --no-link --print-out-paths '.#briefCases')"
  @cat "$(nix build --no-link --print-out-paths '.#snapshotCases')"

# the guest closure and its runner — the slow one
build-vm:
  nix build --no-link '.#capsule'

# is the host-side perimeter loaded? dropped / latent / open
verify:
  capsule-net verify

# --------------------------------------------------------- the module path
#
# Three commands because a capsule under systemd is not one: it has to be
# created before it can start, its state directory tracks that directory rather
# than the flake, and a stop is a request the *guest* carries out. Each recipe
# below is one of those three with the trap that goes with it.
#
# The devshell path has none of this and is unaffected — but run one shape or
# the other, never both, which is what `up` refuses on.

# Creating is the one part of a capsule's lifecycle that needs *this* flake:
# `microvm -c <name>` resolves the instance's name as a flake attribute (notes
# item 21), so it cannot be done from a host with no checkout. Everything after it
# is `capsule <name> start` — the stay-up assertion, the reload trap and the
# journal tail all live there now, where a human logged into the host can reach
# them (host/cli.nix).
#
# create if this host has never seen this capsule, then start it (root)
up name:
  #!/usr/bin/env bash
  set -euo pipefail
  tap=$(just _net tap)
  if ip link show "$tap" >/dev/null 2>&1; then
    echo "just up: refusing — $tap is in the root namespace, so the devshell" >&2
    echo "  shape is up. 'vm-stop' then 'capsule-net down' first: two" >&2
    echo "  perimeters over one guest is worse than one, not safer." >&2
    exit 1
  fi
  if capsule {{name}} created; then
    echo "{{name}}: created already"
  else
    # The flake ref carries no fragment: the CLI appends
    # #nixosConfigurations.<name>.config.microvm.declaredRunner itself, so a
    # fragment asks for that attribute *of* a package and reads as a missing
    # output. Root, for /var/lib/microvms and the gcroots.
    echo "{{name}}: never created on this host — creating"
    sudo microvm -c {{name}} -f "{{justfile_directory()}}"
  fi
  capsule {{name}} start

# stop it cleanly, and show what the stop actually did (root)
down name="":
  @capsule {{name}} stop

# Nothing reaches a created VM until its state directory is rebuilt, because
# that directory is what it tracks. Cleanly down first, so the update never
# lands under a mounted volume, and back up only if it was up.
#
# after a guest change: rebuild its state directory, restart if it was running
refresh-build name:
  #!/usr/bin/env bash
  set -euo pipefail
  # Not `is-active`, which is false for a unit in `auto-restart` — the one state
  # where updating under it is worst, because it is about to start again.
  state=$(systemctl show microvm@{{name}} -P ActiveState)
  if [ "$state" = inactive ] || [ "$state" = failed ]; then
    running=no
  else
    running=yes
    just down {{name}}
  fi
  sudo microvm -u {{name}}
  if [ "$running" = yes ]; then
    just up {{name}}
  else
    echo "{{name}}: updated, and it was not running — 'just up {{name}}'"
  fi

# Two shapes answer this differently and both are shown. The per-capsule table is
# `capsule all status` — every column of it readable without root, and what is
# inside a namespace named as the guard's rather than printed as unknown
# (host/cli.nix). What is left here is the devshell shape, whose tap and listener
# *are* in this namespace and so can be shown directly.
#
# every capsule, plus the devshell shape's own link — one screen
status:
  #!/usr/bin/env bash
  set -uo pipefail
  capsule all status
  echo
  echo "== devshell shape (its tap and listener are in this namespace; a"
  echo "   namespaced one is not, which is what the table above is for)"
  ip -brief addr show "$(just _net tap)" 2>/dev/null | sed 's/^/  /' \
    || echo "  no tap here"
  ss -lntp "sport = :$(just _net proxyPort)" 2>/dev/null | tail -n +2 | sed 's/^/  /' \
    || echo "  nothing on the proxy port"
  just verify 2>&1 | sed 's/^/  /'

# The capsule comes first in every one of these, as everywhere else here, so
# `just provision b main` cannot be read the other way round. The ref is
# not defaulted: `capsule-provision` refuses without one, and that refusal should
# have one home.
#
# push a ref into a capsule's checkout
provision name="" ref="" *flags:
  @capsule {{name}} provision {{ref}} {{flags}}

# the non-git half: credentials and anything else setup.nix declares
inject name="" *args:
  @capsule {{name}} inject {{args}}

# regenerate the derived state a push cannot carry — a provision does this
# itself, so this is for a hand checkout in the guest or a retry after one failed
refresh name="":
  @capsule {{name}} refresh

# the target's own build-and-test in the guest, with its record on the volume
baseline name="" *flags:
  @capsule {{name}} baseline {{flags}}

# what the capsule has produced, into this host's quarantine
collect name="":
  @capsule {{name}} collect

# the state half out of quarantine and onto a disk, validated first — the code
# half is `fetch`. `just adopt a /tmp/exhibit`, or a bare `--list` to look.
adopt name="" *args:
  @capsule {{name}} adopt {{args}}

# another capsule's collected state into this one's checkout, so a second agent
# can read the first one's working state. Both must be at the same commit.
# `just brief b a` or `just brief b a:implementation`.
brief name="" spec="":
  @capsule {{name}} brief {{spec}}

# a fresh capsule to green: provision, inject, baseline
setup name="" ref="":
  @capsule {{name}} setup {{ref}}

# what a capsule has produced, as collected — `all` for every capsule
branches name="":
  @capsule {{name}} branches

# the second step: quarantine -> the repo you work in, once you have looked
fetch name="":
  @capsule {{name}} fetch

# What the host pays while capsules work — the question the withdrawn "16 GiB per
# capsule" left behind, since what binds at N is what capsules *touch*.
#
# Per **cgroup**, not per process, and that is the whole design. Host-wide PSI on
# this machine measures whatever else is running — other agents grepping read as
# 93% io pressure while the capsules' own cgroups sat at 0.00 — so a host-wide
# figure is not a capsule figure. A unit's cgroup isolates it, charges shared
# pages once, and hands over `memory.peak` and `memory.events` from the kernel:
# **the peak does not depend on this sampler's interval**, and zero events is what
# says a peak is a high-water mark rather than a reclaim floor.
#
# The cgroup comes from the unit, because a VMM cannot be found by name — one
# image means every one of them is `microvm@capsule` in the process table
# (CLAUDE.md). Everything read is world-readable: no root, and not a probe, since
# this attaches to the real instances rather than booting throwaways.
#
# Sampled to a file *and* summarised, because a figure whose only copy is terminal
# scrollback is not a figure (docs/probes.md). Ctrl-C ends it.
#
# what these capsules cost while they work: cgroup memory, their own pressure
load +names:
  #!/usr/bin/env bash
  set -uo pipefail
  # A parameter until the capsule name stopped having a default: a
  # variadic list has to come last, and just refuses a required parameter after
  # a defaulted one. An environment variable keeps the override without putting
  # a second positional in front of the names.
  out="${CAPSULE_LOAD_TSV:-.vm/load.tsv}"
  mkdir -p "$(dirname "$out")"
  read -ra names <<<"{{names}}"
  declare -A cg
  for n in "${names[@]}"; do
    cg[$n]="/sys/fs/cgroup$(systemctl show "microvm@$n" -P ControlGroup)"
    # The pressure files are checked as well as the memory one, because a kernel
    # with PSI off has the cgroup and not them — and an absent pressure file read
    # as an empty column, or defaulted to zero, is a report of *no contention*
    # from an instrument that cannot see any. Refuse instead.
    for f in memory.current cpu.pressure io.pressure; do
      [ -r "${cg[$n]}/$f" ] || {
        echo "just load: no readable $f for microvm@$n — start it first, and if" >&2
        echo "  the cgroup is there then PSI is off and this cannot measure." >&2
        exit 1
      }
    done
  done
  # Every capsule is in the same slice, so its *current* total is the answer to
  # "what do N of them cost" with nothing double-counted. Its **peak** is not:
  # `systemctl stop` destroys a unit's cgroup and resets that unit's peak, but the
  # slice stays active with no members — measured, `ActiveEnterTimestamp` hours
  # older than the units in it — so the slice's peak spans every capsule that has
  # run since it went active. Read once here and once at the end: a peak that did
  # not move is a peak this run did not set, and saying so is the difference
  # between a figure and a number left over from a previous session.
  slice=$(dirname "${cg[${names[0]}]}")
  mib() { echo $(( $(cat "$1") / 1048576 )); }
  declare -A peak0
  for n in "${names[@]}"; do peak0[$n]=$(mib "${cg[$n]}/memory.peak"); done
  slice_peak0=$(mib "$slice/memory.peak")
  # A pressure file is two lines — `some`, at least one task stalled, and `full`,
  # every task stalled — each carrying avg10/60/300 and a cumulative `total=` in
  # microseconds. avg10 is all a sample can show and it is a decaying average, so
  # a spike between samples is gone by the time this loop looks; `total` is the
  # integral, and the only pressure figure here that does not depend on the
  # interval. Both are taken: the samples say *when*, the totals say *how much*.
  psi() {
    awk -v want="$2" -v key="$3" '
      $1 == want {
        for (i = 2; i <= NF; i++) { split($i, kv, "="); if (kv[1] == key) print kv[2] }
      }
    ' "$1"
  }
  # Same argument as the memory peaks, one field further: a `total=` read only at
  # the end is every stall since the cgroup was created, which for a capsule that
  # has already built once is mostly somebody else's session.
  declare -A cpu_stall0 io_stall0 iofull_stall0
  for n in "${names[@]}"; do
    cpu_stall0[$n]=$(psi "${cg[$n]}/cpu.pressure" some total)
    io_stall0[$n]=$(psi "${cg[$n]}/io.pressure" some total)
    iofull_stall0[$n]=$(psi "${cg[$n]}/io.pressure" full total)
  done
  {
    printf 'elapsed'
    for n in "${names[@]}"; do
      printf '\t%s_mib\t%s_cpu_some\t%s_io_some\t%s_io_full' "$n" "$n" "$n" "$n"
    done
    printf '\tslice_mib\thost_avail_mib\n'
  } >"$out"
  trap 'break' INT TERM
  start=$SECONDS
  while :; do
    line="$((SECONDS - start))"
    for n in "${names[@]}"; do
      line+=$'\t'"$(mib "${cg[$n]}/memory.current")"
      line+=$'\t'"$(psi "${cg[$n]}/cpu.pressure" some avg10)"
      line+=$'\t'"$(psi "${cg[$n]}/io.pressure" some avg10)"
      # `full` on io is the one that says a capsule got nothing done: every task
      # in it stalled at once. cpu has no useful `full` at cgroup level, so it is
      # not sampled — a column of zeros would only look like a measurement.
      line+=$'\t'"$(psi "${cg[$n]}/io.pressure" full avg10)"
    done
    line+=$'\t'"$(mib "$slice/memory.current")"
    line+=$'\t'"$(( $(awk '/^MemAvailable:/{print $2}' /proc/meminfo) / 1024 ))"
    printf '%s\n' "$line" >>"$out"
    sleep 2
  done
  elapsed=$((SECONDS - start))
  # Written as well as printed, for the same reason the samples are: the peaks are
  # the figure this recipe exists to produce, and until now they existed only in
  # scrollback (docs/probes.md).
  peaks="$out.peak"
  # Stall time this run is responsible for, as seconds and as a share of the
  # window they fell in — the share is what makes two capsules, or two runs of
  # different length, comparable at all.
  stalled() {
    awk -v now="$1" -v before="$2" -v s="$3" 'BEGIN {
      us = now - before
      # Parenthesised, and it has to be: awk reads a bare `s > 0` in an argument
      # list as an output redirection, and shellcheck cannot see inside an awk
      # program to say so. A smoke run is what catches this class.
      printf "%.1fs (%.1f%%)", us / 1000000, (s > 0 ? us / (s * 10000) : 0)
    }'
  }
  {
    echo "peak, from the kernel rather than from these samples:"
    sum=0 most=0
    for n in "${names[@]}"; do
      p=$(mib "${cg[$n]}/memory.peak")
      sum=$(( sum + p ))
      [ "$p" -gt "$most" ] && most=$p
      printf '  %-14s %s MiB' "$n" "$p"
      [ "$p" = "${peak0[$n]}" ] && printf '  (unchanged — set before this run)'
      # A nonzero event means the kernel reclaimed, and a peak measured under
      # reclaim is a floor. Printed beside the number it qualifies.
      ev=$(awk '$2 != 0 {printf "%s=%s ", $1, $2}' "${cg[$n]}/memory.events")
      [ -n "$ev" ] && printf '  (memory.events: %s)' "$ev"
      echo
    done
    # The pair cost is bounded, not known: the slice's peak is unattributable
    # unless it moved, and two units' peaks need not have coincided in time.
    sp=$(mib "$slice/memory.peak")
    # Not aligned to the number above it: this name is longer than any capsule's
    # can be, so a shared column would only ever line up by accident.
    printf '  %s %s MiB\n' "$(basename "$slice")" "$sp"
    if [ "$sp" = "$slice_peak0" ]; then
      printf '    unchanged since before this run, so NOT set by it — a slice outlives\n'
      printf '    the units in it. Quote the bound below instead.\n'
    else
      printf '    was %s MiB before this run.\n' "$slice_peak0"
    fi
    printf '  bound on these %d together: [%s, %s] MiB — the largest unit, and their sum\n' \
      "${#names[@]}" "$most" "$sum"
    echo
    printf 'stalled during these %ss, cumulative from the kernel:\n' "$elapsed"
    for n in "${names[@]}"; do
      c="${cg[$n]}"
      printf '  %-14s cpu %s  io %s  io-full %s\n' "$n" \
        "$(stalled "$(psi "$c/cpu.pressure" some total)" "${cpu_stall0[$n]}" "$elapsed")" \
        "$(stalled "$(psi "$c/io.pressure" some total)" "${io_stall0[$n]}" "$elapsed")" \
        "$(stalled "$(psi "$c/io.pressure" full total)" "${iofull_stall0[$n]}" "$elapsed")"
    done
  } | tee "$peaks"
  echo "samples in $out, peaks in $peaks — quote figures from there, not from this screen"

# every egress attempt, live — unlisted hostnames show up here as denials
proxy-log name:
  tail -f "$(just _proxy-log {{name}})"

# hostnames a policy's proxy will resolve — a destination control, not an exfil
# one. Named, never defaulted: there is no fleet-wide allowlist any more, and
# `capsule <slot> policy` says which one a slot is on (NOTES item 36).
allowed policy:
  @cat "$(just _policy dir)/$(just _policy policies.{{policy}}.allowlist)"

# A trailing command reaches the guest as one word, via `quote`, and the reason
# is stronger than tidiness. just hands a recipe its arguments by *interpolation*
# rather than on a command line, so a bare `{{cmd}}` is text the recipe's own
# shell then parses: `$(…)` and backticks run **on this host**, and their output
# is what the guest is asked. `just ssh b 'echo $(hostname)'` answered `Sleipnir`
# — a diagnostic that reads as the capsule's and is the host's, which is the one
# failure a door exists to prevent. `capsule <name> ssh` never had it, because a
# program takes argv. Quoting once here makes the two agree; the remote shell
# does the expanding, which is where it was always meant to happen. The empty
# case has to stay distinguishable, since no command means an interactive shell.
# Which door and which transport is `capsule <name> ssh`'s question, not a
# recipe's (host/cli.nix).
#
# a shell in the guest as the agent — TUIs work here, not on the console. With a
# command it runs that instead, which is the only way to ask a capsule something
# without becoming a human reading a prompt: every capsule is the same image, so
# every one of them says `agent@capsule` and the prompt identifies nothing.
ssh name="" *cmd:
  @c={{quote(cmd)}}; if [ -z "$c" ]; then capsule {{name}} ssh; else capsule {{name}} ssh "$c"; fi

# root in the guest — admin from outside the jail; the agent has no path to it
admin name="" *cmd:
  @c={{quote(cmd)}}; if [ -z "$c" ]; then capsule {{name}} admin; else capsule {{name}} admin "$c"; fi

# a fresh capsule has fresh host keys at the same address, because they live on
# its volume — so the interactive paths above refuse. The programs don't: they
# check no keys at all and keep no record (host/guest-ssh.nix), deliberately.
reset-known-hosts name:
  #!/usr/bin/env bash
  set -euo pipefail
  if [ -S "/run/capsule/{{name}}/ssh.sock" ]; then
    ssh-keygen -R "capsule-{{name}}"
  else
    ssh-keygen -R "$(just _net guest)"
  fi

