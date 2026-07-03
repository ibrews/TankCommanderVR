# Handoff — asset showcase geometry investigation (2026-07-03)

For whichever Claude Code session picks this up overnight. Read this fully
before touching anything — two real near-misses happened in the session
that produced this handoff; don't repeat them.

## Why this exists

Alex built the asset showcase scene (`scenes/asset_showcase.tscn`,
`scripts/asset_showcase.gd`) last session to visually audit every
procedurally-generated model in the game. Alex is now reporting "a lot of
flipped normals, but inconsistently" across the showcase. This handoff
parks a partial investigation and sets up tooling for whoever continues it.

Full background: [`intelligence/techniques/godot-asset-showcase-scene-and-floating-mountain-finding.md`](../../knowledge/intelligence/techniques/godot-asset-showcase-scene-and-floating-mountain-finding.md)
in the KB (`C:\Users\Sam\knowledge`) — read this first, it has the complete
history including the floating-mountain root cause (already solved,
separate issue) and today's update section.

## What's actually confirmed so far

**Clean (no flipped normals, verified by direct screenshot inspection):**
player/enemy vehicles, village house (prism roof), castle keep roof (prism),
castle corner tower (cylinder caps), trees, rocks. These are the exact
primitives that had a real winding-order bug in a *previous* session
(fixed already, see daily log "checkpoint ~14:40" 2026-07-02) — re-checked
and still fixed.

**One confirmed, reproducible, NOT-yet-root-caused bug:** `CITY BUILDING`
(the `tall=true` branch of `WorldDressing._building()`) renders like its
exterior wall is invisible from a clean ~20m-away outside vantage — you see
what looks like an interior corner (two walls + a window-patterned
"ceiling"/"floor") with no exterior silhouette against the sky. Reproduced
from two different camera distances/angles, so it isn't a too-close-camera
artifact. The `tall=false` village house, built by the *identical* code
path at smaller scale, renders correctly. Candidates not yet checked:
scale-dependent behavior, the `uv_scale=0.12` tiling branch in
`MeshKit.box()` (only used when `tall=true`), the roof-cap box sitting
exactly flush with the wall-top (`hgt` vs `hgt+0.25`).

**Alex still perceives more issues than this ("a lot... inconsistently")**
— the investigation so far has been screenshot-based (Read tool loading
PNGs from `TC_SHOWCASE_SHOT=1` renders) and spot-checked maybe 10 of the
~30 showcase specimens closely. This was NOT an exhaustive per-object
audit. That's the main gap to close — see "Suggested loop" below.

## Two gotchas from tonight — read before doing anything

1. **The Godot editor can silently rewrite `project.godot`.** It happened
   tonight from opening a second editor process via computer-use
   (`open_application` on the bare .exe, no `--path`) — the editor dumped
   its in-memory ProjectSettings back to disk, dropping hand-written
   comments and several non-default settings including the load-bearing
   `openxr/extensions/meta/render_model=false` line (Quest 3S doesn't
   support that extension — see the comment that was there) and the action
   map reference. Caught via `git diff` before it was committed, reverted
   with `git checkout -- project.godot openxr_action_map.tres .gitignore`.
   **Rule: `git status`/`git diff` after ANY Godot editor GUI interaction,
   before committing anything, every time.** Full writeup:
   `intelligence/techniques/godot-editor-silently-rewrites-project-godot.md`.
   The original task boundary still applies: **do not modify
   `project.godot`'s [xr]/rendering settings or `export_presets.cfg`, and
   do not touch the App Lab upload pipeline.**

2. **Gemini CLI will confidently fabricate answers from files it never
   read.** Tried `gemini -p ... --include-directories out` to offload the
   screenshot QA pass — every single `read_file` call failed silently
   (Gemini CLI's default ignore patterns exclude images from that tool),
   and it still returned a detailed, specific, completely fabricated
   16-item defect report. Only caught by reading the full raw stdout
   (including the tool-error lines), not just the final answer. **If you
   use Gemini CLI for anything file-based, verify from the raw log that
   the reads actually succeeded before trusting the answer.** Full
   writeup: `intelligence/techniques/gemini-cli-hallucinates-on-failed-file-reads.md`.

## New tooling set up tonight

- **Godot 4.7 stable** installed at `D:\Projects\godot-4.7-stable\`
  (`Godot_v4.7-stable_win64.exe` / `_console.exe`), export templates
  installed at `%APPDATA%\Godot\export_templates\4.7.stable\` (Windows +
  Android templates present). Verified: `--headless --import` and
  `-- --smoke` both run clean against this project under stable — **not
  yet switched over as the project's primary engine** (`tools/build_apk.sh`
  and the `.tscn` file association still point at beta3, deliberately, so
  this is a decision to make with Alex, not something to just do).
- **`godot-mcp`** (Coding-Solo, MIT, 4.5k★, github.com/Coding-Solo/godot-mcp)
  registered as a Claude Code MCP server at **user scope** — will be
  available once you start a fresh session or reconnect
  (`claude mcp list` should show `godot: ... - ✔ Connected`). No Godot-side
  addon required (lower risk than the alternatives — doesn't touch the
  project itself). `GODOT_PATH` env is set to the new 4.7 stable console
  exe. Exposes: launch/run/stop the editor, capture debug output, project
  analysis, create/modify scenes+nodes, export MeshLibrary, UID management.
  **This is the tool to use for root-causing the city-building bug** —
  should let you query the actual mesh/material state (surface count,
  `cull_mode`, node transforms) instead of inferring from screenshots.
- Alex's original suggestion, `3ddelano/gdai-mcp-plugin-godot`, turned out
  to require going through gdaimcp.com directly (the GitHub repo is just a
  demo project, not the installable addon/server) — possibly a paid/
  account-gated product, didn't investigate further or sign up for
  anything without checking first. Flag this back to Alex if `godot-mcp`
  doesn't pan out and a second option is wanted.
- A handful of other open-source Godot MCP servers exist if `godot-mcp`
  turns out to be insufficient: `tugcantopaloglu/godot-mcp` (149 tools,
  broader scope), `mkdevkit/godot-mcp`, `hi-godot/godot-ai`. Not evaluated
  in depth — `godot-mcp` was picked for being the most established
  (star count) with the simplest, addon-free install.

## Suggested loop for tonight

1. **Root-cause the city building bug first** — it's the one confirmed,
   reproducible lead. Use `godot-mcp` to inspect the live `walls`
   MeshInstance3D on a running showcase instance: surface material
   `cull_mode`, actual mesh AABB, and ideally the raw vertex winding.
   Compare directly against the village house's `walls` mesh (same
   function, different size) to isolate what actually differs.
2. **Then do the exhaustive per-object audit Alex is actually asking for.**
   Don't spot-check — go through all ~30 showcase specimens systematically
   with `godot-mcp` queries (material cull_mode, mesh face counts) cross-
   referenced against a close-up screenshot per object
   (`TC_SHOWCASE_SHOT=1`, extend `_DEBUG_WAYPOINTS` in `asset_showcase.gd`
   as needed — waypoints already exist for most structures). Build a
   simple checklist/table as you go (pass/fail/uncertain per object) so
   the next session — or Alex — can see coverage at a glance, not just
   vibes. If you find more real issues, add them to the KB doc's list
   rather than starting a new document (one topic, one doc).
3. **If you find and fix a real bug**, that means editing `world_dressing.gd`
   or `mesh_kit.gd` (real gameplay code) — that's fine and expected for an
   actual fix, unlike the showcase-building task which was add-only. Just:
   verify with `git diff` before every commit (gotcha #1 above), re-run
   `--smoke` after any gameplay-code edit, and re-render the showcase
   (`TC_SHOWCASE_SHOT=1`) to confirm the fix visually before calling it done.
4. **Don't go chase the floating-mountain illusion further** — that one's
   already understood (perspective foreshortening, not a bug) with a
   proposed mitigation (steepen the rim's inner smoothstep edge in
   `terrain.gd`) sitting in the KB doc, unapplied. It's a polish call, not
   a bug fix — leave it for Alex to decide, don't implement without asking.
5. **If you get properly stuck or hit something that would require
   touching `project.godot`'s XR/rendering settings or `export_presets.cfg`
   to fix, stop and leave a clear note instead of guessing** — that
   boundary was set deliberately in the original task and should stay in
   place unless Alex explicitly lifts it.
6. Log real findings to the KB as you go (checkpoints, not just at the
   end) — same convention as always, `daily/2026-07-03-fort.md` +
   the showcase KB doc.

Good luck — the tooling gap (screenshots only, no structured introspection)
is now closed. Use it before falling back to more eyeballing.
