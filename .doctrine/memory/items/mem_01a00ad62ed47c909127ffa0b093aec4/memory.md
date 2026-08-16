The guest console log lives **inside the state directory the probe deletes**, and
a log is only ever wanted **after** a red run — by which point it is gone.

Set `CAPSULE_KEEP=1` before any probe run you might need to read.