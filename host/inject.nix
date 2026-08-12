# Non-git provisioning, host-initiated: the third thing a fresh capsule needs,
# after its history and its static config (docs/design.md, "Capsule-only
# setup"). It pushes an explicit list of declared payloads over the ssh channel
# that already exists, as the human.
#
# Two properties it exists to keep:
#
#   - **Nothing whole leaves the host.** Each entry brings its own `produce`, a
#     host-side fragment that writes the payload to stdout. The selection is the
#     declaration's, so this program never learns what a credential looks like —
#     no filename, no format, no key name appears below. Copying a whole
#     `~/.claude.json` in would hand the capsule every project's history along
#     with the token.
#   - **It is a push.** Nothing listens, the guest cannot ask for any of this,
#     and it runs as you — the same seam as `capsule-provision`, and the reason
#     NOTES item 18's inversion deleted the port this used to want.
#   - **It is idempotent, and safe to run at every start.** Write-if-absent per
#     payload, so `capsule <name> start` runs the whole list (host/cli.nix) and a
#     restarted capsule keeps what it has. That is what makes a declared payload
#     something a human does not have to remember N times.
#
# Jail-agnostic in the same sense as `perimeter/` and `git-channel.nix`: it knows
# an ssh destination and a fragment that reaches it, and nothing about taps,
# namespaces or hypervisors. Under netns only `transport` changes, at the call
# site.
{
  pkgs,
  # Where to ssh, e.g. `agent@10.99.0.2`. Jail-shaped, so injected.
  guestHost,
  # Which capsule, and how to reach it: a shell fragment that sets `$capsule` and
  # the `ssh_cmd` argv, and consumes `--capsule` out of `"$@"` before the loop
  # below sees it (host/guest-ssh.nix). Argv rather than a string because the
  # netns form carries a ProxyCommand with spaces inside it. Jail-shaped, so
  # injected — and required, since without it this program has no capsule.
  transport,
  # [{name, dest, produce, tools, optional ? false}] — ./setup.nix, with `tools`
  # already resolved to packages by the call site.
  injections,
}: let
  inherit (pkgs) lib;

  # One block per declared payload, and the only thing that varies between two
  # of them is what `produce` is and whether a missing source is fatal. The
  # fragment is spliced as a *function body* rather than parameterised, because a
  # payload is a program and not a value — and defining it here rather than
  # inlining it at the push is what keeps one copy of the control flow below for
  # every entry. Its consequence, which is why `offer` is the caller: a fragment
  # sees the environment and `$capsule`, not argv.
  step = i: ''
    if wanted ${lib.escapeShellArg i.name}; then
      produce() {
        ${i.produce}
      }
      offer ${lib.escapeShellArg i.name} ${lib.escapeShellArg i.dest} \
        ${lib.escapeShellArg (builtins.dirOf i.dest)} \
        ${
      if i.optional or false
      then "optional"
      else "required"
    }
    fi
  '';
in
  pkgs.writeShellApplication {
    name = "capsule-inject";
    runtimeInputs =
      [pkgs.openssh pkgs.coreutils]
      ++ lib.concatMap (i: i.tools) injections;
    text = ''
      # Payloads land on this host's disk on the way past. They are readable by
      # you and by nobody else, for the whole run.
      umask 077

      ${transport}
      host=${lib.escapeShellArg guestHost}

      force=""
      selected=()
      for arg in "$@"; do
        case "$arg" in
          --force) force=1 ;;
          -*)
            echo "usage: capsule-inject [--capsule <name>] [payload...] [--force]" >&2
            echo "  no payload named: every declared one (./setup.nix)." >&2
            exit 1
            ;;
          *) selected+=("$arg") ;;
        esac
      done

      wanted() {
        if [ ''${#selected[@]} -eq 0 ]; then return 0; fi
        local n
        for n in "''${selected[@]}"; do
          if [ "$n" = "$1" ]; then return 0; fi
        done
        return 1
      }

      tmpdir=$(mktemp -d)
      trap 'rm -rf "$tmpdir"' EXIT

      # Produce one payload and push it, or say why it did not go. The
      # destination directory is resolved at build time rather than with a remote
      # `dirname`: it is a declared path, so it is known here, and the guest end
      # stays one shell command with nothing to quote twice.
      offer() {
        local name=$1 dest=$2 dir=$3 kind=$4 file bytes=0
        file="$tmpdir/$name"

        # Absence and emptiness are one fact: a source that is not on this host
        # and a filter that matched nothing both mean there is no payload here,
        # and pushing what came of either replaces a working credential with
        # nothing. So neither is ever pushed, and the only question left is
        # whether it is a failure — which the declaration answers, once, rather
        # than every entry answering it and one of them forgetting.
        if produce > "$file"; then bytes=$(wc -c < "$file"); fi
        if [ "$bytes" -lt 2 ]; then
          if [ "$kind" = optional ]; then
            echo "capsule-inject: $name: nothing to produce on this host — skipped."
            return 0
          fi
          echo "capsule-inject: $name: produced nothing — refusing to push it" >&2
          exit 1
        fi

        # Not a merge, and not an overwrite either. A capsule's copy diverges
        # from this host's the moment the agent uses it — these are two copies
        # of a credential, not one shared file — so replacing one is a decision
        # rather than a default. See docs/design.md.
        if [ -z "$force" ] && "''${ssh_cmd[@]}" "$host" "test -e '$dest'"; then
          echo "capsule-inject: $name: $dest is already there — skipped ('capsule-inject" \
            "$name --force' replaces it, discarding what the capsule wrote since)."
          return 0
        fi

        # Written aside and moved, so a dropped connection cannot leave half a
        # credential behind that still parses.
        "''${ssh_cmd[@]}" "$host" \
          "umask 077; mkdir -p '$dir' && cat > '$dest.new' && mv '$dest.new' '$dest'" \
          < "$file"
        echo "capsule-inject: $name -> $dest ($bytes bytes)"
      }

      ${lib.concatMapStrings step injections}
    '';
  }
