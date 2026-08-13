# The namespace layer: what a capsule's network *is* on the host-module path.
#
# `probe/netns-egress.sh` built this by hand with `ip` and `nft` and asserted it
# 27 times (docs/probes.md). This is that run as units — same namespaces, same
# links, same three drops, same resolver. If a claim the probe makes stops
# holding once these units own the namespace, the units are wrong.
#
# Only the module path, never the devshell path: namespaces need root, and the
# convention that `capsule-net` + `capsule-host` work with no rebuild and no
# root is what makes the dev loop usable (plan-c-multi-capsule.md, "Where netns
# applies").
#
# What moves in here from `~/flakes`: the control the whole confinement rests on
# is now `ip_forward=0` **inside a namespace this module creates**, so nobody
# else writes it and there is no race to lose (NOTES item 7 inverts). What the
# host still owns is forwarding and NAT for the *proxies'* egress — nothing
# about a guest's confinement rests on it.
#
# Two programs rather than N generated scripts, with every per-capsule value in
# the unit's own `Environment=`: `systemctl cat` then shows the addressing of a
# boundary instead of a store path.
{
  pkgs,
  lib,
  net,
  capsules,
}: let
  inherit (capsules) egress uplinkNet;

  # Explicit paths: `nft` and `sysctl` are the two tools these units cannot
  # borrow from a PATH they do not have.
  nft = "${pkgs.nftables}/bin/nft";

  # Where iproute2 keeps a named namespace, and what `NetworkNamespacePath=`
  # wants. A convention of the tool, not a fact about capsules, so it is derived
  # here rather than in capsules.nix.
  nsPath = ns: "/var/run/netns/${ns}";

  # Loopback is per-namespace, so the host's stub on 127.0.0.53 is not in a
  # capsule — an inherited resolv.conf naming it resolves nothing. `ip netns
  # exec` bind-mounts this file over /etc/resolv.conf; **systemd does not**, so
  # a unit joined to the namespace has to be given it explicitly (see
  # host/services.nix).
  resolvConf = ns: "/etc/netns/${ns}/resolv.conf";

  # The one address a capsule may reach on this host: the resolver stub, on the
  # aggregator's host end. Anything else RFC1918 is dropped in the aggregator.
  resolver = egress.peerAddr;

  # ------------------------------------------------------------------ programs

  egressProgram = pkgs.writeShellApplication {
    name = "capsule-egress-ns";
    runtimeInputs = [pkgs.iproute2 pkgs.nftables pkgs.procps];
    text = ''
      # Values come from the unit's Environment=, deliberately: a boundary's
      # addressing should be readable in `systemctl cat`.
      ns=''${NS:?}
      dev=''${DEV:?}
      peer=''${PEER:?}
      addr=''${ADDR:?}
      peer_addr=''${PEER_ADDR:?}
      prefix=''${PREFIX:?}
      nets=''${UPLINK_NET:?}
      pattern=''${LINK_PATTERN:?}

      case "''${1:-}" in
        up)
          ip netns add "$ns"
          ip -n "$ns" link set lo up
          # It has to forward: it is the point every capsule's proxy leaves
          # through. Which is exactly what makes it a capsule-to-capsule path,
          # and why the pair drop below is not optional.
          ip netns exec "$ns" sysctl -q -w net.ipv4.ip_forward=1

          ip link add "$dev" type veth peer name "$peer"
          ip link set "$dev" netns "$ns"
          ip -n "$ns" addr add "$addr/$prefix" dev "$dev"
          ip -n "$ns" link set "$dev" up
          ip addr add "$peer_addr/$prefix" dev "$peer"
          ip link set "$peer" up
          ip netns exec "$ns" ip route add default via "$peer_addr"
          # One route for every capsule, present or future: the /30s are carved
          # out of this, so adding a capsule adds no host route.
          ip route add "$nets" via "$addr" dev "$peer"

          # Each rule was verified by deleting it and watching the wall fall
          # over (probe/netns-egress.sh, stage 4). The resolver is the one
          # RFC1918 destination a capsule may have and is allowed narrowly,
          # ahead of the broad drop — which is what makes the pair testable:
          # DNS works, a ping to the same address does not.
          ip netns exec "$ns" nft -f - <<EOF
      table ip capsule-egress {
        chain forward {
          type filter hook forward priority filter; policy accept;
          ip daddr $peer_addr udp dport 53 accept
          ip daddr $peer_addr tcp dport 53 accept
          iifname "$pattern" oifname "$pattern" drop
          ip saddr $nets ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } drop
        }
      }
      EOF
          ;;
        down)
          # Deleting either end of a veth takes both, and the host route with
          # it. The namespace goes last so nothing is half-torn-down if a
          # capsule is still attached — its own unit refuses in that case.
          ip link del "$peer" 2>/dev/null || true
          ip netns del "$ns" 2>/dev/null || true
          ;;
        *)
          echo "usage: capsule-egress-ns up|down" >&2
          exit 1
          ;;
      esac
    '';
  };

  capsuleProgram = pkgs.writeShellApplication {
    name = "capsule-netns";
    runtimeInputs = [pkgs.iproute2 pkgs.nftables pkgs.procps pkgs.gnugrep pkgs.coreutils];
    text = ''
      ns=''${NS:?}
      egress_ns=''${EGRESS_NS:?}
      tap=''${TAP:?}
      tap_addr=''${TAP_ADDR:?}
      dev=''${DEV:?}
      peer=''${PEER:?}
      addr=''${ADDR:?}
      gw=''${GW:?}
      prefix=''${PREFIX:?}
      uplink_prefix=''${UPLINK_PREFIX:?}
      resolver=''${RESOLVER:?}

      # A capsule's VMM cannot be found by name — one image means every one of
      # them is `microvm@capsule` in the process table — so the namespace is the
      # identity here as everywhere else (CLAUDE.md).
      vm_in_ns() {
        local pid cmd
        for pid in $(ip netns pids "$ns" 2>/dev/null); do
          cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null) || continue
          case $cmd in
            *microvm@*) return 0 ;;
          esac
        done
        return 1
      }

      case "''${1:-}" in
        up)
          ip netns add "$ns"
          ip -n "$ns" link set lo up
          # The whole confinement, in one sysctl that is *ours*: forwarding is
          # per-namespace, so docker and tailscale cannot flip this one. The
          # guest may hold a default route — guest root can always add one —
          # and still reach nothing but the proxy.
          ip netns exec "$ns" sysctl -q -w net.ipv4.ip_forward=0
          ip netns exec "$ns" sysctl -q -w net.ipv4.conf.all.forwarding=0

          install -d -m 0755 "/etc/netns/$ns"
          printf 'nameserver %s\n' "$resolver" >"/etc/netns/$ns/resolv.conf"

          ip link add "$dev" type veth peer name "$peer"
          ip link set "$dev" netns "$ns"
          ip link set "$peer" netns "$egress_ns"
          ip -n "$ns" addr add "$addr/$uplink_prefix" dev "$dev"
          ip -n "$egress_ns" addr add "$gw/$uplink_prefix" dev "$peer"
          ip -n "$ns" link set "$dev" up
          ip -n "$egress_ns" link set "$peer" up
          ip netns exec "$ns" ip route add default via "$gw"

          # The proxy's way out is a *local* address of this namespace, so a
          # packet from the guest to it is INPUT and no forwarding switch
          # touches it (probe/netns.sh, cost 1). Services bind the tap address;
          # anything else arriving on the tap is not for them. `iifname` is a
          # string match, so this rule is loadable before the tap exists — which
          # it must be, since microvm.nix creates the tap later and inside here.
          ip netns exec "$ns" nft -f - <<EOF
      table ip capsule-guard {
        chain input {
          type filter hook input priority filter; policy accept;
          iifname "$tap" ip daddr != $tap_addr drop
        }
      }
      EOF
          ;;
        addr)
          # Runs *inside* the namespace, as ExecStartPost on microvm.nix's own
          # tap unit: it creates the tap and brings it up but knows nothing
          # about addresses, and the address cannot be assigned before the tap
          # exists. No `ip netns exec` here — the unit is already joined.
          ip addr add "$tap_addr/$prefix" dev "$tap"
          # So the tap never carries an IPv6 the guest's side could talk to.
          sysctl -q -w "net.ipv6.conf.$tap.disable_ipv6=1" 2>/dev/null || true
          ;;
        down)
          if ip netns list | grep -qw "$ns"; then
            # Deleting the namespace takes the tap with it, and a tap cannot be
            # swapped under a running VM: the fd survives, the netdev does not,
            # and the guest goes silent with `No route to host` (CLAUDE.md).
            # Ordering should have stopped the VMM first; if it did not, say so
            # rather than cutting the power quietly.
            if vm_in_ns; then
              echo "capsule-netns: $ns still has a VMM in it — refusing to" >&2
              echo "  delete the namespace. Stop microvm@<name> first." >&2
              exit 1
            fi
            ip netns del "$ns"
          fi
          rm -f "/etc/netns/$ns/resolv.conf"
          rmdir "/etc/netns/$ns" 2>/dev/null || true
          ;;
        *)
          echo "usage: capsule-netns up|addr|down" >&2
          exit 1
          ;;
      esac
    '';
  };

  # ----------------------------------------------------------------- the check
  #
  # What the guard asks, every cycle. There is no `latent` state any more: these
  # namespaces are this module's own, so an answer it cannot read is a fault and
  # not somebody else's config being unreadable. Unverifiable is a refusal.
  check = ''
    # Asked without a verdict attached, because absence is a question with two
    # answers now: for the aggregator it is a fault, for a declared slot that
    # never came up it is nothing at all (NOTES item 30). One definition of
    # "exists" under both.
    ns_exists() {
      ip netns list | grep -qw "$1"
    }

    ns_present() {
      ns_exists "$1" || {
        echo "  namespace $1 is gone" >&2
        return 1
      }
    }

    ns_not_forwarding() {
      local v
      v=$(ip netns exec "$1" sysctl -n net.ipv4.ip_forward 2>/dev/null) || {
        echo "  cannot read ip_forward in $1" >&2
        return 1
      }
      [ "$v" = 0 ] || {
        echo "  net.ipv4.ip_forward is $v in $1 — the guest's confinement is gone" >&2
        return 1
      }
    }

    # **Limb two of the guard's invariant, not a companion check** (NOTES item
    # 30): a running capsule's VMM is in *its own* namespace. Limb one — every
    # declared-and-present namespace passes its audit — is only safe to apply to
    # a subset of the declared slots because of this one, so the two are stated
    # together or the skip is unsound.
    #
    # What it closes: `ip netns del` removes the *name*, not the namespace, which
    # lives on as long as a process holds it. So a guest can be running inside a
    # namespace that is no longer named — declared, absent, and dangerous, which
    # is exactly where "absent, skip it" would be wrong. Nothing can ask a scoped
    # question about a nameless namespace, so ask about the process instead: an
    # active unit whose namespace has no name refuses here.
    #
    # Per slot rather than membership of the union, which also catches a VMM
    # bound to the wrong namespace — `microvm@a` living in `cap-b` is a slot's
    # guest behind another slot's perimeter, and a union test calls that fine.
    #
    # `ip netns pids` rather than `/proc/<pid>/ns/net` against a bind-mount's
    # inode: the kernel is being asked the same question either way, and this is
    # the tool the rest of this file already uses.
    vm_in_ns() {
      local name=$1 ns=$2 unit="microvm@$1.service" pid pids
      systemctl is-active --quiet "$unit" || return 0
      pid=$(systemctl show -P MainPID "$unit" 2>/dev/null) || pid=""
      [ -n "$pid" ] && [ "$pid" != 0 ] || {
        echo "  $unit is active with no MainPID — nothing can say where its guest is" >&2
        return 1
      }
      pids=$(ip netns pids "$ns" 2>/dev/null) || {
        echo "  $unit is running and $ns is not a named namespace — its perimeter cannot be read" >&2
        return 1
      }
      grep -qxF "$pid" <<<"$pids" || {
        echo "  $unit (pid $pid) is not in $ns — a VMM's namespace is its identity" >&2
        return 1
      }
    }

    # Fixed-string matches against nft's own rendering. Fail-closed: a rule this
    # cannot find is treated as absent.
    ns_rule() {
      local ns=$1 table=$2 want=$3 rules
      rules=$(ip netns exec "$ns" ${nft} list table ip "$table" 2>/dev/null) || {
        echo "  table $table is not loaded in $ns" >&2
        return 1
      }
      grep -qF -- "$want" <<<"$rules" || {
        echo "  $ns/$table has no rule matching: $want" >&2
        return 1
      }
    }
  '';
in {
  inherit nsPath resolvConf resolver check;

  programs = {
    egress = egressProgram;
    capsule = capsuleProgram;
  };

  # The environment each program's unit carries — one place, so a unit and the
  # program it runs cannot disagree about what a capsule is called.
  egressEnv = {
    NS = egress.ns;
    DEV = egress.dev;
    PEER = egress.peer;
    ADDR = egress.addr;
    PEER_ADDR = egress.peerAddr;
    PREFIX = toString egress.prefix;
    UPLINK_NET = uplinkNet;
    LINK_PATTERN = egress.linkPattern;
  };

  capsuleEnv = c: {
    NS = c.ns;
    EGRESS_NS = egress.ns;
    TAP = net.tap;
    TAP_ADDR = net.host;
    PREFIX = toString net.prefix;
    DEV = c.uplink.dev;
    PEER = c.uplink.peer;
    ADDR = c.uplink.addr;
    GW = c.uplink.gw;
    UPLINK_PREFIX = toString c.uplink.prefix;
    RESOLVER = resolver;
  };

  # Host-side, and none of it about a guest: the proxies' egress. NAT rather
  # than a route back, so nothing upstream needs to know these networks exist.
  hostConfig = {
    boot.kernel.sysctl."net.ipv4.ip_forward" = true;

    networking.nftables.enable = lib.mkDefault true;
    networking.nftables.tables.capsule-nat = {
      family = "ip";
      content = ''
        chain post {
          type nat hook postrouting priority srcnat; policy accept;
          ip saddr ${uplinkNet} oifname != "${egress.peer}" masquerade
        }
      '';
    };

    # The stub the capsules resolve against, on the host end of the
    # aggregator's link. Without it a capsule has no resolver at all, and the
    # tempting fix — a public nameserver in /etc/netns/<ns>/resolv.conf —
    # silently drops the host's own resolved -> stubby -> DoT chain, which is
    # most of what NOTES item 7 built.
    services.resolved.settings.Resolve.DNSStubListenerExtra = resolver;
    networking.firewall.interfaces.${egress.peer} = {
      allowedUDPPorts = [53];
      allowedTCPPorts = [53];
    };
  };
}
