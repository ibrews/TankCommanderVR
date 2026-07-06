Both GOOGLE_API_KEY and GEMINI_API_KEY are set. Using GOOGLE_API_KEY.
Both GOOGLE_API_KEY and GEMINI_API_KEY are set. Using GOOGLE_API_KEY.
Here are 9 low-effort, high-impact feature ideas ranked by fun-per-effort:

1. **Cabbage Cartastrophe:** When the cabbage merchant's cart takes damage, it erupts into a ridiculous, physics-heavy shower of green spheres.
   - *Approach:* In `destructible_prop.gd` or `npc.gd`, loop 50 times on destruction to instantiate green procedural `SphereMesh` `RigidBody3Ds` with random outward velocities.

2. **SUPER FIZZ MAX Jitters:** Consuming the energy drink makes the player's virtual hands visually shake for the duration of the buff.
   - *Approach:* Add a `shake_intensity` multiplier in `avatar_rig.gd` or `xr_rig.gd` applied to the hand mesh transforms, driven by a timer triggered from `interactables.gd`.

3. **Spaghetti Grapple:** The procedural grapple line used for the Spider-Man climbing power is bright yellow and wobbly, resembling cooked pasta.
   - *Approach:* In `player_alt.gd`, update the grapple line rendering to use a yellow material and apply a simple sine wave offset to the geometry points.

4. **Sarcastic Weather Announcements:** Weather changes trigger a lo-fi, procedural "voice" (beeps) and a subtitle expressing inappropriate enthusiasm (e.g., "Oh boy, extreme fog!").
   - *Approach:* Hook into the state change in `weather.gd` to trigger randomized synth bleeps from `audio.gd` and push a subtitle string to the UI.

5. **Googly Eye Avatars:** A multiplayer cosmetic that attaches procedurally generated, physically wobbly googly eyes to the player's avatar helmet.
   - *Approach:* In `avatar_cosmetics.gd`, build two white spheres with black child spheres, attach them to the head, and apply a basic jiggle offset based on head velocity.

6. **Jeep Horn of Despair:** Honking the horn in the jeep plays a muffled, pitched-up procedural scream instead of a standard mechanical beep.
   - *Approach:* Swap the horn's synth frequency generation in `player_jeep.gd` and `audio.gd` to a discordant, rapidly oscillating noise profile.

7. **Volcanic Product Placement:** The volcano occasionally erupts, launching a massive, glowing SUPER FIZZ MAX can into the sky like a ballistic missile.
   - *Approach:* Add a timer in `levels.gd` that periodically instantiates a scaled-up glowing cylinder (via `mesh_kit.gd`) with a strong upward physics impulse.

8. **Passive-Aggressive Scoreboard:** The end-game UI appends a randomized, minor insult to the lowest-scoring player (e.g., "Player 3: Barely Participated").
   - *Approach:* Modify the scoreboard population loop in `game.gd` or `menu.gd` to append a random string from a hardcoded array to the last place player's label.

9. **Fake Award Splash Screen:** The game boot screen boldly claims "Winner of 14 Fake Awards" in a generic font before fading out.
   - *Approach:* Add a simple fading `Label` node with this text to the initialization sequence in `splash.gd`.
