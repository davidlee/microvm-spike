A probe that "ignores your fix" is **the old build on `PATH`**.

`just build`, re-enter the devshell, or
`sudo "$(nix build --no-link --print-out-paths .#probe-netns-boot)/bin/…"`.