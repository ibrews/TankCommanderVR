---
name: tcvr-performance
description: Diagnose Tank Commander VR frame time, draw calls, memory growth, and Quest rendering costs using measured production gameplay.
---

# Tank Commander VR performance

Bind the measurement to the project commit, engine version, device, level,
game mode, and applied tuning. Inspect `res://scripts/tune.gd` and the active
`tuning.cfg` before explaining behavior from project defaults alone.

The documented target is 72 Hz, approximately 13.89 ms per frame. Preserve the
requested target; do not impose a generic 90 Hz requirement. Read the README's
measurement caveat: the historical 9.2 ms GPU result predates the foveation and
shadow changes and is not a current baseline.

1. Reproduce the issue and separate CPU, physics, GPU, allocation, and loading
   costs using profiling appropriate to the target. Desktop timings can guide
   a diagnosis but cannot establish standalone Quest performance.
2. Trace the measured cost through the real source: `res://scripts/terrain.gd`,
   `res://scripts/mesh_kit.gd`, `res://scripts/fx.gd`,
   `res://scripts/projectiles.gd`, or the responsible gameplay system.
3. Test one bounded change against the same workload. Pool or batch only where
   measurements justify it; preserve gameplay, collision, and replication.
   Off-screen enemies can still matter to simulation and multiplayer, so do
   not disable their logic solely because they are invisible.
4. Report before/after frame times and observed spikes with the workload and
   settings. Keep unmeasured costs explicitly unmeasured.

For foveation, inspect the actual XR initialization in `res://scripts/main.gd`:
setting an OpenXR foveation level is not proof it is active. Check the viewport's
VRS setup and runtime evidence. A/B glow, shadows, resolution, and foveation
individually rather than assuming their costs or compatibility.

`autostart.cfg` can change level and settings after a delay. Isolate benchmark
user data from the player's normal files before running a controlled experiment.
Use the `tcvr-testing` skill for environment and capture setup.
