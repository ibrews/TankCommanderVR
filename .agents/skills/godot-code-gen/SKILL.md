---
name: godot-code-gen
description: Implement or review Tank Commander VR GDScript, procedural scene construction, control lifecycles, and gameplay state in Godot 4.7.
---

# GDScript for Tank Commander VR

Start with the affected production code and `project.godot`. Use Godot 4.7 APIs
and concrete types where they clarify new or changed code. Preserve local
conventions; do not rewrite unrelated code just to enforce a generic style.

- The runtime constructs geometry and cockpit controls. Follow
  `res://scripts/mesh_kit.gd` and `res://scripts/cockpit_builder.gd` rather than
  introducing editor-authored scenes to implement a small feature.
- Trace changes through `res://scripts/game.gd`, `res://scripts/main.gd`, and
  the affected vehicle. Reuse the existing autoloads instead of adding another
  state owner or a second singleton for the same responsibility.
- For nodes built dynamically, initialize references after construction;
  an `@onready` path is only valid when the node already exists at that stage.
- Keep signal connections, timers, tweens, and deferred callbacks valid across
  vehicle swaps, death, lobby return, and node deletion. Check validity after
  awaits when the owner or referenced node can be freed.
- For an inverted VR control, check its game value and visible mesh motion
  separately. Verify transforms with actual vectors rather than repeatedly
  changing signs from a mental derivation.
- New examples should use callable signals, `await`, and `instantiate()`.
  Verify uncertain APIs against the documentation for the project's version.

For verification, use the `tcvr-testing` skill. If the change has network or
rendering consequences, select that domain's skill as well.

For a syntax example, selectively read [the retained community reference](references/upstream.md).
Its examples are templates, not this project's architecture or proven working
code. In particular, threaded loads need error handling, and general advice to
prefer signals or `@onready` does not override the actual lifecycle here.
Source and license are recorded in `docs/agent-skills.md` and the adjacent
`LICENSE` file.
