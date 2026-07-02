# Controller model source

`left.glb` / `right.glb` / `profile.json` — Meta Quest Touch Plus (Quest 3 / 3S)
controller models, from `@webxr-input-profiles/assets@1.0.20`
(`immersive-web/webxr-input-profiles` on GitHub), profile `meta-quest-touch-plus-v2`.
MIT licensed — see `LICENSE.md` in this folder (Copyright Amazon 2019).

Used instead of Godot's `OpenXRFbRenderModel` (XR_FB_render_model) because that
extension is confirmed NOT supported on Quest 3S specifically by the Khronos
runtime extension support matrix, and rendered nothing when tested live on-device
2026-07-02 — see `intelligence/techniques/godot-quest-hand-mesh-and-controller-model.md`
in the KB for the full story. Animated mechanically by `scripts/controller_visual.gd`
per the node-naming-triplet scheme documented in `profile.json` (each animated part
has a `<name>_value` node whose local transform gets interpolated between `<name>_min`
and `<name>_max` based on the live input value each frame — no IK, no physics).
