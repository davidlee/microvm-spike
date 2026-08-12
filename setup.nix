# What a fresh capsule needs before it is a capsule you can work in, beyond its
# history and its static config. `capsule-inject` pushes these over the existing
# ssh channel as you — and `capsule <name> start` runs it, so a started capsule
# has them; `host/inject.nix` is the mechanism and knows none of the below.
#
# Its own file, and deliberately not `target.nix`: none of this is a property of
# the repo under confinement. doctrine has no opinion about which agent you sign
# in as, and a second target would share this list unchanged. Empty is a working
# value — a capsule with no injections is a capsule you log into by hand.
#
# **Selection is the whole point.** Every entry names what leaves this host, and
# the default for anything not named is that it stays. The tempting version —
# copy `~/.claude` in — would carry `projects` (every repo path you have opened),
# `history.jsonl` (3 MB of prompts) and `file-history/` into a jail that exists
# to not have them.
#
# An entry is `{name, dest, produce, tools}` plus an optional `optional`:
#
#   - `produce` is a host-side shell fragment writing the payload to stdout. It
#     is a program, not a value, which is what keeps filenames, formats and key
#     names out of the mechanism. `$capsule` is in scope, so a payload may differ
#     per capsule; argv is not, since the flag loop has already consumed it.
#   - `optional = true` means a source that is not on this host is a skip rather
#     than a failure — the working absent path a declaration shared by every host
#     needs.
#
# The volume's mount point is the only thing taken from `target.nix`, because a
# payload's destination is on the volume and `/work` may not be spelled twice.
# Nothing else target-shaped belongs here.
{volumePath}: let
  # The bwrapped agent's home on this host. Not the human's: that one has the
  # same credential in it and a great deal else besides, and this is already the
  # separated copy.
  jail = "/home/agent/jail.nix/home/agent";

  # The agent's `$HOME` in the guest (docs/contract-target.md).
  home = "${volumePath}/home";

  # Where *this* host keeps what it is willing to hand a capsule. Per capsule
  # first, then a shared file — so one host can give two capsules different
  # secrets without the declaration learning either capsule's name.
  mine = "$HOME/.config/capsule";
in [
  {
    # The OAuth token itself, whole — the file is nothing but the credential, so
    # there is no subsection to take. It rotates on refresh, which is the reason
    # `capsule-inject` refuses to replace an existing copy without `--force`: the
    # capsule's copy and this one diverge, and neither is authoritative. If a
    # capsule's session starts failing to authenticate, re-inject it.
    name = "claude-credentials";
    dest = "${home}/.claude/.credentials.json";
    produce = "cat ${jail}/.claude/.credentials.json";
    tools = [];
  }
  {
    # Identity and onboarding state, so a capsule session starts signed in
    # instead of at a setup wizard. Four keys of ninety: `projects`,
    # `githubRepoPaths`, `mcpServers`, `history` and every cache stay here.
    # `machineID` stays too — a capsule is a different machine and may say so.
    #
    # `error` rather than a quiet null: a key renamed upstream must fail here,
    # where it is one line to fix, rather than arriving in the guest as a file
    # that parses and signs nobody in.
    name = "claude-identity";
    dest = "${home}/.claude.json";
    produce = ''
      jq '{oauthAccount, userID, hasCompletedOnboarding, lastOnboardingVersion}
          | with_entries(select(.value != null))
          | if has("oauthAccount") then . else error("no oauthAccount") end' \
        ${jail}/.claude.json
    '';
    tools = ["jq"];
  }
  {
    # Environment secrets — API keys and anything else a shell in the guest wants
    # exported. `<volumePath>/.env` is sourced at login and persists on the
    # volume, so this is the file the guest already has (NOTES item 2); what was
    # missing was a carrier, and every capsule needed one made by hand.
    #
    # `op inject` is the second shape, and it is the same interface — swap the
    # line below for
    #
    #     op inject -i "${mine}/$capsule.env.tpl" 2>/dev/null \
    #       || op inject -i "${mine}/env.tpl" 2>/dev/null
    #
    # and add `tools = ["_1password-cli"];`. It has to run *here* rather than in
    # the guest: `op` reaches a host unix socket and firecracker has no shares,
    # so the direction is fixed — the rendered environment goes in, it is never
    # fetched out (docs/plan-c-multi-capsule.md, "Secrets and home at N"). The
    # plain file is the default because it costs no unfree package on a host that
    # does not use one.
    #
    # Optional, and that is the point of the field: a host with neither file
    # still starts capsules, and says which payload it skipped.
    name = "env";
    dest = "${volumePath}/.env";
    optional = true;
    produce = ''
      cat "${mine}/$capsule.env" 2>/dev/null || cat "${mine}/env" 2>/dev/null
    '';
    tools = [];
  }
]
