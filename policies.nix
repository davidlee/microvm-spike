# The egress and ingestion policies this host declares. Its own file for the same
# reason as net.nix, target.nix and capsules.nix — several places need these
# values and none of them may spell them twice — and, like all three, a *value*:
# nothing here reads the system or does work.
#
# **A policy is a control, and a control has one owner.** Which project a slot
# holds is semantics: cheap, frequent, delegable, and the thing a fleet exists to
# vary. What that slot may talk to, and what may come back out of it, is not —
# and it lived in `target.nix` until now only because one target made the two
# questions look like one (NOTES item 36, item 25). An assigner selects a policy
# by name from the set its slot declares (capsules.nix) and may not author one;
# a host operator declares the set and never has to spell an allowlist twice.
#
# **Paths, not contents.** Every allowlist stays a plain file outside the store,
# which is what lets it change without a rebuild — the same rule the single
# allowlist has always been kept under. What a policy adds is *which* file.
#
# **One directory, because a hardened unit has to be able to read it.** The
# proxy runs with `ProtectSystem=strict` and an explicit `BindReadOnlyPaths`, and
# the file it reads is chosen at run time by a symlink the `policy` verb
# re-points. Binding one declared directory makes the set of files a proxy could
# ever read bounded and legible, which a per-policy path scattered over the disk
# would not.
#
# `rec`, for one reason: `everything` is the vocabulary's own names, and deriving
# it here is what keeps a slot's permissive declaration one word instead of a
# list that drifts as this file grows.
rec {
  # Relative to CAPSULE_ROOT on the devshell path, and to the module's `policyDir`
  # option on the module path — the same arrangement `allowlist` had, one level
  # up. A policy's `allowlist` is a filename in here and never a path: a
  # separator would put a proxy's readable set outside the directory that was
  # bound for it.
  dir = "perimeter";

  # The vocabulary. Two, because two is what makes the mechanism demonstrable —
  # a slot on one and a slot on the other is the only way to assert that a policy
  # is selected rather than shared, and it is the shape `probe/netns-egress.sh`
  # would take to prove it on a live host.
  policies = {
    # What a capsule that has to build something needs: the hostnames its
    # toolchains fetch from, and an ingestion bound that a real result fits
    # inside. The allowlist file is the one this repo has always had.
    build = {
      allowlist = "egress-allow.txt";

      # `ulimit -f` on the fetch, so it bounds the size of any *one* file the
      # fetch writes — the packfile — and nothing else. A backstop rather than a
      # bound on the transfer: a pack of a million small objects never trips it
      # and still fills the disk (NOTES item 18). It is here rather than in
      # `target.nix` because what may come back is host policy about ingestion,
      # not a property of the project (item 25).
      collectMaxPackBytes = 536870912;

      mayCollect = true;
    };

    # The maximally-confined one: nothing out, nothing back. An empty allowlist
    # is a real file rather than an absent one, so a proxy under this policy
    # starts, serves and denies — a proxy that failed to start would be a
    # perimeter nobody is watching rather than a tight one.
    sealed = {
      allowlist = "egress-none.txt";
      collectMaxPackBytes = 536870912;
      mayCollect = false;
    };
  };

  # The whole vocabulary's names, so a slot that may take any policy says so in
  # one word instead of a list that drifts as this file grows. That is Plan D
  # §0's rule that the permissive answer **falls out of a declaration** rather
  # than being the mechanism's default — a dev host declares `everything` and a
  # ranch declares two names, and neither is a special case of the other.
  everything = builtins.attrNames policies;
}
