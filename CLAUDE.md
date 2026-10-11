@AGENTS.md

For Godot tasks, select the matching skill from `.claude/skills`. Each entry
points to the canonical instructions under `.agents/skills`; resolve those
paths from the repository root. Load the selected skill's optional references
only when they are relevant to the current task.

For real OpenXR acceptance, use scenes/xr_audit.tscn and tools/xrsim_audit.mjs
with our xrsim Meta backend and Operator layer; see docs/audit-2026-10-11.md.
Export Quest APKs from a named worktree with tools/build_quest.py under the
host build lease. Supply isolated profile/output paths on a data volume.
For alpha updates, also require the existing release certificate with
--expected-signer-sha256; see the audit's signing boundary before retrying upload.
