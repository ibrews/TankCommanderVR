# Tank Commander VR — controls

## VR (Quest controllers)

### Global (works in any vehicle, on foot, or in the menu)
| Input | Action |
|---|---|
| Right stick click | Toggle 1st / 3rd person camera |
| Left stick click | Restart level (solo) / leave to hangar (co-op, versus) |
| Either menu button | **Pause** — freezes the level in place (solo only; co-op/versus keep running since the other player can't be stopped) and shows a RESUME / QUIT TO HANGAR panel. Press again to resume without it. |
| Laser pointer (aim pose, or gaze if no hand/controller tracked) + trigger / A-X / menu button | Click menu / pause-panel buttons |

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

---
*Generated 2026-07-03 from scripts/xr_rig.gd, scripts/desktop_rig.gd, scripts/menu.gd (HOWTO pages), scripts/game.gd. Re-derive from those files if this drifts — don't hand-maintain speculative bindings.*
