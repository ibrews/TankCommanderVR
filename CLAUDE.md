@AGENTS.md

For Godot tasks, select the matching skill from `.claude/skills`. Each entry
points to the canonical instructions under `.agents/skills`; resolve those
paths from the repository root. Load the selected skill's optional references
only when they are relevant to the current task.
