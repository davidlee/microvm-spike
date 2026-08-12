# What a fresh capsule needs before it is a capsule you can work in, beyond its
# history and its static config. `capsule-inject` pushes these over the existing
# ssh channel as you; `host/inject.nix` is the mechanism and knows none of the
# below.
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
# Paths are absolute in the guest. `/work/home` is the agent's `$HOME` and lives
# on the volume, which is why this is paid per *fresh* capsule rather than once:
# freshness is implemented by deleting that volume (docs/probes.md).
let
  # The bwrapped agent's home on this host. Not the human's: that one has the
  # same credential in it and a great deal else besides, and this is already the
  # separated copy.
  jail = "/home/agent/jail.nix/home/agent";
in [
  {
    # The OAuth token itself, whole — the file is nothing but the credential, so
    # there is no subsection to take. It rotates on refresh, which is the reason
    # `capsule-inject` refuses to replace an existing copy without `--force`: the
    # capsule's copy and this one diverge, and neither is authoritative. If a
    # capsule's session starts failing to authenticate, re-inject it.
    name = "claude-credentials";
    dest = "/work/home/.claude/.credentials.json";
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
    dest = "/work/home/.claude.json";
    produce = ''
      jq '{oauthAccount, userID, hasCompletedOnboarding, lastOnboardingVersion}
          | with_entries(select(.value != null))
          | if has("oauthAccount") then . else error("no oauthAccount") end' \
        ${jail}/.claude.json
    '';
    tools = ["jq"];
  }
]
