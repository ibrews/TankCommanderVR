# Tank Commander VR agent guidance

Read `README.md` and the affected source before making changes. This is a Godot
4.7 project using the Mobile renderer and OpenXR for standalone Quest. Game
content is built procedurally in GDScript; scene files provide entry points and
test harnesses. Preserve this approach unless the task requests an architecture
change. Keep the engine version and renderer bound to `project.godot`.

Select the relevant project skill; do not load every reference:

| Task | Skill entry point |
| --- | --- |
| GDScript implementation or review | `.agents/skills/godot-code-gen/SKILL.md` |
| Materials, shaders, or visual effects | `.agents/skills/godot-shader/SKILL.md` |
| Frame time, draw calls, memory, or performance | `.agents/skills/tcvr-performance/SKILL.md` |
| LAN, relay, authority, or replicated gameplay | `.agents/skills/tcvr-multiplayer/SKILL.md` |
| Gameplay checks, capture, or regression verification | `.agents/skills/tcvr-testing/SKILL.md` |

Codex discovers `.agents/skills`; Claude Code discovers the thin entry points in
`.claude/skills`. Both lead to the same maintained instructions. After editing
skill metadata, run `python tools/agent_skills.py --sync`, then
`python tools/agent_skills.py --check`.

Use the existing `Game`, `Tune`, `Sfx`, and `NetManager` autoloads and production
control APIs. Read the implementation before treating historical test comments
as current behavior. Run focused checks appropriate to the change; distinguish
logic verification, desktop rendering, and on-headset results.

Work in an isolated checkout for project edits. Route generated artifacts, logs,
temporary files, and Godot user data to an appropriate data volume under the
host's operating rules. Keep third-party licenses and pinned source metadata.
