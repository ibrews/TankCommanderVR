#!/usr/bin/env python3
"""Synchronize Claude entry points and validate the shared project skill pack."""

import argparse
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CANONICAL = ROOT / ".agents" / "skills"
CLAUDE = ROOT / ".claude" / "skills"
EXPECTED = {
    "godot-code-gen", "godot-shader", "tcvr-performance",
    "tcvr-multiplayer", "tcvr-testing",
}


def metadata(path):
    text = path.read_text(encoding="utf-8")
    match = re.match(r"\A---\n(.*?)\n---\n", text, re.DOTALL)
    if not match:
        raise ValueError(f"{path.relative_to(ROOT)}: missing YAML frontmatter")
    fields = {}
    for line in match[1].splitlines():
        key, sep, value = line.partition(": ")
        if not sep or key in fields:
            raise ValueError(f"{path.relative_to(ROOT)}: invalid metadata line {line!r}")
        fields[key] = value.strip()
    if set(fields) != {"name", "description"}:
        raise ValueError(f"{path.relative_to(ROOT)}: expected name and description")
    if fields["name"] != path.parent.name or not re.fullmatch(r"[a-z0-9-]{1,64}", fields["name"]):
        raise ValueError(f"{path.relative_to(ROOT)}: invalid or mismatched name")
    description = fields["description"]
    if not description or any(c in description for c in "\n<>") or ": " in description:
        raise ValueError(f"{path.relative_to(ROOT)}: invalid plain-scalar description")
    return fields, text


def claude_entry(fields):
    name = fields["name"]
    return (
        "---\n"
        f"name: {name}\n"
        f"description: {fields['description']}\n"
        "---\n\n"
        "Read the canonical skill from the repository root at "
        f"`.agents/skills/{name}/SKILL.md` and follow its workflow. "
        "Resolve its optional references relative to that canonical skill folder.\n"
    )


def run(sync):
    skills = {p.parent.name: p for p in CANONICAL.glob("*/SKILL.md")}
    if set(skills) != EXPECTED:
        raise ValueError(f"Expected {sorted(EXPECTED)}, found {sorted(skills)}")
    for name, path in sorted(skills.items()):
        fields, content = metadata(path)
        for target in re.findall(r"\]\(([^)]+)\)", content):
            if "://" not in target and not (path.parent / target).is_file():
                raise ValueError(f"{name}: missing reference {target}")
        for target in re.findall(r"`res://([^`]+)`", content):
            if not (ROOT / target).is_file():
                raise ValueError(f"{name}: missing production file {target}")
        expected = claude_entry(fields)
        wrapper = CLAUDE / name / "SKILL.md"
        if sync:
            wrapper.parent.mkdir(parents=True, exist_ok=True)
            wrapper.write_text(expected, encoding="utf-8", newline="\n")
        if not wrapper.is_file() or wrapper.read_text(encoding="utf-8") != expected:
            raise ValueError(f"{name}: Claude entry out of sync; run --sync")
        metadata(wrapper)
    discovered = {p.parent.name for p in CLAUDE.glob("*/SKILL.md")}
    if discovered != EXPECTED:
        raise ValueError(f"Unexpected Claude skills: {sorted(discovered ^ EXPECTED)}")
    manifest = json.loads((CANONICAL / "sources.json").read_text(encoding="utf-8"))
    for source in manifest["sources"]:
        for key in ("reference", "license"):
            entry = source[key]
            actual = hashlib.sha256((ROOT / entry["path"]).read_bytes()).hexdigest()
            if actual != entry["sha256"]:
                raise ValueError(f"Upstream {key} changed: {entry['path']}")
    print("PASS: 5 canonical skills, 5 matching Claude entries, production paths, references, and upstream hashes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--sync", action="store_true", help="Regenerate Claude entries, then validate")
    mode.add_argument("--check", action="store_true", help="Validate without writing (default)")
    args = parser.parse_args()
    try:
        run(args.sync)
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, f"FAIL: {error}\n")


if __name__ == "__main__":
    main()
