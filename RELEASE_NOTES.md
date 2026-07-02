# v0.3.0 — Kids Edition + The Fun Pass

New in v0.3.0:
- **Weather**: random rainstorms with thunder and lightning, wind gusts,
  dust kicked up by your tracks
- **DAD FM** 📻: the cockpit radio channel knob now tunes real stations —
  including a full morning-zoo talk show. All dad. All day. There is no escape.
- **SILLY MODES** on the menu: LOW-G (bouncing tanks), UNDERWATER (glub glub),
  BALLOON (everything is a party, explosions are confetti pops), PAINTBALL
  (splats everywhere, Rec Room energy)
- **GYM**: a giant school gymnasium battlefield — court floor, bleachers,
  basketball hoops, cardboard forts, bouncy basketballs you can ram
- **Multiplayer avatars**: your co-op crewmate's head floats in the cockpit;
  your versus rival peeks out of their hatch
- **???**: squeeze both grips + both triggers + hold A. You didn't hear it from me.

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

    gh release create v0.3.0 out/TankCommanderVR.apk \
      --title "Tank Commander VR v0.3.0 — Kids Edition + Fun Pass" \
      --notes-file RELEASE_NOTES.md
