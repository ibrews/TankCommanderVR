# Tank Commander VR — controls

## VR (Quest controllers)

### Global (works in any vehicle, on foot, or in the menu)
| Input | Action |
|---|---|
| Right stick click | Toggle 1st / 3rd person camera |
| Left stick click | Restart level (solo) / leave to hangar (co-op, versus) |
| Either menu button | **Pause** — freezes the level in place (solo only; co-op/versus keep running since the other player can't be stopped) and shows the real lobby menu, positioned where you were looking when you paused. Press the same button again with nothing selected to resume exactly where you were. Picking a different vehicle (same level/mode/difficulty/mutator) swaps in place — you keep your wave/score. Picking a different level, mode, difficulty, or mutator does a full restart. |
| Laser pointer (aim pose, or gaze if no hand/controller tracked) + trigger / A-X / menu button | Click menu / pause-menu buttons |
| **Hold LEFT trigger ~1 second (seated, empty hand)** | **Exit the current vehicle** — works in every vehicle, no lever hunt. Plane: ejection seat + parachute. Biplane: bail out + parachute. Airborne helicopter: bail out + parachute. Everything else: climb out beside the vehicle. Haptic ticks confirm the hold is charging. |
| Hold LEFT trigger (on foot, within ~0.6m of a vehicle seat) | Climb back in (grip squeeze still works too) |

### Entering a level
A wide establishing shot (pulled back further than normal 3rd person, ~45° overhead angle, vehicle centered) holds for about a second before you drop into normal control — first or third person, whichever you have selected. Only on a genuine level start, not on a vehicle swap or re-entry.

### Seated in the tank
| Input | Action |
|---|---|
| Two floor tillers (grab + push/pull), or left stick | Drive — push both forward to advance, pull one back to turn, oppose them to spin in place |
| Turret joystick (grab), or right stick | Aim the turret — traverse + elevate |
| Trigger (while gripping the turret stick) | Fire cannon |
| A / X button (while gripping) | Machine gun |
| Breech lever (grab + pull) | Reload after every cannon shot |
| Rocket console: flip safety cover → ARM toggle → big red button | Fire a 2-rocket salvo (mild homing vs. planes) |
| Battery switch → hold green STARTER → gear to D | Full start ritual |
| X button (not gripping) | Quick-start (skips the ritual) |
| B / Y button | Fire rockets (stick fallback) |
| Y button (left hand) | Recalibrate seated position |
| **Yellow HATCH lever (above your seat, grab + pull)** | **Exit the vehicle mid-mission**, on foot. Walk back within ~0.6m of the abandoned vehicle's seat and squeeze either grip to climb back in. |

### Seated in the plane / biplane
| Input | Action |
|---|---|
| Stick + throttle | Flight controls |
| Trigger | Fire weapons (bombs / MG, per vehicle) |
| **Yellow EJECT (plane) / BAIL OUT (biplane) lever** | Exit mid-flight. **Plane:** scripted ejection-seat pop, then you're falling. **Biplane:** falls straight out of the seat, no eject beat. |
| Trigger (while falling, not gripping anything) | Deploy parachute |
| Pull a hand from near your chest outward, across your body (like yanking a ripcord) | Alternate parachute-deploy gesture — same effect as the trigger, for hand-tracking or if you don't want to hunt for the trigger while falling |
| Thumbstick (under canopy) | Drift left/right/forward/back |

### Seated in the jeep
| Input | Action |
|---|---|
| Steering wheel (grab), or left stick X | Steer |
| Throttle lever, or left stick Y | Throttle (down = reverse) |
| Right stick | Aim the rear tank gun (full 360° traverse) |
| Trigger | Fire the rear cannon |
| A / X button | Machine gun |
| Yellow rail lever, or hold LEFT trigger | Exit |

### On foot (RUNNER)
| Input | Action |
|---|---|
| Thumbsticks | Walk / strafe |
| Grip near an item | Pick up (grapple hook, climbing gloves, energy drink, pistol, cabbage grenade) |
| Grip within ~0.6m of an abandoned vehicle's seat | Climb back in |
| Arm-swing (physically pump your arms) | Extra movement speed, layered on top of stick/grapple/climb |
| Grapple hook (equipped) | Aim + trigger to fire, swing |
| Climbing gloves (equipped) | Grab climbable surfaces directly |
| Energy drink (equipped, consumed on use) | Temporary sprint boost |

### Multiplayer
- **Co-op:** host drives + runs the machine gun; the joining player is the gunner (cannon, breech, rockets) in a puppet tank mirroring the host.
- **Versus:** each peer drives their own tank; first to 5 kills wins.

## Desktop (dev/test fallback, no VR headset)
| Key | Action |
|---|---|
| W / A / S / D | Drive |
| Mouse | Look (also steers turret aim in some vehicles) |
| I / K | Turret elevate up / down |
| J / L | Turret traverse left / right |
| Space | Fire cannon |
| R | Cycle the breech (reload) |
| B | Fire rockets |
| M (hold) | Machine gun |
| T | Flip battery switch |
| F | Quick-start |
| V or C | Toggle 1st / 3rd person |
| Backspace | Toggle pause (no clickable panel on desktop — press again to resume) |
| Escape | Release mouse capture |

### Your own body
Your avatar (procedural, Rec-Room-style — round head, visor, simple arms) is visible in **third person only**. It used to also render in first person, where it looked like a confusing second pair of hands floating near your real ones (blue-tinted, since solo play defaults to the "client" color) — now it's hidden there entirely, since your real hand visuals already cover that. Look at yourself in third person to see it.

---
*Updated 2026-07-04 from scripts/xr_rig.gd, scripts/desktop_rig.gd, scripts/menu.gd (HOWTO pages), scripts/game.gd, scripts/main.gd, scripts/player_parachute.gd. Re-derive from those files if this drifts — don't hand-maintain speculative bindings.*
