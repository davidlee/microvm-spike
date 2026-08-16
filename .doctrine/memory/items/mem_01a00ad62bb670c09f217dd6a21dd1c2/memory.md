Deleting a tap leaves firecracker holding a **dead fd**; recreating it attaches
to nothing and the guest goes silent with `No route to host`.

`capsule-net down` refuses while a VM runs, for this reason. Do not remove that
refusal.