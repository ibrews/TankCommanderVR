# Handoff — asset showcase geometry investigation (2026-07-03)

**UPDATE (later same night): ROOT CAUSE FOUND AND FIXED.** The section
below this line is the important one — read it first. The rest of the
document is kept for the two AI-tooling gotchas and the tooling setup,
which are still relevant.

## THE FIX — read this first

Alex's "flipped normals, inconsistently" report was real, and it wasn't
the city-building anomaly logged earlier tonight (that one didn't survive
scrutiny — see "Retracted" below). The actual bug: **`MeshKit.cyl()`'s
side-wall triangles had inverted winding**, in `scripts/mesh_kit.gd`.

**How it was found:** built a headless, no-rendering analytical check
(`scripts/mesh_audit.gd` + `scenes/mesh_audit.tscn`, run via
`godot --path . scenes/mesh_audit.tscn`) that reads the real
`ArrayMesh.surface_get_arrays()` vertex/index data for every cylinder-based
mesh in the game and checks: does the triangle's *geometric* winding
(right-hand-rule cross product of the actual vertex order) agree with the
*stored* per-vertex normal `MeshKit.cyl()` writes? Godot's backface culling
decides visibility from winding; lighting shades from the stored normal —
a mismatch between the two is exactly the "some faces look right, some
look inside-out, depending on angle" symptom, because culling and shading
are working off two different, disagreeing ideas of which way the face
points.

**Result before the fix:** 8 of 10 real meshes tested had mismatches —
every one of them cylinder-based (tank turret 36/72, enemy plane 32/112,
jeep 100/236, gunner infantry 34/104, mortar 36/180, ship 54/198,
tree/palm foliage). The two box-only meshes (tank hull, rocks) were
already 100% correct — this bug was specific to `MeshKit.cyl()`, not
`MeshKit.box()` or `MeshKit.prism()`.

**Fix applied** (`scripts/mesh_kit.gd`, `cyl()` function): the side-wall
quad was split into triangles `(b0,b1,t1)` + `(b0,t1,t0)`, which — verified
by hand with the actual vertex math before touching code — computes a
face normal pointing *inward* toward the cylinder axis, opposite the
correct outward per-vertex normal already being written. Swapping the last
two vertices of each triangle (`(b0,t1,b1)` + `(b0,t0,t1)`) flips it
outward, matching the stored normal. The normal/UV arrays were reordered
to match the new vertex order (each vertex position must keep pairing
with the same normal/UV regardless of which triangle it appears in — this
was checked, not assumed).

**Verified, not assumed, three ways:**
1. Re-ran `mesh_audit.gd` after the fix: **0/1194 mismatches across every
   mesh tested** (was >0 on 8/10 before). One residual case (tree foliage,
   14 apparent mismatches) turned out to be a false positive from the
   audit script itself — cone-shaped foliage has `top_r=0`, so both "top"
   vertices of a side-wall triangle coincide at the apex, producing a
   zero-area degenerate triangle whose winding is numerically meaningless.
   Added an area filter (`area < 0.0001 → skip`) to the audit script and
   confirmed the count matched exactly (14 = 2 cones × 7 sides each).
2. `-- --smoke` clean after the fix.
3. Re-rendered the full showcase (`TC_SHOWCASE_SHOT=1`) and visually
   confirmed the helicopter, jeep, gunner rifle, palm trunk — all
   previously-affected cylinder meshes — render correctly.

**Retracted from earlier tonight:** the "CITY BUILDING renders inside-out"
claim in the original version of this doc. That was investigated further
with an analytical check on `MeshKit.box()` specifically (not `cyl()`) —
both the small and large wall-box sizes came back 100% correctly wound.
The actual bug was never in `box()` at all; the city-building screenshot
was very likely just a misread on my part (a very tall, narrow building
viewed close-up against open sky). Don't re-chase it — if Alex still sees
something wrong with buildings specifically after this cylinder fix, that
would be a *new* finding, not the one already investigated twice tonight.

**What this means for you (the parallel session):** the primary
investigation is DONE. What's left:
- Confirm on your end that the fix looks right in-editor
  (`scenes/asset_showcase.tscn`, F6) — a second pair of eyes before Alex
  wakes up is worth it, especially since Alex's original report was more
  specific/emphatic than what one round of screenshot review caught.
- If Alex is *still* seeing something after this, it's a genuinely new
  lead — use `mesh_audit.gd` as the template (it's fast, cheap, and far
  more reliable than screenshots — extend it to check `MeshKit.prism()`
  callers too, which weren't isolated on their own, only inside the
  EnemyShip combined-mesh test which came back clean).
- **This was a real gameplay-code fix** (`scripts/mesh_kit.gd`), not
  showcase-only. It affects literally every cylinder in the game — export
  a fresh APK when this feels solid so Alex can confirm on the Quest, since
  this is exactly the kind of thing that can look different on-device than
  on desktop.

## Two gotchas from tonight — still relevant, read before doing anything

1. **The Godot editor can silently rewrite `project.godot`.** Happened
   once already tonight from opening a second editor process via
   computer-use. **Rule: `git status`/`git diff` after ANY Godot editor
   GUI interaction, before committing anything, every time.** Full
   writeup: `intelligence/techniques/godot-editor-silently-rewrites-project-godot.md`
   in the KB. Task boundary still applies: **do not modify
   `project.godot`'s [xr]/rendering settings or `export_presets.cfg`, and
   do not touch the App Lab upload pipeline.**

   **Note from later tonight:** while wrapping up, an `addons/godot-xr-tools/`
   folder and a `scripts/game.gd` modification showed up staged in git
   again — almost certainly *your* (the parallel session's) own
   in-progress work, since you were active in this same repo concurrently.
   I deliberately did NOT touch, revert, or investigate that state — I
   committed my own fix by exact file path only
   (`git commit scripts/mesh_kit.gd scripts/mesh_audit.gd ... `, never
   `git add -A`) specifically so I wouldn't clobber whatever you were
   mid-way through. If that addon/game.gd state is actually *not* yours
   and is a recurrence of the same accidental-editor-rewrite gotcha,
   handle it the same way as before: check `git diff` carefully, confirm
   with Alex before reverting anything that looks intentional.

2. **Gemini CLI will confidently fabricate answers from files it never
   read.** Every `read_file` call can fail silently (default ignore
   patterns exclude images) and it'll still return a detailed, confident,
   completely fabricated report. Verify from the raw log that reads
   actually succeeded before trusting any Gemini CLI output. Full writeup:
   `intelligence/techniques/gemini-cli-hallucinates-on-failed-file-reads.md`.

## Tooling set up tonight (still available)

- **Godot 4.7 stable**: `D:\Projects\godot-4.7-stable\` (both exe
  variants), export templates installed, verified compatible
  (`--import` + `--smoke` clean). Not switched over as primary yet.
- **`godot-mcp`** (Coding-Solo, MIT, no project-side addon) registered as
  a user-scope Claude Code MCP server — should appear in a fresh session's
  tool list. Turned out **not to be needed** for tonight's actual fix — a
  plain headless analytical script (`mesh_audit.gd`) settled the question
  directly and more reliably than live introspection would have. Keep it
  registered regardless; it's still the right tool for genuinely
  runtime-only questions (Alex's own framework: plain-text-edit +
  headless-validate covers most Godot work, MCP/live-introspection is for
  the narrower case where you need actual running-editor state).
- Alex's original MCP suggestion, `gdai-mcp-plugin-godot`, requires going
  through gdaimcp.com directly (possibly paid/account-gated) — not set up,
  didn't sign up for anything without checking first.

## Original investigation notes (superseded by the fix above, kept for context)

Original scope: Alex reported "a lot of flipped normals, but
inconsistently" after inspecting the showcase scene. First pass
(screenshot-only) found nothing definitive and wrongly flagged the city
building as the culprit — corrected above once analytical tooling (not
just visual inspection) was actually applied. Full history including the
separately-resolved floating-mountain investigation:
`intelligence/techniques/godot-asset-showcase-scene-and-floating-mountain-finding.md`
in the KB — this has been updated with tonight's full story, read it for
the complete timeline rather than reconstructing from this file alone.
