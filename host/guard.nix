# The perimeter guard: one program, and the only thing on this host that can see
# inside a capsule's namespace.
#
# Its own file rather than a block in `host/services.nix` for one reason, and it
# is the same reason `transport` is an argument: **`tools` is injected, so the
# same text can be built against stubs.** `writeShellApplication` prepends
# `runtimeInputs` to `PATH`, so a test that stubs `ip` or `systemctl` cannot win
# by prepending its own — the tools have to come from the outside or the program
# is untestable without a live host. `flake.nix`'s `guardCases` builds this with
# stubs and asserts the verdicts; `host/services.nix` builds it with the real
# ones and gives it a unit. One construction, two tool sets, no second copy of an
# invariant.
#
# One guard for every capsule, and it holds all of them: a `BindsTo` that only
# tears some of them down is worse than no guard, because the survivors look
# healthy. Every question is asked of the running kernel in the namespace that
# owns the answer — see host/netns.nix for why there is no `latent` state left.
#
# **It holds one invariant with two limbs** (NOTES item 30), and they are only
# sound together:
#
#   1. every declared-and-present namespace passes its perimeter audit; and
#   2. every running capsule's VMM is inside *its own* declared namespace.
#
# So the audit set is declared ∩ present. A declared slot whose namespace does
# not exist is skipped — a slot with no namespace can hold no guest and no
# egress, because its VMM unit carries `NetworkNamespacePath` and its tap unit
# `requires` the namespace, so a broken slot fails as itself. Limb two is what
# makes that skip *sound* rather than merely cheap: unnaming a namespace does not
# destroy it, so without limb two the algorithm would say "absent, skip" in
# precisely the case where a guest is still running in there.
#
# A namespace that *is* present and wrong remains the whole host's problem:
# absence is capacity that does not exist, breakage is a breach, and only the
# second is fleet-wide. Which is why this is not a mode — there is no boolean, no
# override and no second path. One invariant over the resources that exist, and
# capacity that happens to be less than what is declared.
#
# The intersection is with the *declared* names, never with every `cap-*` that
# exists: a probe's namespace is `cap-capsule` (NOTES item 28), so enumerating by
# prefix would audit a probe, find no `capsule-guard` table in it, and tear the
# live fleet's egress down.
{
  pkgs,
  lib,
  net,
  capsules,
  # host/netns.nix, for `check` — the helpers that ask a namespace the questions.
  netns,
  # What the program finds on `PATH`. The real set is iproute2, procps (for the
  # `sysctl` inside `ip netns exec`), grep, coreutils and systemd — the last
  # because whether a slot's VMM unit is running is a question only systemd can
  # answer, and the guard is already a unit.
  tools,
}: let
  instances = lib.attrValues capsules.instances;
  inherit (capsules) egress;
in
  pkgs.writeShellApplication {
    name = "capsule-perimeter-guard";
    runtimeInputs = tools;
    text = ''
      ${netns.check}

      # `name:namespace` pairs, because both limbs of the invariant are asked per
      # slot and index-aligned arrays are a bug waiting for a deleted line.
      declared=(${lib.concatMapStringsSep " " (c: ''"${c.name}:${c.ns}"'') instances})
      # Set by every `audit`, read by the report: the slots that existed to be
      # audited this cycle, which is the number a human needs to see a pool
      # running degraded.
      audited=()

      audit() {
        local slot name ns bad=0

        audited=()

        ns_present "${egress.ns}" || bad=1
        # Capsule to capsule, and capsule to the host's own networks. The
        # resolver is allowed narrowly ahead of the second one, which is what
        # makes the pair testable: DNS works, a ping to the same address does
        # not.
        ns_rule "${egress.ns}" capsule-egress \
          'iifname "${egress.linkPattern}" oifname "${egress.linkPattern}" drop' || bad=1
        ns_rule "${egress.ns}" capsule-egress \
          'ip saddr ${capsules.uplinkNet}' || bad=1

        for slot in "''${declared[@]}"; do
          name=''${slot%%:*}
          ns=''${slot#*:}

          # Limb two first, because it is what licenses the skip below: a slot
          # whose unit is running must be *in* its namespace, so an unnamed
          # namespace with a live guest refuses here rather than reading as
          # absent (host/netns.nix).
          vm_in_ns "$name" "$ns" || bad=1

          # Absent is not a verdict. `ns_exists` rather than `ns_present` for
          # exactly that: the second one says "is gone", which is true of the
          # aggregator and meaningless of a slot nobody started.
          ns_exists "$ns" || continue
          audited+=("$ns")
          ns_not_forwarding "$ns" || bad=1
          # The guest reaching a service in its own namespace is INPUT, not
          # forward, so no forwarding switch covers it (probe/netns.sh, cost 1).
          ns_rule "$ns" capsule-guard \
            'iifname "${net.tap}" ip daddr != ${net.host} drop' || bad=1
        done

        return "$bad"
      }

      report() {
        echo "capsule-perimeter-guard: ''${#audited[@]} of ${toString (builtins.length instances)} declared capsule namespace(s) verified"
      }

      if ! audit; then
        echo "capsule-perimeter-guard: refusing — the perimeter above is not intact." >&2
        exit 1
      fi
      report
      reported=''${#audited[@]}

      # BindsTo on every proxy, so exiting takes their egress with it. A
      # preflight alone would only prove the perimeter held at start.
      while sleep 10; do
        audit || {
          echo "capsule-perimeter-guard: the perimeter changed under us. Tearing down egress." >&2
          exit 1
        }
        # A slot arriving or leaving is not a fault, and it is the one thing a
        # silent loop would hide — a pool that came up eight of ten reads as
        # healthy for as long as nobody counts.
        [ "''${#audited[@]}" = "$reported" ] || {
          report
          reported=''${#audited[@]}
        }
      done
    '';
  }
