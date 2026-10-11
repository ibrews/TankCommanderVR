---
name: godot-shader
description: Author or review Tank Commander VR materials, shader code, and VFX for Godot 4.7 Mobile rendering and stereoscopic OpenXR.
---

# Shaders for Tank Commander VR

Locate the shader or material actually used by the game. Shader strings may be
embedded in GDScript, such as `res://scripts/terrain.gd`; do not assume a
`shaders/` directory exists. Inspect `res://scripts/mesh_kit.gd` for the shared
vertex-color material convention before adding unique materials per instance.

- Keep the Mobile renderer and the existing asset approach. Check feature
  support in the documentation for the project's engine version before using
  a Forward+-specific effect or a screen/depth-buffer technique.
- Keep coordinate spaces explicit. For a stereo effect, inspect how each eye's
  view and projection are used; a desktop screenshot does not establish correct
  depth or appearance in both eyes.
- Preserve mesh normals, winding, vertex colors, fog, and material sharing when
  changing surface shading. Do not hide a geometry defect by making everything
  double-sided unless that is the intended material behavior.
- Bound transparent overdraw, full-screen passes, texture samples, and lights.
  Profile a representative Quest scene with the effect enabled and disabled
  before making a frame-budget claim.
- For camera feeds built with `SubViewport`, verify the camera is current and
  the viewport updates; a material alone cannot make an inactive camera render.
- Keep visual captures tied to the real game and its current settings. Inspect
  `res://tools/store_capture.gd` before using it: its lighting can differ from
  normal gameplay. Verify the same effect in the production path.

Use `tcvr-performance` for cost measurements and `tcvr-testing` for captures.
Read only the relevant section of [the community shader reference](references/upstream.md)
when an example helps. Validate its stage built-ins, render modes, and feature
support against the actual engine; these examples are not certified Quest code.

Official reference: [Godot spatial shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html).
Use the version selector to match the project. Attribution is in
`docs/agent-skills.md` and `LICENSE`.
