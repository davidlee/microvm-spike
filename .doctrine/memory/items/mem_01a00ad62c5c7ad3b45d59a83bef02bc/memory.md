systemd reads a newline in a directive as **unbalanced quoting**, ignores that
directive, and **does not reliably resume**. A multi-line
`ExecStartPre=${pkgs.bash}/bin/bash -c '…'` took `NetworkNamespacePath`,
`ExecStop` and `Restart=no` with it, and every capsule started as microvm.nix's
bare template: root namespace, no tap, EPERM, restarting every 5 s.

Nix will happily generate it and only a load says otherwise.

**Everything else looked fine** — both proxies and relays active, both sockets
present, `capsule-perimeter-guard: 2 capsule namespace(s) verified` — because
none of them can see inside a VMM's unit. The one witness is
`journalctl -u microvm@<name>`, and the confirmation is
`systemctl show microvm@<name> -P NetworkNamespacePath -P Restart`.

Repeated `changed on disk … run daemon-reload` warnings and a stuck
`NeedDaemonReload=yes` are what a drop-in that never parses looks like from
outside; **reloading is not the fix**.

Put the script in the store and name it (`host/services.nix`'s `stopKeyCheck`).
`just build` now refuses a newline in any of the module's `serviceConfig`
values.