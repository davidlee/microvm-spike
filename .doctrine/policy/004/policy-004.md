# POL-004: Reusable code knows nothing about the jail

## Statement

**`perimeter/` knows nothing about the jail.** It builds the proxy and
`capsule-host` from addresses, a port, and **two injected shell fragments**:

- `preflight` — once, before anything binds;
- `watch` — a supervised child that exits nonzero when the perimeter is gone,
  which tears the proxy down.

**No tap name, no hypervisor, no Linux-only tool goes in there.** Anything
platform-shaped belongs at the call site in `flake.nix` (`perimeterChecks`).

**`host/git-channel.nix` has the same seam for the same reason**: it knows a git
URL and a `transport` fragment, both injected, and nothing about taps or
namespaces.

**A program that needs testing takes as an argument the one thing that ties it to
this host** — `host/guard.nix`'s `tools`, `host/cli.nix`'s `moduleState`, an
argument with a default so both shipped copies stay one store path — exactly as
all of them take `transport`.

**Do not let a program probe for which transport to use: that bakes both into
it.**

## Rationale

The seam is what lets the perimeter be reused by a shape that is not firecracker
— a seatbelt or VM-based jail (`docs/plan-b-other-jails.md`), or a guest that is
not a capsule at all (`docs/plan-e-room.md`, the first test of whether the
machinery underneath is separable from the product).

The same seam is what lets **one store path serve N capsules**: the `transport`
fragment resolves `--capsule <name>` at run time and sets `ssh_cmd`, so a
capsule's socket is derived from its name instead of being built into four
programs (`NOTES item 20`).

**And it is what makes the case suites possible at all.**
`writeShellApplication` prepends `runtimeInputs` to `PATH`, so a test **cannot**
stub `ip` by prepending its own. Injecting the host-tying thing as an argument is
the only way a suite can run the shipped program's own text.

That has a boundary worth respecting rather than working around:
`gitChannelCases` is the only suite over a program that talks to a guest, and
**what it can reach is everything upstream of the door** — `pkgs.openssh` is in
its subjects' `runtimeInputs`, so nothing in a sandbox can stub `ssh`.

## Scope

**Applies to** `perimeter/`, `host/git-channel.nix`, and any new component
intended to outlive this hypervisor.

**Excluded**: `flake.nix`'s call sites, which are where platform-shaped things
belong; `host/netns.nix` and `host/services.nix`, which are the jail.

Two adjacent rules of the same family:

- **A suite that composes a program's command line by hand pins only one end of
  it.** `snapshotArgs` and `observeArgs` are an order of values printed at one
  end and read at the other; a suite spelling that order itself would agree with
  itself while the two ends disagreed — silently, in the status's case. So those
  suites build the tail from the **shipped fragment** and run the **shipped
  script** with it.
- **How many times a value is escaped depends on where it lives.** A value
  *spliced into a program's text* crosses two shells and is escaped twice. A
  value that is an **array element at run time** is not parsed by this host's
  shell at all, so exactly one `%q` is right and two arrive backslashed;
  `profileQuote` is that one filter, and it can be line-based only because the
  render refuses a newline in any value.

## Verification

- **Build**: every `*-cases.nix` suite exists because of this seam. One suite per
  file, beside the program it pins — `host/<name>-cases.nix`, a function of
  `pkgs`, `lib` and **the store path the program ships**, with a short `import`
  in `flake.nix` (`NOTES item 51` step 0). A new suite goes in its own file and
  takes its subject as an argument — **never a second render of the text it
  claims to pin**.
- **All suites are in `just build`, so a failing case is a failing build.**
  Check that when you add one: `observeCases` and `baselineCases` were written,
  wired into `just cases`, and **left out of `just build` for a session**
  (`NOTES item 51` step 3).
- **Two rules for writing a case**: assert the **reason** as well as the exit
  status, since a refusal for the wrong reason is a different program passing;
  and **check the suite can fail** by mutating the behaviour it claims to pin —
  the skip in `host/guard.nix` was reverted to its old form once, on purpose, to
  watch the case for it go red.

## References

- `NOTES item 20` — one store path, N capsules, and why a program must not probe
  for its transport.
- `NOTES item 51` — the guest-pushed scripts taking their checkout at run time.
- `docs/plan-b-other-jails.md`, `docs/plan-e-room.md` — what the seam is for.
