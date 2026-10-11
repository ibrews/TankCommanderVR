#!/usr/bin/env bash
# Export from a named worktree with explicit engine, profile, and artifact paths.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
exec python "$repo_root/tools/build_quest.py" "$@"
