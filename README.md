# microvm-spike

A **capsule**: a [firecracker](https://github.com/firecracker-microvm/firecracker) [microVM.nix](https://github.com/microvm-nix/microvm.nix) used to confine a coding agent. It holds a
real git clone of `~/dev/doctrine`, carries that project's tool set, and has
exactly enough network to work and no more.

Design rationale and known gaps live in [NOTES.md](./NOTES.md). This file is
how to drive it.

## Prerequisites

- KVM (`/dev/kvm` is `crw-rw-rw-` here, so no group membership needed).
- In the host's NixOS config, the two ports the guest is allowed to reach:

  ```nix
  networking.firewall.interfaces."vm-capsule".allowedTCPPorts = [3128 9418];
  ```

  Interface-scoped on purpose. `trustedInterfaces` would accept *everything*
  arriving on the tap, which puts every `0.0.0.0`-bound host service inside the
  jail's reach; plain `allowedTCPPorts` would open the proxy and the git daemon
  on the LAN and the tailnet.
- nix-direnv — `direnv allow` gets you the devshell and its commands.

## Quickstart

Three terminals, or three tmux windows:

```
capsule-net up      # once per boot; sudo. creates the tap, owned by you
capsule-host        # foreground: git daemon + egress proxy
vm capsule          # foreground: the VM, with its serial console on your tty
```

Then from a fourth: `ssh agent@10.99.0.2`.

Inside the guest you are `agent`, in `/work/doctrine`:

```
just test
just web-build
capsule-push my-branch     # -> refs/heads/capsule/my-branch on the host mirror
```

Back on the host, collect the work:

```
git fetch .vm/host/doctrine.git 'refs/heads/capsule/*:refs/heads/capsule/*'
```

## Commands

| command             | what                                                       |
| ------------------- | ---------------------------------------------------------- |
| `capsule-net up`    | create the tap + assign `10.99.0.1/30`. Needs sudo.         |
| `capsule-net down`  | remove it. Refuses while a VM runs; `--force` overrides.    |
| `capsule-host`      | git daemon + tinyproxy. Foreground, unprivileged.           |
| `vm [name]`         | run a VM (`capsule` by default; `hello` is the smoke test). |
| `vm-stop [name]`    | clean shutdown over the firecracker API socket.             |
| `capsule-clone`     | *(guest)* clone/fetch from the host mirror.                 |
| `capsule-push NAME` | *(guest)* push HEAD to `capsule/NAME` on the mirror.        |

## Process lifecycle

`vm` is **not** a daemon: it's firecracker in the foreground with the guest's
serial console on your terminal. Closing the terminal SIGHUPs it, which works
but is a power-cut — the guest gets no shutdown and the volume replays its ext4
journal next boot. Prefer `poweroff` at the console, or `vm-stop` from
elsewhere. `pgrep -af 'microvm@'` is the entire inventory; nothing is
registered anywhere.

**A guest that has shut down may leave the VM running.** Firecracker doesn't
exit on guest poweroff — it halts the vCPU and keeps holding the tap, so the
next `vm capsule` fails with `Device or resource busy`. `vm-stop` handles this
(poweroff, wait, then terminate the VMM); `pgrep -af 'microvm@'` is the check.

**A tap cannot be swapped under a running VM.** `capsule-net down` while the VM
runs destroys the netdev while firecracker keeps the fd; recreating the tap
attaches to nothing and the guest goes silent (`No route to host`). Only a VM
restart recovers it, which is why `down` refuses by default.

## Network

Point-to-point tap, host `10.99.0.1/30` ↔ guest `10.99.0.2/30`. No bridge, no
NAT, **no default route in the guest**, no resolver in the guest. Everything
outbound goes through the host's proxy, which resolves names itself — so an
unlisted host cannot be reached or even resolved.

To let something new out, edit `net/egress-allow.txt` (extended regex,
one hostname per line) and restart `capsule-host`. No rebuild.

`ssh` runs the other way — host to guest — and widens nothing.

## Changing the guest's tools

The tool set comes from doctrine's `packages.dev-tools`, so both this VM and
that devshell take from one list. To change it:

```
cd ~/dev/doctrine        # edit devToolPkgs in flake.nix
git commit               # git+file: inputs read committed HEAD
cd ~/dev/microvm-spike && nix flake update doctrine
vm-stop capsule && vm capsule
```

## Troubleshooting

| symptom                                        | cause                                                     |
| ---------------------------------------------- | --------------------------------------------------------- |
| `Cannot assign requested address` on start     | tap missing — `capsule-net up`                             |
| `Address already in use` on start              | orphaned daemon from an earlier run; `capsule-host` names the pid |
| `No route to host` to `10.99.0.2`              | tap was recreated under a running VM, or the VM is down    |
| guest reaches nothing, host is up              | host firewall dropping the tap — see the `interfaces."vm-capsule"` rule above |
| a hostname 403s through the proxy              | not in `net/egress-allow.txt`; `.vm/host/tinyproxy.log` names it |
| a TUI (claude, etc.) renders but ignores Enter | serial console input quirk — run TUIs over ssh              |

State lives in `.vm/` (volume images, sockets, the mirror, proxy logs) and is
gitignored. Deleting `.vm/capsule/capsule-work.img` resets the guest's
workspace; deleting `.vm/host/` re-mirrors from scratch and **loses any
`capsule/*` branches not yet fetched**.

**Never loop-mount `capsule-work.img`.** It is guest-written ext4, and `mount`
feeds its metadata to the host kernel. Read it with `fuse2fs`/`debugfs`, or
just ask the guest over ssh. (NOTES.md has the reasoning.)
