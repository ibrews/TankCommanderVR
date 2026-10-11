---
name: tcvr-testing
description: Verify Tank Commander VR gameplay and controls with its production harnesses, bounded smoke runs, and real rendered captures while tracking test limits.
---

# Tank Commander VR verification

Choose the smallest check that exercises the affected production behavior.
Read the selected harness before running it: historical comments can describe
an old defect, and some harnesses exit zero even when assertions fail.

| Change | Existing starting point |
| --- | --- |
| Gameplay state and wave transitions | `res://scenes/gameplay_qa.tscn`, `res://scripts/gameplay_qa.gd` |
| Cockpit control logic | `res://scenes/xr_interaction_smoke.tscn`, `res://tools/xr_interaction_smoke.gd` |
| Mesh geometry and facing | `res://tools/winding_math_check.gd`, targeted view-check tools |
| Main startup and scene construction | `res://scripts/main.gd` with `--smoke` |
| Rendered appearance | Production game capture flags or `res://tools/store_capture.gd` after checking its settings |

Use commands like these after binding the Godot executable and output routing
to the host's project instructions. `godot` below stands for that verified binary:

```text
godot --headless --path . -- --smoke
godot --headless --path . res://scenes/gameplay_qa.tscn
godot --headless --path . res://scenes/xr_interaction_smoke.tscn
godot --headless --path . --script res://tools/winding_math_check.gd
```

Pass game-specific CLI flags after a literal `--`. Use bounded runs and capture
stdout/stderr plus exit status. Require the expected checks and completion
marker, inspect FAIL/assertion output, and reject parse/runtime errors. An exit
code of zero or the main smoke marker alone does not establish a clean run.

Run scenes for tests that need project autoloads. Reserve bare `--script` for
independent `SceneTree`/`MainLoop` scripts whose dependencies are appropriate
for that mode; do not assume main-scene startup or test state is identical.

Read the splash-skip gate in `res://scripts/main.gd` when adding a test flag.
Also check `autostart.cfg`: it can replace the test scene after a delay. Route
`user://` to isolated data-volume storage using engine-supported configuration
or the host's approved wrapper; do not rename or overwrite the player's files.
Keep temporary configurations out of the committed project settings.

Headless runs test logic, not GPU images. Use a rendering-capable run for
screenshots and shader validation. Fix seeds and timing for repeatable captures
where possible, but do not assume a fixed timestep alone makes all physics or
threaded behavior deterministic. Check both control values and visible motion.

Synthetic hand trajectories verify control responses, not real tracking,
input dispatch, comfort, or haptics. Desktop captures do not establish stereo
quality or Quest frame time. Report each kind of evidence separately. Reuse
production APIs rather than reimplementing the behavior in the test.
