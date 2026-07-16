# Tank Commander VR v0.6.27

## The release-prep blitz — controls deconflicted, multiplayer hardened, radio expanded
- **Button fixes (big one):** Y, B, and A each secretly did TWO things per
  press — recalibrating your seat also RESET YOUR WHOLE RUN, firing rockets
  also toggled the HUD, and firing the MG also changed the radio station.
  Now: tap = the common action (recalibrate / rockets / radio), hold = the
  rare one (respawn / HUD toggle), MG unchanged on A-hold. Two-hand chords
  (seat swap, host tools) no longer leak into any of them.
- **Thermal sight actually works now** (the v0.6.25 fix accidentally
  re-broke it a different way), and the display moved off the side window.
- **Multiplayer over the internet (relay) fixed for real:** seat swap, host
  map/difficulty/team changes, and driving after a seat swap were all
  silently dead over the relay — every one now works. Room capped at 2
  players (no more strangers colliding in the shared room), and a host
  disconnect now ends the session cleanly instead of freezing it.
- **Radio: two new stations.** SAIGON FM — a wartime morning-DJ station
  with 16 all-new lines ("GOOOOD MORNING, TANK COMMANDERS!") — and TOUR FM,
  which shuffles every level's music. Radio knob + A-tap both cycle all 7.
- **Other vehicles caught up:** jeep + boat gun elevation had the same
  inversion the tank had; heli's physical yaw pedals were dead (stick was
  overwriting them); parachute drift now agrees between both sticks.
- **Boot is faster** (~1s less startup hitch — voice lines now load in the
  background) and the APK is ~40MB smaller (store art was shipping inside it).
- **5 new easter eggs.** Honk responsibly. Flip switches irresponsibly.
  Basketball counts. Cabbage has consequences. Listen closely on the moon.

# Tank Commander VR v0.6.25

## Live playtest fix batch — controls, camera modes, gunner seat, thermal sight
- **Gunner seat**: swap between a hull-fixed driver view and a turret-fixed
  gunner view (grips+Y in solo, or the existing co-op seat-swap). Solo holds
  the last drive command while you're in the gunner seat.
- **Three camera modes**: first-person, third-person, and a new far
  third-person (another 20' back). Works seated and on foot — on-foot third
  person is now a real chase cam (it never actually pulled back before).
- **Live thermal sight**: the tank's thermal display is a real camera feed
  that tracks the gun's aim now, with a false-color heat-cam look — was a
  static decorative texture before.
- **Fixed**: plane thumbstick steering (was locking up after the first
  input), tank gun elevation was backwards front-to-back, radio knobs
  couldn't actually be turned, controller-model/lever visuals reading
  backwards on the Y axis, on-foot pickup reach (was floor-only), a
  round-timer sync bug over the Cloudflare relay fallback.
- **New**: right-A cycles the radio station in any vehicle; crash logs now
  auto-upload on next boot as a safety net alongside the manual button.

## Known issues going into this build
- Radio silence and "plane roll doesn't respond to the right stick" were
  reported live but did not reproduce in testing (music/talk/roll all
  verified working in a real session) — flag again if still present.
- On-foot third-person black screen: root cause unconfirmed, hardened the
  likely code path (camera transform on mode switch) but couldn't reproduce
  directly.

# Tank Commander VR v0.6.19

## Multiplayer vehicle support + security fix
- **VERSUS mode now supports tank, jeep, boat, and plane** (was silently
  forced to tank regardless of your pick). Co-op stays tank-only for now —
  it needs real driver/gunner seat infrastructure the other vehicles don't
  have yet. Jeep/boat opponents replicate position correctly but their gun
  doesn't visibly track aim yet (their meshes are one fused piece, unlike
  the tank's separate turret — a follow-up item).
- Fixed a real, separate co-op bug found along the way: the coax machine gun
  never actually fired for whoever was in the gunner seat as the client.
- Rotated a Cloudflare relay token that had been committed in plaintext.

# Tank Commander VR v0.6.18

## The big overnight batch
- **MP join crash fixed** — joining a host no longer crashes the host.
- **Spider-Man powers are earned, not free** — grapple and climb only work
  after you find the pickups; climbing now works on terrain, buildings,
  rocks, trees, and castle walls, not just a narrow allowlist.
- **Coffee** is a real pickup now (reflex/reload boost); energy drink got a
  proper drink animation (fizz, gulp, crushed can).
- **Weather**: fog joins rain/storm. **Volcano** is a real level with
  flowing lava and lethal eruptions (no more grass on the volcano — basalt/
  ash/steam only). The baby-room boss can finally be killed.
- **Multiplayer**: round timer + live score + end-of-round tally, host
  god-mode (change map/mode/difficulty, spawn bots — two-hand-grip
  gestures), co-op seat-swap hotkey, player names, team colors.
- **"Four arms" avatar bug fixed** — the controller model and the hand
  glove were both rendering at once.
- **Vehicles**: right trigger drives every vehicle forward now; the jeep
  got a real steering wheel; the plane spawns facing into the map instead
  of away from it; runner mode got snap/smooth turning and a stick-sprint
  option.
- **Persistent-host fallback**: if no one's on your Wi-Fi, the game now
  falls back to an online relay room automatically, with reconnect. New
  "Upload Log" button in the menu ships your session log for support
  without ever plugging the headset in.
- 3 new weapons (burst SMG, mini-howitzer, close-range spread gun); fixed
  the store page's 360° preview image (4 of 6 faces were mirrored wrong).

# Tank Commander VR v0.6.9 – v0.6.17

## Vehicles, avatars, and lobby polish
- New **JEEP** vehicle (open-top 4x4, rear-mounted tank gun).
- Real Rec Room-style procedural avatars — helmet, vest, backpack, belt,
  shoulder pads — with a proper arm-IK fix (arms used to solve toward the
  map origin instead of your actual hand position).
- Grapple/climb-the-world added (later gated behind pickups in v0.6.18).
- Controller aim pose now always wins the menu ray over hand-tracking, so
  the menu doesn't get hijacked when both are active at once.
- Lobby: live vehicle turntable, level diorama preview, framerate fix
  (previews no longer build full mission-grade collision).
- THE MOON — a sphere-gravity bonus level.
- Fixed the periscope glass rendering as solid white (a recurring Mobile-
  renderer alpha-blend bug — the glass pane was removed rather than
  re-tuned a third time), left-stick Y-axis settled, enemy spawn rings
  brought closer in.

# Tank Commander VR v0.6.5 – v0.6.8

## On-foot mode, real hands, and the pause menu
- **On-foot locomotion** (dismount your vehicle, walk/sprint/grapple/climb)
  built on `godot-xr-tools`, with full procedural avatars for seated and
  on-foot crew alike.
- **The controller pose bug, finally found**: `XRController3D` pose names
  were the action-map names instead of the engine's own names, so
  controller poses never resolved at all — this silently broke the glove
  visual, hatch levers, and on-foot movement together, and turned out to be
  the root cause behind several rounds of earlier "hands are broken"
  investigation.
- Pause menu now freezes the level in place instead of tearing it down;
  quitting to the hangar is a deliberate choice from that menu.
- AI tanks bias their patrol toward the player instead of wandering fully
  at random — first contact used to sometimes take a very long time.
- Every generated mesh (boxes, cylinders) had been rendering inside-out
  since v0.1 — Godot's front-face winding is clockwise, not the convention
  everything was originally built against. Fixed globally.

# Tank Commander VR v0.6.4

## Hand position fix (round 4)
- Real lead from v0.6.3's debug numbers: pinch/grip values were changing
  correctly, but hands still couldn't hover/grab anything — meaning the
  game didn't know WHERE your hand actually was. Found it: the OpenXR
  extension that makes bare-hand pinch/grasp map to trigger/grip also
  synthesizes a controller-style position that isn't your real tracked
  hand position, and the game was preferring that stale synthesized
  position over the real one. Now prefers the real hand-tracking position
  whenever it's available.

# Tank Commander VR v0.6.3

## More VR hands fixes (round 3)
- **Reverted the "every material two-sided" fix from v0.6.2** — it made the
  cockpit interior worse (the tank's outer hull, previously correctly hidden
  from inside, started showing through as a big flat panel). The actual
  flipped-normal bugs still need individual fixes, not a blanket change.
- **Controller model relit** — it was on the same dim lighting group as the
  cockpit walls, which likely made it read as nearly invisible even when
  correctly positioned. Now lit normally.
- **Hands now show a small colored dot at the fingertip**: white/neutral by
  default, yellow when near something grabbable, green while holding it —
  so you can see whether the game even detects your hand near something.
- Added an on-device debug readout (small text, always in view) showing
  live tracking/grip/trigger numbers per hand — temporary, to figure out
  exactly what's still not working with hand-tracking interaction.

# Tank Commander VR v0.6.2

## VR hands fixes
- **Controller model now actually renders on Quest 3S** — v0.6.1's controller
  model used a Meta OpenXR extension that turns out unsupported on this
  specific headset (worked on paper, invisible in practice). Swapped to a
  bundled model that's animated by hand instead.
- **Bare hands can now grab and interact**: pinch (thumb+index) fires the
  trigger, squeeze the other three fingers to grip — matches the "hands
  work too" hint that's been on the main menu all along.
- **Fixed a pile of inside-out-looking geometry** (flipped normals) —
  every material renders both sides for now.
- **Version + build time on the main menu** (bottom-left corner) — so you
  can always tell which build you're actually running.

# Tank Commander VR v0.6.1

## VR hands update
- **Real Touch controller model**: both hands now show the actual runtime
  controller geometry (fetched live from the OS, animated by real button/
  trigger/thumbstick input) instead of a placeholder box.
- **Real hand-tracking mesh**: set the controllers down and your actual
  hand shape appears, posed live from Quest hand tracking.
- Fixed VR controllers/hands not being tracked at all on some sessions
  (an OpenXR extension flag gap that could silently break every controller
  binding, not just hand tracking).

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
