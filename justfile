# capsule — firecracker agent jail. README.md is usage, docs/ is everything else.
#
# The **devshell** path's lifecycle (capsule-net, capsule-host, vm, vm-stop, and
# the git channel's capsule-provision / capsule-collect) comes from the devshell
# and is not wrapped here — each is already one command. What is here is the
# stuff that has no home otherwise: the pre-commit gate, the questions that need
# more than one command to answer, and the **module** path's lifecycle, which is
# three commands with two traps in them (`up` / `down` / `refresh`).

# Every nix file that is ours. Explicit, so nothing walks .direnv or .vm.
nix_paths := "flake.nix net.nix target.nix capsules.nix setup.nix perimeter host vm"

# addresses and ports come from net.nix or they drift
# --json, not --raw: the ports are integers and --raw refuses to coerce one
_net key:
  @nix eval --json --file net.nix {{key}} | tr -d '"'

# same for the repo under confinement — target.nix or it drifts
_target key:
  @nix eval --json --file target.nix {{key}} | tr -d '"'

# Run one of the four host programs at a capsule, with the copy that can reach
# it. Two copies of each exist by design — the devshell's goes straight over a
# tap, the module's crosses that capsule's relay socket — and inside the repo the
# devshell's shadow the module's on PATH, which is a timeout that reads as a dead
# guest (CLAUDE.md). The programs refuse rather than guess; a recipe is a human's
# front end, so choosing here is the same latitude `_guest-ssh` already takes.
_capsule prog name *args:
  #!/usr/bin/env bash
  set -euo pipefail
  bin={{prog}}
  if [ -S "/run/capsule/{{name}}/ssh.sock" ] \
     && [ -x "/run/current-system/sw/bin/{{prog}}" ]; then
    bin="/run/current-system/sw/bin/{{prog}}"
  fi
  exec "$bin" --capsule {{name}} {{args}}

# a capsule's quarantine, wherever this host keeps it: /var/lib/capsule (module
# path) or .vm/host. Same search order as the programs' own defaults.
_quarantine name="capsule":
  #!/usr/bin/env bash
  set -euo pipefail
  for state in "${CAPSULE_STATE:-}" /var/lib/capsule "${CAPSULE_ROOT:-$PWD}/.vm/host"; do
    [ -n "$state" ] && [ -d "$state/collect/{{name}}.git" ] \
      && { echo "$state/collect/{{name}}.git"; exit 0; }
  done
  echo "nothing collected yet — run capsule-collect --capsule {{name}}" >&2
  exit 1

# same question for the proxy's log
_proxy-log:
  #!/usr/bin/env bash
  set -euo pipefail
  for f in /var/lib/capsule-proxy/tinyproxy.log \
           "${CAPSULE_PROXY_STATE:-${CAPSULE_STATE:-${CAPSULE_ROOT:-$PWD}/.vm/host}}/tinyproxy.log"; do
    [ -f "$f" ] && { echo "$f"; exit 0; }
  done
  echo "no proxy log yet — start capsule-host or capsule-proxy" >&2
  exit 1

# the gate: everything parses and is formatted
default: check

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
# capsule-baseline exists only while the target declares a `baseline`; a target
# that omits it drops that line, and the build says so rather than skipping it.
build:
  nix build --no-link '.#capsule-host' '.#capsule-net' '.#vm-stop' '.#capsule-halt' \
    '.#probe-netns' '.#probe-netns-boot' '.#probe-freshness' \
    '.#probe-two-capsules' \
    '.#capsule-provision' '.#capsule-collect' '.#capsule-inject' \
    '.#capsule-baseline' '.#hostModuleUnits'

# which units the host module generates, without rebuilding a host — the only
# mechanical check the NixOS half has
units:
  @cat "$(nix build --no-link --print-out-paths '.#hostModuleUnits')"

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

# where microvm.nix keeps a created VM. `tap-up` is what both microvm@<name> and
# its tap unit are conditioned on, so its absence is what a missing create
# actually looks like — reported as a dependency failure naming neither (README).
microvms := "/var/lib/microvms"

# Starting is the whole capsule: the drop-ins pull its namespace in first, and
# the VM wants its proxy and its ssh relay.
#
# create if this host has never seen this capsule, then start it (root)
up name="capsule":
  #!/usr/bin/env bash
  set -euo pipefail
  tap=$(just _net tap)
  if ip link show "$tap" >/dev/null 2>&1; then
    echo "just up: refusing — $tap is in the root namespace, so the devshell" >&2
    echo "  shape is up. 'vm-stop' then 'capsule-net down' first: two" >&2
    echo "  perimeters over one guest is worse than one, not safer." >&2
    exit 1
  fi
  if [ -x "{{microvms}}/{{name}}/current/bin/tap-up" ]; then
    echo "{{name}}: created already"
  else
    # The flake ref carries no fragment: the CLI appends
    # #nixosConfigurations.<name>.config.microvm.declaredRunner itself, so a
    # fragment asks for that attribute *of* a package and reads as a missing
    # output. Root, for /var/lib/microvms and the gcroots.
    echo "{{name}}: never created on this host — creating"
    sudo microvm -c {{name}} -f "{{justfile_directory()}}"
  fi
  # A host rebuild that changes this unit's drop-ins does not reach a unit that
  # is already running or mid-restart: systemd keeps the loaded fragment and
  # only records NeedDaemonReload, and a reload cannot swap it while a job is
  # pending. What starts then is the *bare* microvm.nix template — Restart=always,
  # no namespace, the old ExecStop — so firecracker runs in the root namespace,
  # where its tap is not, and EPERMs in a five-second loop (CLAUDE.md: EPERM on
  # the tap means no tap). Stop first, reload while it is stopped, then start.
  if [ "$(systemctl show microvm@{{name}} -P NeedDaemonReload)" = yes ]; then
    echo "{{name}}: unit changed on disk since it was loaded — reloading first"
    sudo systemctl stop microvm@{{name}}
    sudo systemctl daemon-reload
  fi
  # `|| true` because the assertion below is the better error: it reports what
  # the VMM said rather than that a start returned nonzero.
  sudo systemctl start microvm@{{name}} || true
  # A start returns once the VMM is exec'd, and a VMM that cannot open its tap
  # is gone again in milliseconds — which is how a crash loop reads as a
  # successful `up`. So ask again, after long enough for that to have happened.
  sleep 2
  if [ "$(systemctl show microvm@{{name}} -P SubState)" != running ]; then
    echo "just up: {{name}} did not stay up —" >&2
    journalctl -u microvm@{{name}} -n 15 --no-pager -o cat >&2
    exit 1
  fi
  journalctl -u capsule-perimeter-guard -n 1 --no-pager -o cat 2>/dev/null || true

# Not a power cut: `capsule-halt` asks the guest to reboot, it unmounts and then
# its reset exits the VMM (notes item 11), and microvm.nix's own ExecStop blocks
# until that happens. The journal tail is the evidence — `reboot requested` and
# then a return, rather than 120 s of TimeoutStopSec.
#
# stop it cleanly, and show what the stop actually did (root)
down name="capsule":
  #!/usr/bin/env bash
  set -euo pipefail
  sudo systemctl stop microvm@{{name}}
  journalctl -u microvm@{{name}} -n 12 --no-pager -o cat 2>/dev/null || true

# Nothing reaches a created VM until its state directory is rebuilt, because
# that directory is what it tracks. Cleanly down first, so the update never
# lands under a mounted volume, and back up only if it was up.
#
# after a guest change: rebuild its state directory, restart if it was running
refresh name="capsule":
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

# VM, tap, listener, perimeter, quarantine, units — one screen
#
# Two shapes answer this differently and both are shown. On the devshell shape
# the tap and the proxy's listener are in the root namespace, where this can see
# them; on the module shape they are inside a capsule's namespace and this
# cannot, by construction — the namespaces and the sockets are what says a
# capsule is up.
status name="capsule":
  #!/usr/bin/env bash
  set -uo pipefail
  echo "== vm"
  pgrep -af 'microvm@' || echo "  no VM running"
  echo "== tap (devshell shape only — a namespaced tap is invisible from here)"
  ip -brief addr show "$(just _net tap)" 2>/dev/null || echo "  none in this namespace"
  echo "== listener (devshell shape only; only your own processes are named)"
  ss -lntp "sport = :$(just _net proxyPort)" 2>/dev/null | tail -n +2 || echo "  none"
  echo "== perimeter (devshell shape)"
  just verify 2>&1 | sed 's/^/  /'
  echo "== capsules (module shape)"
  ip netns list 2>/dev/null | grep '^cap-' | sed 's/^/  ns /' || echo "  no namespaces"
  for s in /run/capsule/*/ssh.sock; do
    [ -S "$s" ] && echo "  in $s"
  done
  echo "== units (module shape)"
  systemctl list-units --no-legend --no-pager 'capsule-*' 2>/dev/null \
    | awk '{printf "  %s: %s\n", $1, $3}' || true
  echo "== collected"
  q=$(just _quarantine {{name}} 2>/dev/null) \
    && echo "  $q ($(git --git-dir="$q" for-each-ref "refs/capsule/{{name}}/" | wc -l) refs)" \
    || echo "  nothing — capsule-collect --capsule {{name}}"

# The capsule comes first in every one of these, as everywhere else here, so
# `just provision capsule-b edge` cannot be read the other way round. The ref is
# not defaulted: `capsule-provision` refuses without one, and that refusal should
# have one home.
#
# push a ref into a capsule's checkout
provision name="capsule" ref="" *flags:
  @just _capsule capsule-provision {{name}} {{ref}} {{flags}}

# the non-git half: credentials and anything else setup.nix declares
inject name="capsule" *args:
  @just _capsule capsule-inject {{name}} {{args}}

# the target's own build-and-test in the guest, with its record on the volume
baseline name="capsule" *flags:
  @just _capsule capsule-baseline {{name}} {{flags}}

# what the capsule has produced, into this host's quarantine
collect name="capsule":
  @just _capsule capsule-collect {{name}}

# All three, in the only order they work in, which is also the order that makes
# a fresh capsule usable (docs/design.md's three setup problems). Ends attached
# to the baseline, so it finishes when the build does — Ctrl-C leaves that run
# going in the guest and `just baseline <name>` re-attaches.
#
# a fresh capsule to green: provision, inject, baseline
setup name="capsule" ref="":
  @just provision {{name}} {{ref}}
  @just inject {{name}}
  @just baseline {{name}}

# what a capsule has produced, as collected
branches name="capsule":
  @git --git-dir="$(just _quarantine {{name}})" for-each-ref \
    --sort=-committerdate \
    --format='%(objectname:short)  %(refname:short)  %(committerdate:relative)  %(subject)' \
    'refs/capsule/{{name}}/'

# the second step: quarantine -> the repo you work in, once you have looked
fetch name="capsule":
  git -C "${CAPSULE_REPO:-$(just _target path)}" fetch "$(just _quarantine {{name}})" \
    'refs/capsule/*:refs/capsule/*'

# What the host pays while capsules work — the question the withdrawn "16 GiB per
# capsule" left behind, since what binds at N is what capsules *touch*.
#
# A VMM is identified by its unit, never by its name: one image means every one of
# them is `microvm@capsule` in the process table, so `MainPID` of `microvm@<name>`
# is the only unprivileged answer that cannot pick the wrong sibling (CLAUDE.md).
# Everything read here is world-readable, so no root and no probe — this attaches
# to the real instances rather than booting throwaways, which is the one thing a
# probe must not do.
#
# Sampled to a file *and* summarised, because a figure whose only copy is
# terminal scrollback is not a figure (docs/probes.md). Ctrl-C ends it and prints
# the peaks; the TSV is what a figure gets quoted from.
#
# what the host pays while these capsules work: RSS per VMM, host pressure
load out=".vm/load.tsv" +names="capsule":
  #!/usr/bin/env bash
  set -uo pipefail
  mkdir -p "$(dirname {{out}})"
  read -ra names <<<"{{names}}"
  {
    printf 'elapsed\t'
    printf '%s_rss_mib\t' "${names[@]}"
    printf 'mem_avail_mib\tmem_some_avg10\tcpu_some_avg10\tio_some_avg10\n'
  } >{{out}}
  declare -A peak
  for n in "${names[@]}"; do peak[$n]=0; done
  peak_mem=0
  trap 'break' INT TERM
  start=$SECONDS
  while :; do
    row=$((SECONDS - start))
    line="$row"
    for n in "${names[@]}"; do
      pid=$(systemctl show "microvm@$n" -P MainPID)
      rss=0
      if [ "$pid" != 0 ] && [ -r "/proc/$pid/status" ]; then
        rss=$(( $(awk '/^VmRSS:/{print $2}' "/proc/$pid/status") / 1024 ))
      fi
      [ "$rss" -gt "${peak[$n]}" ] && peak[$n]=$rss
      line+=$'\t'"$rss"
    done
    avail=$(( $(awk '/^MemAvailable:/{print $2}' /proc/meminfo) / 1024 ))
    m=$(awk '/^some/{print $2}' /proc/pressure/memory | cut -d= -f2)
    c=$(awk '/^some/{print $2}' /proc/pressure/cpu | cut -d= -f2)
    i=$(awk '/^some/{print $2}' /proc/pressure/io | cut -d= -f2)
    # Pressure is the whole reason a peak can be trusted: a high-water mark taken
    # while the kernel was reclaiming is a floor, not a peak.
    awk -v m="$m" -v p="$peak_mem" 'BEGIN{exit !(m>p)}' && peak_mem=$m
    printf '%s\t%s\t%s\t%s\t%s\n' "$line" "$avail" "$m" "$c" "$i" >>{{out}}
    sleep 2
  done
  echo
  echo "peak RSS, MiB:"
  for n in "${names[@]}"; do printf '  %-12s %s\n' "$n" "${peak[$n]}"; done
  echo "peak memory pressure (some avg10): $peak_mem"
  echo "samples in {{out}} — quote figures from there, not from this screen"

# every egress attempt, live — unlisted hostnames show up here as denials
proxy-log:
  tail -f "$(just _proxy-log)"

# hostnames the proxy will resolve — a destination control, not an exfil one
allowed:
  @cat "${CAPSULE_ALLOWLIST:-$(just _target allowlist)}"

# a shell in the guest as the agent — TUIs work here, not on the console
ssh name="capsule":
  stty sane # in case echo got stuck on
  @just _guest-ssh agent {{name}}

# root in the guest — admin from outside the jail; the agent has no path to it
admin name="capsule":
  @just _guest-ssh root {{name}}

# One door, two transports. On the module shape the guest is not routable from
# here at all and the way in is the capsule's relay socket — which is also its
# identity, so `HostKeyAlias` files each capsule's host key under its own name
# instead of N capsules fighting over one address's entry. The interactive paths
# keep strict host-key checking on purpose: a human is present to read it.
_guest-ssh user name:
  #!/usr/bin/env bash
  set -euo pipefail
  guest=$(just _net guest)
  sock="/run/capsule/{{name}}/ssh.sock"
  if [ -S "$sock" ]; then
    exec ssh -o HostKeyAlias="capsule-{{name}}" \
      -o ProxyCommand="socat - UNIX-CONNECT:$sock" "{{user}}@$guest"
  fi
  exec ssh "{{user}}@$guest"

# a fresh capsule has fresh host keys at the same address, because they live on
# its volume — so the interactive paths above refuse. The programs don't: they
# check no keys at all and keep no record (host/guest-ssh.nix), deliberately.
reset-known-hosts name="capsule":
  #!/usr/bin/env bash
  set -euo pipefail
  if [ -S "/run/capsule/{{name}}/ssh.sock" ]; then
    ssh-keygen -R "capsule-{{name}}"
  else
    ssh-keygen -R "$(just _net guest)"
  fi
