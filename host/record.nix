# The assignment record — what a slot is currently *supposed* to be.
# [docs/contract-assignment.md](../docs/contract-assignment.md) owns the field
# list and the authority split; this file is only the mechanism, and it is
# deliberately a shell fragment rather than a program.
#
# **Why a fragment.** Two things write a record and one reads it, and they are
# already separate store paths for reasons that have nothing to do with records:
# `capsule` carries no transport (host/cli.nix) and `capsule-provision` carries
# one and exists in two copies (host/programs.nix). A record *library* injected
# into each is one definition of the path, the locking and the generation; a
# record *program* would be a fifth thing to install and would still need the
# same fragment to call it. Same seam as `transport` and `statePaths`, same
# reason.
#
# **Desired state only.** Nothing observed goes in here — no head sha, no
# baseline verdict, no disk. Those are measured per call (host/observe.nix), and
# keeping the two apart is most of the value of writing the contract down: a
# record that mixes them cannot answer *is this slot doing what it was told*.
{pkgs}: {
  # Callers add these to their own `runtimeInputs`, so the dependency is visible
  # at each call site rather than assumed.
  inputs = [pkgs.jq pkgs.util-linux pkgs.coreutils];

  # Expects `$recordRoot` in scope — the state root the record lives under.
  # Deliberately **not** `$state`, the name `statePaths` uses: `quarantineOf` in
  # host/cli.nix already has a `local state` as a loop variable, and one of the two
  # callers there would have silently shadowed the other. A fragment injected into
  # somebody else's scope should not take a name that scope already uses.
  fragment = ''
    # `<root>/slot/<name>/`, not `<root>/<name>/` as the contract's prose has it.
    # The state root already holds `collect/`, and `capsules.nix` would accept a
    # slot called `collect` — an 11-character limit is the only name rule there
    # is. One namespacing directory is a structural fix; a list of reserved words
    # that grows every time this repo adds a state directory is not.
    slotDir() { printf '%s/slot/%s' "$recordRoot" "$1"; }
    recordOf() { printf '%s/assignment.json' "$(slotDir "$1")"; }

    # A slot nothing has assigned reads as `{}` rather than as an error: never
    # having been assigned is a state, and the field accessor below turns it into
    # `-` per field. `unassigned` in the contract's state model is exactly this.
    recordRead() { cat "$(recordOf "$1")" 2>/dev/null || echo '{}'; }

    # One field, `-` when absent or null, for a status column. `--arg` rather
    # than string interpolation because a field name reaching jq as code is the
    # same class of mistake as a path reaching a shell as code.
    recordField() {
      recordRead "$1" | jq -r --arg f "$2" '(.[$f] // "-") | if type == "array" then (if length == 0 then "-" else join(",") end) else tostring end'
    }

    # Mutate under `flock`, read-modify-write, and the generation bumped by the
    # write itself rather than by the caller — a caller that computes the next
    # generation is a caller that can compute it wrong, and every mutation bumps
    # it (docs/contract-assignment.md).
    #
    # The lock makes read-modify-write atomic, which is the whole of the
    # concurrency discipline this size of problem warrants. What it does *not* do
    # is the other half of what `generation` is for: **a command that acts on a
    # slot should state the generation it is acting for and be refused if that is
    # not current.** That matters once anything detached exists (Plan D D6) and
    # there is nothing to refuse today, so the field is written and the check is
    # not built — which is the right order, because retrofitting the field would
    # mean rewriting every record and retrofitting the check means adding an
    # argument.
    #
    # Written aside and moved, the same discipline `capsule-inject` uses on a
    # credential: a dropped write must not leave half a document that still
    # parses.
    # The locked section is a subshell with the lock on its own fd rather than
    # `exec 9>` in the function, so the descriptor and the variables both go away
    # when it does — a lock held for the rest of the program's life is a lock
    # nobody remembers taking.
    # `recordWrite <slot> <filter> [jq args…]` — anything after the filter is
    # passed to jq, which is how a value reaches it. **Never interpolate a value
    # into the filter**: free text like `purpose` would then be jq code, the same
    # class of mistake as a path reaching a shell as code, and `purpose` is
    # explicitly whatever a client puts in it.
    recordWrite() {
      local n="$1" filter="$2" dir
      shift 2
      dir=$(slotDir "$n")
      mkdir -p "$dir"
      (
        flock 9
        cur=$(cat "$dir/assignment.json" 2>/dev/null || echo '{}')
        gen=$(printf '%s' "$cur" | jq -r '.generation // 0')
        next=$((gen + 1))
        tmp="$dir/.assignment.json.$$"
        # Three things are appended *after* the caller's filter: the absent-field
        # skeleton, then `generation` and `schema` — so no caller can spell either
        # of the last two and have it survive, and none of them can be forgotten
        # by a caller who only meant to set one field.
        #
        # The absent four are written as absent rather than omitted, so a record
        # says for itself which half of the contract is built. Each waits on a
        # different mechanism: `policy` on a declared set to select from,
        # `extras` and `image` on a fragment vocabulary and a composition to
        # resolve (docs/contract-flavour.md), and `profile_snapshot` on a profile
        # that is a *document* rather than a build-time literal. That last one is
        # not a gap in the pinning: today's profile is pinned by being in the
        # closure, which is a stronger pin than a copied file — and an unusable
        # one for a controller that never runs nix, which is why the contract
        # asks for bytes and this field will eventually hold them.
        printf '%s' "$cur" \
          | jq --argjson g "$next" ''${1+"$@"} \
            "$filter"'
              | .policy = (.policy // null)
              | .extras = (.extras // [])
              | .image = (.image // null)
              | .profile_snapshot = (.profile_snapshot // null)
              | .generation = $g
              | .schema = 1
            ' > "$tmp"
        mv "$tmp" "$dir/assignment.json"
        printf '%s' "$next"
      ) 9>"$dir/.lock"
    }
  '';
}
