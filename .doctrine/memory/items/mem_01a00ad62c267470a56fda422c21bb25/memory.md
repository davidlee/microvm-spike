A guest `ls` shows a file written five minutes ago as **ten hours old**, and
`find -newermt` compares against a guest-local time that may be in the guest's
future.

Ask the guest for `date -u` before reading any mtime in it against a host clock.
This is what made a run taken minutes earlier look like the previous evening's.