#!/usr/bin/env python3
"""Deterministic, zero-AI check for scripts/asset_showcase.gd's
DEBUG_FACING / TC_FACING_TOUR debug-facing shader output.

The shader (see asset_showcase.gd's _debug_facing_mat()) colors every
triangle solid green (front-facing, correct) or solid red (back-facing --
a real, GPU-computed fact about that exact camera vantage, not an opinion)
with everything else in the scene (UI labels, sky) left alone. Whether a
render "has real red in it" is therefore a plain pixel-color threshold
question -- it needs zero vision model, local or frontier, to answer.

Per the KB's "build tools that run without AI" principle: this exists so
nobody has to spend a human's eyes or a model's tokens re-checking a
render that a script can check for free, forever. Only images this script
flags should ever need a human or a model to actually look at them.

Usage:
    python tools/analyze_facing_debug.py out/showcase_*.png
    python tools/analyze_facing_debug.py out/debug_facing_*.png --threshold 2.0

Requires ImageMagick's `magick` on PATH (already used by tools/build_apk.sh's
own screenshot pipeline conventions on this fleet).
"""
import argparse
import subprocess
import sys

# NOT _debug_facing_mat()'s raw ALBEDO values (1.0,0.05,0.05) / (0.15,0.95,0.15) --
# Godot's default Environment tonemap/post-process pipeline shifts those before
# they hit the saved PNG, even with an unshaded shader. Verified by sampling
# actual output pixels directly (magick out.png -format "%[pixel:p{x,y}]" info:)
# rather than trusting the shader source: real red is (255,79,79), real green
# is (139,253,139). A first version of this script used the raw ALBEDO values
# and silently reported 0% on an image that was visibly mostly red -- caught
# only because a human looked at the actual picture. Lesson: verify a script
# like this against a known-bad case before trusting a clean result from it.
RED = "rgb(255,79,79)"
GREEN = "rgb(139,253,139)"
FUZZ = "8%"  # tighter now that the base target color is actually correct


def red_percentage(path: str) -> float:
    """Percentage of pixels matching the debug shader's red (back-facing) color."""
    # Build a black/white mask (white = matches red within fuzz tolerance),
    # then the mask's mean brightness (0..1 -> 0..100) IS the red-pixel percentage.
    cmd = [
        "magick", path,
        "-fuzz", FUZZ,
        "-fill", "white", "-opaque", RED,
        "-fill", "black", "+opaque", "white",
        "-format", "%[fx:mean*100]",
        "info:",
    ]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return float(out.stdout.strip())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("images", nargs="+", help="PNG files to check")
    ap.add_argument("--threshold", type=float, default=1.0,
                     help="red%% above this is flagged FAIL (default: 1.0)")
    args = ap.parse_args()

    flagged = []
    print(f"{'FILE':<55} {'RED%':>8}  VERDICT")
    print("-" * 80)
    for path in args.images:
        try:
            pct = red_percentage(path)
        except subprocess.CalledProcessError as e:
            print(f"{path:<55} {'ERR':>8}  {e.stderr.strip()[:60]}")
            continue
        verdict = "FAIL — real backface" if pct > args.threshold else "clean"
        print(f"{path:<55} {pct:>7.3f}%  {verdict}")
        if pct > args.threshold:
            flagged.append((path, pct))

    print("-" * 80)
    if flagged:
        print(f"{len(flagged)}/{len(args.images)} flagged above {args.threshold}% red "
              f"— worth an actual look (human or model), not a re-run of this script:")
        for path, pct in sorted(flagged, key=lambda t: -t[1]):
            print(f"  {pct:6.3f}%  {path}")
        return 1
    print(f"0/{len(args.images)} flagged — nothing here needs eyes on it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
