`sudo` strips `SSH_AUTH_SOCK`, and the guest's key is `~/.ssh/id` — **not a
filename ssh tries by default**. So a root-side program gets the *wrong* key
offered and a clean `Permission denied`, while **ping keeps passing**.

Cost one `probe-netns-boot` run.

Anything host-side that ssh's to the guest runs **as the human** for this reason;
`probe/netns-boot.sh` finds the agent socket itself and refuses before it boots
anything if there is none.