# EVD-003: The relay costs nothing on bulk and clumped every keystroke

Two measurements of the same relay socket, pointing opposite ways:

| what | figure | n |
| --- | --- | --- |
| git channel over the relay | **93.7 MiB/s out, 117.9 MiB/s back**, 66.9k objects / 32 MiB | 1 each way |
| ssh through the relay | 13 ms to banner, 60–90 ms for a whole `ssh … true`; interactive prompt 0.56 s | 3 |
| **keystroke echo** | **18–20 ms a character** | 7, one session |

Bulk is the same order as the tap did directly (~100 MiB/s), so **the relay costs
nothing on bulk** — it is `socat` on both ends plus a TCP hop inside the
namespace, and it still beats the disk.

The echo figure is **Nagle on the relay's TCP leg**: socat sets no `TCP_NODELAY`
and ssh cannot set it on a socket it did not open. **The first character was 1 ms
and the rest clumped**, which is the signature.

`,nodelay` is now on the unit and **the post-fix figure is unmeasured** —
`CHR-009`. Bulk throughput is the wrong instrument for it: a bulk number is green
whether or not the fix does anything.

Source: `docs/probes.md`, *Figures*.
