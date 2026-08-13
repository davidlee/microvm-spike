# NOTES item 13 — host SMT is on

*State: accepted, not fixed.*
One item of the [ledger](./index.md) — the number is the citation, and it
never moves.

**Accepted, not fixed:** host SMT is on and `machine-config` carries
`smt: true`, against firecracker's own host-setup guidance for untrusted
guests. Zen 5 reports vmscape mitigated (IBPB on VMEXIT) and is unaffected
by MDS/L1TF, and a side channel is a preposterous amount of work to steal
what the agent's own commits can carry out in the open. Revisit only if the
capsule ever hosts something genuinely adversarial.
