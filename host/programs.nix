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
  #
  # **Unconditional since step 6** (NOTES item 51). It used to be `null` for a
  # target declaring no `statePaths`, which is what made `capsule-collect`
  # degrade to the code-only program it used to be — a degrade decided by *which
  # flake this host was built from*, and therefore the same answer for every
  # document a run could be pointed at. The degrade is still there and it is a
  # run-time branch on the loaded profile now; this file no longer reads the
  # target to build it, and there is nothing left in it that is a function of
  # one.
  stateSnapshot = import ./state-snapshot.nix {inherit pkgs lib;};

  # How anything host-authored runs *inside* a live capsule: the build-time lint
  # both guest runners get, and the login-shell rule a second hand-written
  # invocation would get wrong (host/guest-exec.nix, NOTES item 24).
  guestExec = import ./guest-exec.nix {inherit pkgs;};

  # The guest half of a status: one store path plus the command line that points
  # it at this target's paths (host/observe.nix).
  observeHook = import ./observe.nix {inherit pkgs;};

  # The third step of a provision — regenerate what the push cannot carry, in the
  # checkout the push just made (host/refresh.nix, NOTES item 33).
  #
  # **Unconditional since step 6**, like `stateSnapshot` above and for its
  # reason. The absent path did not go anywhere: a profile that derives nothing
  # from its checkout is a step a provision skips and a refusal
  # `capsule-refresh` makes by name, both off `$profile_refresh` and both
  # already written at step 4. What went is the *build* deciding it, which on a
  # host with two documents decided it for the wrong one.
  refreshHook = import ./refresh.nix {
    inherit pkgs lib guestExec guestHost transport profileSelect;
  };

  # The inbound state half: one capsule's collected state pushed into another's
  # checkout, so a second agent can read the first one's working state (NOTES
  # item 35). Unconditional since step 6, on the same argument as the two above.
  #
  # The third corner of one decision: what a collect takes out
  # (`stateSnapshot`), what lays it on this host (`adopt`), and what puts it into
  # another capsule are three directions over one tree and one check.
  briefHook = import ./brief.nix {
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
    slots = builtins.attrNames capsules.instances;
  };

  # The target's own build-and-test, host-initiated (host/baseline.nix).
  # Unconditional since step 6, and the last of the four: "no program rather
  # than one that cannot work" was the right absent path while a host had one
  # target, and is the wrong one the moment it has two — the program cannot work
  # for *this* document is a sentence only a run can say, and `capsule-baseline`
  # has said it off `$profile_baseline` since step 4.
  baselineHook = import ./baseline.nix {
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
    refresh = refreshHook.invoke;
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

  # Where a capsule's own outbound state chain sits on its volume
  # (host/state-snapshot.nix, which declares it). Passed on rather than
  # respelled, for the reason everything else here is: the front end has to drop
  # a stale link of that chain before a handoff (NOTES item 53), and a namespace
  # spelled at two call sites is two things to keep true.
  stateRefPrefix = stateSnapshot.refPrefix;

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
  # validated before anything is written (host/adopt.nix, NOTES item 34).
  # Unconditional since step 6 — and the least conditional of the four, since it
  # reads a quarantine on this host and no target value at all: what it used to
  # be gated on was another program's absence.
  adopt = import ./adopt.nix {
    inherit pkgs selectCapsule quarantine exhibit;
  };

  # The other end of the same tree, and the reason `capsule-adopt`'s check became
  # a construction: this one validates host-side and pushes, and the guest only
  # lays out, because validation belongs where the policy is (NOTES item 35).
  brief = briefHook.program;

  # The guest half of a brief, at a checkout of the caller's choosing — the seam
  # `briefCases` in `flake.nix` runs the real text through. Exported here rather
  # than reached for through `brief`, because a program is a store path and a
  # case suite needs the thing *before* it becomes one.
  briefRunner = briefHook.runner;

  # Which names may be a source of a brief, as a runnable text (host/brief.nix).
  # Exported for `briefCases` beside the runner, and for the same reason: the
  # refusal that decides a quarantine is what a capsule sent back needs no guest,
  # so nothing about it should wait for a host (NOTES item 42).
  briefSpecChecker = briefHook.specChecker;

  # The outbound half's equivalent, and exported for the same reason
  # `briefRunner` is: `snapshotCases` runs this text against a checkout the
  # sandbox builds, because what an exhibit *contains* is decided by a branch a
  # live host reaches only by driving a real unit of work in a real capsule.
  #
  # A store path rather than a function of one now (NOTES item 51): the checkout,
  # the ceiling and the declared templates are arguments, so the sandbox's
  # instantiation *is* the guest's and there is nothing left to instantiate.
  stateSnapshotScript = stateSnapshot.script;

  # The other end of that script's interface, for the same suite: the fragment
  # `capsule-collect` and `capsule-brief` build its command line with. Exported
  # beside the script because the two are one fact read from two ends, and
  # nothing else can tell whether they agree (NOTES item 51 step 4).
  snapshotArgsFragment = stateSnapshot.argsFragment;

  # Which of the verbs below read a profile, so the front end knows which ones to
  # fill a `--profile` in for. `inject` and `adopt` are not among them and that is
  # the honest line rather than an oversight: a payload's destination is on the
  # *volume* and a quarantine is on this host, so neither is a value the target
  # supplies (setup.nix, host/adopt.nix). A list here rather than a predicate
  # there, for `programVerbs`' reason — built once, beside the programs.
  profileVerbs = ["provision" "collect" "baseline" "refresh" "brief"];

  # Which `capsule-<verb>` programs this host has, for the front end's
  # dispatcher. Here rather than at each of `host/cli.nix`'s three call sites,
  # for the reason `observe` moved here: a list built twice is a list that can
  # differ once, and the copies of the CLI are one store path only while every
  # argument agrees. Eval catches a *missing* argument; nothing catches a
  # different one, so the fix is to have one.
  #
  # **A literal since step 6** (NOTES item 51), and the whole of that half of the
  # step: four of these seven used to appear only where `target.nix` declared the
  # field they read, so *which verbs this front end offered* was a function of
  # which project the host confines — the coupling this item is about, in the one
  # place it decided what a human could type. Both lists are constants now, and
  # what a target does not declare is a run-time refusal that names the profile.
  programVerbs = ["provision" "collect" "inject" "baseline" "refresh" "adopt" "brief"];

  # The same refresh `capsule-provision` runs, on its own: a human who has just
  # done a hand `git checkout` in the guest wants it and no push, and a provision
  # that failed *at* the refresh needs a way to retry only that half.
  refresh = refreshHook.program;

  # And the same export for the same reason `stateSnapshotScript` has one: the
  # branch a case must reach is chosen by the *target's* command line, so the
  # command is what a suite passes (NOTES item 47) — passes, now, rather than
  # substitutes, which is what makes this a store path instead of a function of
  # one (NOTES item 51).
  refreshScript = refreshHook.refreshScript;

  # The host half beside it, and the same rule: `refreshCases` pins what is said
  # before anything runs, which is this fragment's and not the script's, and the
  # program's own text cannot be driven to it (a slot with no door is refused by
  # the transport first). Exported from here so the suite gets the text the two
  # callers get — `fragments.refresh` above is the same value.
  refreshInvoke = refreshHook.invoke;

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
  # record written on the volume rather than to a terminal.
  baseline = baselineHook.program;

  # The guest half on its own, for `baselineCases` — the same export
  # `stateSnapshotScript` and `refreshScript` have, and for the same reason: the
  # only interface to that logic is the script's own text (NOTES item 51).
  baselineRunner = baselineHook.runner;
}
