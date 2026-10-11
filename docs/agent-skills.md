# Godot skills for Claude Code and Codex

This repository includes five focused skills for Tank Commander VR. They lead
with the game's procedural GDScript architecture, Godot 4.7 Mobile renderer,
OpenXR setup, and existing verification tools.

| Skill | Example task |
| --- | --- |
| `godot-code-gen` | Review a cockpit control's lifecycle across vehicle swaps. |
| `godot-shader` | Improve terrain shading while preserving vertex colors and stereo rendering. |
| `tcvr-performance` | Measure the cost of shadows and foveation in the same Quest workload. |
| `tcvr-multiplayer` | Check seat-swap behavior over both ENet and the JSON relay. |
| `tcvr-testing` | Select a production harness and inspect its actual assertions. |

Open this repository checkout as the working project. Codex discovers
`.agents/skills`; Claude Code discovers `.claude/skills`. The Claude entry points
load the same canonical skill instructions, avoiding two maintained copies.
For explicit invocation, use `$tcvr-performance` in Codex or
`/tcvr-performance` in Claude Code. Existing sessions may need to reopen the
project to refresh discovery. Skills in this repository do not become global
skills in unrelated projects or chats.

Validate with `python tools/agent_skills.py --check` (standard-library Python 3).
After changing skill metadata, regenerate the Claude entry points with
`python tools/agent_skills.py --sync`. The check verifies matching names and
descriptions, reference links, named production files, and upstream file hashes.
Hashes use LF-normalized text so Git's Windows newline conversion does not
invalidate an otherwise unchanged reference. `.gitattributes` keeps new skill
checkouts on LF. The validator also supports existing CRLF working copies.
It does not prove gameplay, shader compilation, frame rate, or model behavior.

## Sources and adaptation

The GDScript and shader skills include original reference material from
[alexmeckes/godot-claude-skills](https://github.com/alexmeckes/godot-claude-skills),
pinned to commit `881ff9d285b8dfa5e343ce1b32bdcff367fe89f8`:

- `skills/godot-code-gen/SKILL.md`
- `skills/godot-shader/SKILL.md`

The downloaded files had no skill frontmatter. They are retained unchanged as
`references/upstream.md`, together with their upstream MIT license. New canonical
entry points provide valid discovery metadata and project-specific workflows.
The original examples are optional reference material, not verified production
snippets. Their source URLs, commit, and SHA-256 hashes are recorded in
`.agents/skills/sources.json`.

The performance, multiplayer, and testing skills are authored for this project,
based on its checked-in source, README, and existing test harnesses. Their content
uses the repository's MIT license. No LGPL library code, generic VR policy,
automatic delegation, editor bridge, or new external service is bundled.

The libraries evaluated during selection are linked for further exploration:
[Godot Game Dev Studio](https://github.com/bgrenat/godot-game-dev-studio),
[GD Agentic Skills](https://github.com/thedivergentai/GD-Agentic-Skills), and
[gamestack](https://github.com/rondorkerin/gamestack).

The documented 72 Hz target remains the performance reference. The retained
historical GPU measurement needs a fresh device pass. Logic tests, rendered
desktop captures, and headset acceptance remain separate kinds of evidence.
