# v0.2.0 — Kids Edition

**Made for Ani** 🧡

Sideload onto a Quest 2/3/Pro: `adb install -r -g TankCommanderVR.apk`

## What's in the box
- **Main menu** with laser pointers: Solo / Co-op / Versus / Plane mode,
  5 battlefields, Easy–Hard, and a narrated 4-page How to Play
- **5 levels**: Outdoor, City, Town, Mudpit (mud slows your tracks),
  Castle (the walls crumble — make your own gate)
- **Physically-operated cockpit** modeled on a real APC driver's station:
  battery → fuel pump → starter → gear ritual, twin tillers, turret grip,
  breech-lever reloads, rocket console under a safety cover, working radio
  volume knob, thermal display, and a horn
- **Enemies**: tanks, strafing planes, MG jeeps, infantry squads, whistling
  mortars — scaled by difficulty
- **LAN multiplayer** (same Wi-Fi, zero config): Co-op (one drives + machine
  gun, the other runs the turret and heavy rockets) and Versus duels
- **Plane mode**: throttle + stick, machine gun, bombs
- Layered combat soundtrack, multi-stage explosions with shockwaves and
  flying debris, controller haptics everywhere
- The tank computer speaks with a familiar voice…

Everything (textures, sounds, music, voice, world) is procedurally
generated. Built overnight with [Claude Code](https://claude.com/claude-code).

---
To publish this release (Alex — one command from the repo root):

    gh release create v0.2.0 out/TankCommanderVR.apk \
      --title "Tank Commander VR v0.2.0 — Kids Edition" \
      --notes-file RELEASE_NOTES.md
