# capsule — firecracker agent jail. README.md is usage, docs/ is everything else.
#
# The lifecycle commands (capsule-net, capsule-host, vm, vm-stop, and the git
# channel's capsule-provision / capsule-collect) come from the devshell and are
# not wrapped here. What is here is the stuff
# that has no home otherwise: the pre-commit gate, and the questions that need
# more than one command to answer.

# Every nix file that is ours. Explicit, so nothing walks .direnv or .vm.
nix_paths := "flake.nix net.nix target.nix capsules.nix setup.nix perimeter host vm"

# addresses and ports come from net.nix or they drift
# --json, not --raw: the ports are integers and --raw refuses to coerce one
_net key:
  @nix eval --json --file net.nix {{key}} | tr -d '"'

# same for the repo under confinement — target.nix or it drifts
_target key:
  @nix eval --json --file target.nix {{key}} | tr -d '"'

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
