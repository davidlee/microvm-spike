# Is the host-side half of the perimeter actually loaded? Part of it lives in
# the host's NixOS config (README "Host requirements") where nothing here can
# see it declared — so it gets read out of the running kernel instead.
#
# Linux-shaped, hence outside `perimeter/`: it is injected into the
# jail-agnostic perimeter as `preflight` + `watch`, never imported by it.
#
# Two callers with different privilege, one definition: `capsule-host` run by
# hand reads the ruleset through a NOPASSWD sudo rule, the systemd units read
# it directly as root. Hence `nft` is the whole command, not a path.
{
  net,
  nft,
}: ''
  # The services bind ${net.host}, which only exists while the tap does.
  tap_up() {
    ip -brief addr show ${net.tap} 2>/dev/null | grep -q ${net.host}
  }

  # Reading the ruleset needs CAP_NET_ADMIN. No answer is not a pass — see
  # perimeter_state.
  forward_dropped() {
    local rules
    rules=$(${nft} list table inet capsule-forward 2>/dev/null) || return 1
    grep -q 'iifname "${net.tap}" drop' <<< "$rules" &&
      grep -q 'oifname "${net.tap}" drop' <<< "$rules"
  }

  # Without the drop, the whole guarantee rests on the host not forwarding at
  # all — global state neither this repo nor the host config owns, since docker
  # and tailscale each turn it on for their own reasons.
  forwarding_off() {
    local forwarding
    read -r forwarding < /proc/sys/net/ipv4/ip_forward
    [ "$forwarding" = 0 ]
  }

  # dropped: verified. latent: nothing forwards today, but the control is
  # missing or unreadable, so it is one `systemctl start docker` from gone.
  # open: a guest that gains root can add a default route and reach the LAN
  # past the proxy, now.
  perimeter_state() {
    if forward_dropped; then
      echo dropped
    elif forwarding_off; then
      echo latent
    else
      echo open
    fi
  }

  perimeter_advice() {
    echo "  the FORWARD drop on ${net.tap} cannot be verified — either it is" >&2
    echo "  missing from the host's NixOS config, or nft is not readable here." >&2
    echo "  See README 'Host requirements'." >&2
  }
''
