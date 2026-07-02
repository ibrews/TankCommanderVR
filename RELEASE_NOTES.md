# Tank Commander VR v0.6.0

## The "solid ground" update
- **Fixed the floating trees / incomplete geometry** from v0.5.0: every prop
  now grounds to the lowest terrain point under its footprint (trees, rocks,
  palms, buildings, castle walls, wrecks, berms, umbrellas, toys), verified
  by an automated per-instance gap checker across all 10 levels.
- **Fixed the flooded-world renderer bug**: water and lava planes fought the
  terrain for depth on Quest's renderer, drowning beaches and islands.
  Water/lava are now painted into the terrain itself — coasts, the island,
  and the volcano caldera (now glowing!) read correctly everywhere.
- Gym court and baby-room floors are perfectly flat; no more wall-base gaps.

## New
- **ENDLESS TOUR mode**: every 3 cleared waves the battle moves to a random
  new battlefield at a random time of day. Score and wave escalation carry;
  your engine arrives already running.
- **HELP ON/OFF** in the menu (remembered between sessions): turns coaching
  voice lines and cockpit hint text off for veterans. New rocket + radio
  tutorial hints for first-timers. The game-over rescue hint always shows.
- New Dad-voice lines for travel, endless mode, and help toggling.
- Cockpit interior dressing: shell ready-rack, stowage, first-aid box,
  pipes, extinguisher, roof ribs (same single draw call).
- Ground macro-color variation — terrain reads varied at any distance.
- Volcano is basalt-dark with emissive lava; tanks refuse to drive into it.

## Perf
- 72/72 FPS locked on Quest 3S, App GPU 9.2 ms avg of 13.8 budget
  (golden-hour beach, full combat demo, glow on).
- Foveation default now 2 (sharper periphery) — A/B measured free.
