# Everything the human runs *at* a capsule, built once for both paths — plus the
# one script a capsule runs *about itself*, which is here for the same reason:
# built once, so neither path can be built without it.
#
# There are **three** call sites and there must not be three implementations: the
# devshell builds these to reach the guest straight over the tap,
# `host/services.nix` builds the same set to reach it through the capsule's relay
# socket because under netns the guest is not routable from the root namespace at
# all, and `probe-freshness` builds its own to exercise the real programs on the
# real seam. The only difference between them is `access`, which is why that is
# the argument — and it is *one* argument holding two fields rather than two
# arguments, because a second argument is a second thing three call sites can
# each forget, and one of them did (NOTES item 34).
#
# `access.transport` is a shell fragment (`host/guest-ssh.nix`), not a value, and one
# store path serves every capsule because of it: spliced at the top of each
# program, it resolves which capsule this invocation means, strips that argument
# out of `"$@"`, and sets `ssh_cmd` to the argv that reaches it. Baking a
# transport instead — which is what an argv-valued `sshArgs` did — gives one
# program per capsule, since the only thing that differs between two capsules is
# a socket path.
#
# Everything else here is derivation, not decision: who the host talks to
# (`agent@`, the unprivileged guest user), where the checkout is, and which
# payloads leave this host. All of it comes from `net.nix`, `target.nix` and
# `setup.nix` — nothing target-shaped is spelled here.
{
  pkgs,
  lib,
  net,
  target,
  # The host's policy vocabulary (policies.nix). Only the git channel reads it —
  # `capsule-collect` selects an ingestion bound and a permission by name — but it
  # is threaded here for `target`'s reason: three call sites build this set, and a
  # value each of them looks up separately is a value one of them can look up
  # differently.
  policies,
  # The slots this host declares (capsules.nix). Read by one program for one
  # refusal — `capsule-brief` will not take state from a name that is not a slot,
  # because a quarantine is what a capsule sent back (NOTES item 42) — and
  # threaded here rather than looked up there for `policies`' reason: three call
  # sites build this set, and a value each of them resolves separately is a value
  # one of them can resolve differently.
  capsules,
  # The guest's branch, a constant threaded from `flake.nix` rather than a
  # target's field: only the git channel reads it, but both this file's callers
  # have to hand it the same one the guest was built with.
  workBranch,
  # Which capsule, and how to reach it — `host/guest-ssh.nix`'s `direct` or
  # `viaSocket`, as **one value with two fields**:
  #
  #   - `transport` resolves the name *and* sets `ssh_cmd`, for everything that
  #     talks to a guest;
  #   - `selectCapsule` resolves the name alone, for `capsule-adopt`, which must
  #     know which capsule it is for and must not reach one — it reads a
  #     host-owned quarantine, and a transport refuses when the guest is down,
  #     which is the state a finished capsule's exhibit is adopted in (NOTES item
  #     34).
  #
  # One argument rather than two because there are three call sites and a second
  # argument is a second thing each of them can omit.
  access,
}: let
  inherit (access) transport selectCapsule;

  # Where a capsule's collected exhibit lives, and what its refs are called. Two
  # programs over one convention: `capsule-collect` writes it, `capsule-adopt`
  # reads it.
  quarantine = import ./quarantine.nix;

  # The target's run-time half as a document, and the reader for it
  # (host/profile.nix, NOTES item 51). Built **here** rather than at each of this
  # file's three call sites for `observe`'s reason: a thing constructed twice is a
  # thing one of them can construct differently, and the front end and the module
  # both need this one. It is a function of `target` and of nothing else, so
  # there is nothing for a second construction to differ in.
  profile = import ./profile.nix {inherit pkgs lib target;};

  # Which *target* an invocation is about, spliced where `transport` puts which
  # *capsule* — the reader plus the `--profile` parse, as one thing a program
  # splices once. The symmetry is the point: both resolve a name at run time,
  # both strip it out of `"$@"`, and neither has a default (NOTES items 20, 28).
  profileSelect = profile.fragment + profile.select;

  # Where `capsule-baseline` writes its record. Beside the checkout, never inside
  # it: a record in the worktree is a dirty worktree, and that is what the next
  # `capsule-provision` refuses on.
  #
  # A fragment because two programs read one convention from opposite ends —
  # `capsule-baseline` writes it and `capsule status` reads it back
  # (host/observe.nix) — and two spellings of one path is how the two ends drift.
  # Not a field of the document: where a *capsule* keeps a record is this repo's
  # business and not the target's, so it is derived from `volumePath` here rather
  # than declared in `target.nix`.
  baselineRecordFragment = ''
    baselineRecordDir() { printf '%s/baseline' "$profile_volume_path"; }
  '';

  # The guest's checkout as a URL, at run time: the host half is `net.nix`'s and
  # the path half is the profile's. Three programs push or fetch over it
  # (`capsule-provision`, `capsule-collect`, `capsule-brief`) and each splices
  # this, for `gitSsh`'s reason — a mechanical conversion in three copies is
  # three chances to get one wrong.
  guestRepoFragment = ''
    guestRepoUrl() { printf 'ssh://%s%s' ${lib.escapeShellArg guestHost} "$profile_guest_path"; }
  '';

  # Whether a guest-authored tree may be written to a disk. Two programs write
  # one now — `capsule-adopt` onto this host, `capsule-brief` into another
  # capsule — so the check is a construction rather than a copy (NOTES item 35).
  exhibit = import ./exhibit.nix;

  # Transport, plus git's own view of it. git wants a command line rather than
  # argv, so the array is requoted here — `%q` because git runs `GIT_SSH_COMMAND`
  # through a shell, and the netns form has a ProxyCommand with spaces in it that
  # only quoting survives. Built once because three programs push or fetch over
  # this door, and a mechanical conversion in three copies is three chances to
  # get the quoting wrong in one of them.
  gitSsh = ''
    ${transport}
    GIT_SSH_COMMAND=$(printf '%q ' "''${ssh_cmd[@]}")
    export GIT_SSH_COMMAND
  '';

  # Who the host talks to when it talks to a capsule. Named once: the git
  # channel needs it inside a URL, the other two as an ssh destination.
  guestHost = "agent@${net.guest}";

  # The same URL as a build-time string, for **`probe-netns-boot` and nothing
  # else** (flake.nix). That probe is the deliberate exception to the addressing
  # rule — it boots the real guest, whose image has `net.nix` and `target.nix` in
  # it, so the real capsule *is* its subject. No program carries this any more.
  guestRepo = "ssh://${guestHost}${target.guestPath}";

  # The guest half of a collect's sideband — a store path, like `observe` below
  # and for the same reasons, pushed on stdin at each collect rather than baked
  # into a guest that would have to be restarted to carry it (NOTES item 32).
  # `null` when the target declares no out-of-band state, which is what makes
  # `capsule-collect` degrade to the code-only program it used to be rather than
  # grow a flag nobody sets.
  #
  # An attrset rather than the bare store path, since the scope invariant:
  # `capsule-collect` needs to know whether this target's policy has a hole in it
  # before it can decide that a unit is *required*, and that predicate belongs
  # beside the templates it is a predicate over.
  stateSnapshot =
    if (target.statePaths or []) == []
    then null
    else
      import ./state-snapshot.nix {
        inherit pkgs lib;
        # For `needsUnit` alone; the templates the script substitutes arrive on
        # its command line (NOTES item 51).
        inherit (target) statePaths;
      };

  # How anything host-authored runs *inside* a live capsule: the build-time lint
  # both guest runners get, and the login-shell rule a second hand-written
  # invocation would get wrong (host/guest-exec.nix, NOTES item 24).
  guestExec = import ./guest-exec.nix {inherit pkgs;};

  # The guest half of a status: one store path plus the command line that points
  # it at this target's paths (host/observe.nix).
  observeHook = import ./observe.nix {inherit pkgs;};

  # The third step of a provision — regenerate what the push cannot carry, in the
  # checkout the push just made (host/refresh.nix, NOTES item 33). `null` when
  # the target derives nothing from its checkout, which is what keeps the
  # two-step provision available rather than adding a flag nobody sets.
  #
  # The other end of `stateSnapshot` above, and the two are one decision: what a
  # collect must not carry out is what a provision regenerates in.
  refreshHook =
    if (target.refresh or null) == null
    then null
    else
      import ./refresh.nix {
        inherit pkgs lib guestExec guestHost transport profileSelect;
      };

  # The inbound state half: one capsule's collected state pushed into another's
  # checkout, so a second agent can read the first one's working state (NOTES
  # item 35). `null` on the same condition as the snapshot and the extractor — a
  # target with no `statePaths` has no state refs, so there is nothing to brief a
  # capsule with and a flag for it would be a flag that always refuses.
  #
  # The third corner of one decision: what a collect takes out
  # (`stateSnapshot`), what lays it on this host (`adopt`), and what puts it into
  # another capsule are three directions over one tree and one check.
  briefHook =
    if stateSnapshot == null
    then null
    else
      import ./brief.nix {
        inherit pkgs lib guestExec guestHost gitSsh quarantine exhibit profileSelect;
        guestRepo = guestRepoFragment;
        # The fourth corner, and the one whose origin is not a capsule at all
        # (NOTES item 42): a tree authored on this host is built by the program
        # that builds every other one, at `$profile_path` rather than at the
        # guest's checkout, and `slots` is what lets a source name be refused for
        # not being a capsule.
        #
        # One store path and the fragment that points it at a checkout (NOTES
        # item 51). It used to be a third instantiation of the same text, then
        # one text and three command lines; the command lines are read off a
        # document now and there is nothing left that is a function of a target.
        snapshotScript = stateSnapshot.script;
        snapshotArgs = stateSnapshot.argsFragment;
        inherit (stateSnapshot) needsUnit;
        slots = builtins.attrNames capsules.instances;
      };

  # The target's own build-and-test, host-initiated (host/baseline.nix). `null`
  # when the target declares no baseline — a better absent path than a program
  # that cannot work.
  baselineHook =
    if target.baseline == null
    then null
    else
      import ./baseline.nix {
        inherit pkgs guestExec guestHost transport profileSelect;
        baselineRecord = baselineRecordFragment;
      };

  gitChannel = import ./git-channel.nix {
    inherit pkgs lib policies workBranch guestHost gitSsh quarantine profileSelect;
    guestRepo = guestRepoFragment;
    brief = briefHook;
    snapshot = stateSnapshot;
    # The fragment, not the module: the git channel runs a refresh and has no
    # business knowing what one is built out of.
    refresh =
      if refreshHook == null
      then null
      else refreshHook.invoke;
  };
in {
  inherit guestHost guestRepo profile;

  # The one thing here with no transport, built here anyway: the guest-side half
  # of a status is a *store path* the front end pushes over whichever door it
  # already has (host/observe.nix, host/cli.nix). It belongs beside the three
  # guest paths it reads — two of them are already named above, and
  # `baselineRecord` is exported for this reader specifically. The alternative
  # was building it at each of `capsule-cli`'s two call sites, which is how the
  # module path came to be missing an argument the devshell path had.
  observe = observeHook.script;

  # Everything the front end needs to *build* that program's command line, as one
  # fragment (NOTES item 51 step 4): the profile reader, the record convention
  # and the argument order, each from the file that owns it. One opaque splice to
  # `host/cli.nix`, which is what keeps it knowing a program and not a set of
  # guest paths — and deliberately **without** `profile.select`, because a front
  # end resolves which target a slot means from this host's state rather than
  # taking it on argv (NOTES item 20).
  observeFragment = lib.concatStringsSep "\n" [
    profile.fragment
    baselineRecordFragment
    observeHook.argsFragment
  ];

  inherit (gitChannel) provision collect;

  # The second step out of quarantine, and the one with a security control in it:
  # the state half is a guest-authored tree, so what lands on a disk from it is
  # validated before anything is written (host/adopt.nix, NOTES item 34). `null`
  # on the same condition as the snapshot that produces the thing it reads — a
  # target with no `statePaths` never has a state ref, so an extractor for it is
  # a program that cannot work.
  adopt =
    if stateSnapshot == null
    then null
    else
      import ./adopt.nix {
        inherit pkgs selectCapsule quarantine exhibit;
      };

  # The other end of the same tree, and the reason `capsule-adopt`'s check became
  # a construction: this one validates host-side and pushes, and the guest only
  # lays out, because validation belongs where the policy is (NOTES item 35).
  brief =
    if briefHook == null
    then null
    else briefHook.program;

  # The guest half of a brief, at a checkout of the caller's choosing — the seam
  # `briefCases` in `flake.nix` runs the real text through. Exported here rather
  # than reached for through `brief`, because a program is a store path and a
  # case suite needs the thing *before* it becomes one.
  briefRunner =
    if briefHook == null
    then null
    else briefHook.runner;

  # Which names may be a source of a brief, as a runnable text (host/brief.nix).
  # Exported for `briefCases` beside the runner, and for the same reason: the
  # refusal that decides a quarantine is what a capsule sent back needs no guest,
  # so nothing about it should wait for a host (NOTES item 42).
  briefSpecChecker =
    if briefHook == null
    then null
    else briefHook.specChecker;

  # The outbound half's equivalent, and exported for the same reason
  # `briefRunner` is: `snapshotCases` runs this text against a checkout the
  # sandbox builds, because what an exhibit *contains* is decided by a branch a
  # live host reaches only by driving a real unit of work in a real capsule.
  #
  # A store path rather than a function of one now (NOTES item 51): the checkout,
  # the ceiling and the declared templates are arguments, so the sandbox's
  # instantiation *is* the guest's and there is nothing left to instantiate.
  stateSnapshotScript =
    if stateSnapshot == null
    then null
    else stateSnapshot.script;

  # The other end of that script's interface, for the same suite: the fragment
  # `capsule-collect` and `capsule-brief` build its command line with. Exported
  # beside the script because the two are one fact read from two ends, and
  # nothing else can tell whether they agree (NOTES item 51 step 4).
  snapshotArgsFragment =
    if stateSnapshot == null
    then null
    else stateSnapshot.argsFragment;

  # Which of the verbs below read a profile, so the front end knows which ones to
  # fill a `--profile` in for. `inject` and `adopt` are not among them and that is
  # the honest line rather than an oversight: a payload's destination is on the
  # *volume* and a quarantine is on this host, so neither is a value the target
  # supplies (setup.nix, host/adopt.nix). A list here rather than a predicate
  # there, for `programVerbs`' reason — built once, beside the programs.
  profileVerbs =
    ["provision" "collect"]
    ++ lib.optional (baselineHook != null) "baseline"
    ++ lib.optional (refreshHook != null) "refresh"
    ++ lib.optional (briefHook != null) "brief";

  # Whether this target's state paths are scoped to a unit of work (NOTES item
  # 32). The front end needs it for two things a program must not do: offer the
  # verb that records which unit a slot is driving, and hand that record to a
  # collect. Exported rather than recomputed there, because the predicate belongs
  # beside the templates and a second spelling of it is a scope that silently
  # never applies.
  stateNeedsUnit = stateSnapshot != null && stateSnapshot.needsUnit;

  # Which `capsule-<verb>` programs this host actually has, for the front end's
  # dispatcher. Here rather than at each of `host/cli.nix`'s two call sites, for
  # the reason `observe` moved here: a list built twice is a list that can differ
  # once, and the two copies of the CLI are one store path only while every
  # argument agrees. Eval catches a *missing* argument now; nothing catches a
  # different one, so the fix is to have one.
  programVerbs =
    ["provision" "collect" "inject"]
    ++ lib.optional (target.baseline != null) "baseline"
    ++ lib.optional (refreshHook != null) "refresh"
    ++ lib.optional (stateSnapshot != null) "adopt"
    ++ lib.optional (briefHook != null) "brief";

  # The same refresh `capsule-provision` runs, on its own: a human who has just
  # done a hand `git checkout` in the guest wants it and no push, and a provision
  # that failed *at* the refresh needs a way to retry only that half. `null` on
  # the same condition as the hook itself.
  refresh =
    if refreshHook == null
    then null
    else refreshHook.program;

  # And the same export for the same reason `stateSnapshotScript` has one: the
  # branch a case must reach is chosen by the *target's* command line, so the
  # command is what a suite passes (NOTES item 47) — passes, now, rather than
  # substitutes, which is what makes this a store path instead of a function of
  # one (NOTES item 51).
  refreshScript =
    if refreshHook == null
    then null
    else refreshHook.refreshScript;

  # The non-git half of provisioning: credentials, secrets and anything else a
  # fresh capsule needs that no repository carries. The list is ./setup.nix,
  # which is handed the volume's mount point — a payload's destination is in the
  # guest, and `/work` is `target.nix`'s to say. Its `tools` are nixpkgs attr
  # names, resolved here so that a declaration file stays data.
  inject = import ./inject.nix {
    inherit pkgs guestHost transport;
    injections =
      map (i: i // {tools = map (name: pkgs.${name}) i.tools;})
      (import ../setup.nix {inherit (target) volumePath;});
  };

  # The last step of making a fresh capsule usable, and the only one that
  # produces a figure: the target's own build-and-test, host-initiated, its
  # record written on the volume rather than to a terminal. `null` when the
  # target declares no baseline — a better absent path than a program that
  # cannot work.
  baseline =
    if baselineHook == null
    then null
    else baselineHook.program;

  # The guest half on its own, for `baselineCases` — the same export
  # `stateSnapshotScript` and `refreshScript` have, and for the same reason: the
  # only interface to that logic is the script's own text (NOTES item 51).
  baselineRunner =
    if baselineHook == null
    then null
    else baselineHook.runner;
}
