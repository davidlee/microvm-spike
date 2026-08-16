Proxy vars do **not** reach systemd units in the guest; anything daemon-side
needs its own `serviceConfig.Environment`.

Also: `initialHashedPassword = ""` does **not** give a passwordless root — it
applies only at account creation, and PAM rejects empty passwords for `su`.