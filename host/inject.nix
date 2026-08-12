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
#
# Jail-agnostic in the same sense as `perimeter/` and `git-channel.nix`: it knows
# an ssh destination and the argv that reaches it, and nothing about taps,
# namespaces or hypervisors. Under netns only `sshArgs` changes, at the call
# site.
{
  pkgs,
  # Where to ssh, e.g. `agent@10.99.0.2`. Jail-shaped, so injected.
  guestHost,
  # How to ssh, as argv — a list, not a string. The netns form carries a
  # ProxyCommand with spaces inside it, and a string would have to be re-split
  # by a shell that cannot know where the quoting was meant to go.
  sshArgs ? ["ssh"],
  # [{name, dest, produce, tools}] — ./setup.nix, with `tools` already resolved
  # to packages by the call site.
  injections,
}: let
  inherit (pkgs) lib;

  # One block per declared payload. The produce fragment is the entry's, so it
  # is spliced rather than parameterised: a payload is a program, not a value.
  step = i: ''
    if wanted ${lib.escapeShellArg i.name}; then
      tmp="$tmpdir"/${lib.escapeShellArg i.name}
      {
        ${i.produce}
      } > "$tmp"
      push ${lib.escapeShellArg i.name} ${lib.escapeShellArg i.dest} \
        ${lib.escapeShellArg (builtins.dirOf i.dest)} "$tmp"
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

      ssh_cmd=(${lib.escapeShellArgs sshArgs})
      host=${lib.escapeShellArg guestHost}

      force=""
      selected=()
      for arg in "$@"; do
        case "$arg" in
          --force) force=1 ;;
          -*)
            echo "usage: capsule-inject [name...] [--force]" >&2
            echo "  no names: every declared payload (./setup.nix)." >&2
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

      # The destination directory is resolved at build time rather than with a
      # remote `dirname`: it is a declared path, so it is known here, and the
      # guest end stays one shell command with nothing to quote twice.
      push() {
        local name=$1 dest=$2 dir=$3 file=$4 bytes
        bytes=$(wc -c < "$file")
        # A filter that matched nothing writes an empty file, and an empty
        # credential replaces a working one with nothing. Refused here rather
        # than in every entry, because every entry would forget.
        if [ "$bytes" -lt 2 ]; then
          echo "capsule-inject: $name produced $bytes bytes — refusing to push it" >&2
          exit 1
        fi

        # Not a merge, and not an overwrite either. A capsule's copy diverges
        # from this host's the moment the agent uses it — these are two copies
        # of a credential, not one shared file — so replacing one is a decision
        # rather than a default. See docs/design.md.
        if [ -z "$force" ] && "''${ssh_cmd[@]}" "$host" "test -e '$dest'"; then
          echo "capsule-inject: $name: $dest is already there — skipped."
          echo "  'capsule-inject $name --force' to replace it, which discards"
          echo "  whatever the capsule has written into it since."
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
