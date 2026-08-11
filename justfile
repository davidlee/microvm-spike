# capsule — firecracker agent jail. README.md is usage, NOTES.md is rationale.
#
# The lifecycle commands (capsule-net, capsule-host, vm, vm-stop, capsule-sync)
# come from the devshell and are not wrapped here. What is here is the stuff
# that has no home otherwise: the pre-commit gate, and the questions that need
# more than one command to answer.

# Every nix file that is ours. Explicit, so nothing walks .direnv or .vm.
nix_paths := "flake.nix net.nix target.nix perimeter host vm"

# addresses and ports come from net.nix or they drift
# --json, not --raw: the ports are integers and --raw refuses to coerce one
_net key:
  @nix eval --json --file net.nix {{key}} | tr -d '"'

# same for the repo under confinement — target.nix or it drifts
_target key:
  @nix eval --json --file target.nix {{key}} | tr -d '"'

# the mirror, wherever this host keeps it: /var/lib/capsule (units) or .vm/host
_mirror:
  #!/usr/bin/env bash
  set -euo pipefail
  src="${CAPSULE_REPO:-$(just _target path)}"
  name="$(basename "$src").git"
  for state in "${CAPSULE_STATE:-}" /var/lib/capsule "${CAPSULE_ROOT:-$PWD}/.vm/host"; do
    [ -n "$state" ] && [ -d "$state/$name" ] && { echo "$state/$name"; exit 0; }
  done
  echo "no mirror yet — run capsule-sync" >&2
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

# the host-side scripts — shellcheck runs at build, so this is the real lint
build:
  nix build --no-link '.#capsule-host' '.#capsule-sync' '.#capsule-net' '.#vm-stop' '.#probe-netns'

# the guest closure and its runner — the slow one
build-vm:
  nix build --no-link '.#capsule'

# is the host-side perimeter loaded? dropped / latent / open
verify:
  capsule-net verify

# VM, tap, listeners, perimeter, mirror, units — one screen
status:
  #!/usr/bin/env bash
  set -uo pipefail
  echo "== vm"
  pgrep -af 'microvm@' || echo "  no VM running"
  echo "== tap"
  ip -brief addr show "$(just _net tap)" 2>/dev/null || echo "  no tap — capsule-net up"
  echo "== listeners (only your own processes are named)"
  ss -lntp "sport = :$(just _net proxyPort)" "sport = :$(just _net gitPort)" 2>/dev/null | tail -n +2 \
    || echo "  none"
  echo "== perimeter"
  just verify 2>&1 | sed 's/^/  /'
  echo "== units (unit path only)"
  for u in capsule-perimeter-guard capsule-proxy capsule-gitd; do
    state=$(systemctl is-active "$u" 2>/dev/null || true)
    [ -n "$state" ] && [ "$state" != inactive ] && echo "  $u: $state"
  done
  echo "== mirror"
  mirror=$(just _mirror 2>/dev/null) \
    && echo "  $mirror ($(git --git-dir="$mirror" for-each-ref 'refs/heads/capsule/*' | wc -l) capsule/* refs)" \
    || echo "  none — capsule-sync"

# what the guest has pushed
branches:
  @git --git-dir="$(just _mirror)" for-each-ref \
    --sort=-committerdate \
    --format='%(refname:short)  %(committerdate:relative)  %(subject)' \
    'refs/heads/capsule/*'

# collect the guest's work into the target repo
fetch:
  git -C "${CAPSULE_REPO:-$(just _target path)}" fetch "$(just _mirror)" \
    'refs/heads/capsule/*:refs/heads/capsule/*'

# every egress attempt, live — unlisted hostnames show up here as denials
proxy-log:
  tail -f "$(just _proxy-log)"

# hostnames the proxy will resolve — a destination control, not an exfil one
allowed:
  @cat "${CAPSULE_ALLOWLIST:-$(just _target allowlist)}"

# a shell in the guest as the agent — TUIs work here, not on the console
ssh:
  ssh "agent@$(just _net guest)"

# root in the guest — admin from outside the jail; the agent has no path to it
admin:
  ssh "root@$(just _net guest)"
