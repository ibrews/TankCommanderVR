# Headless gameplay QA (Goal 3, overnight 2026-07-03): exercises real
# gameplay logic end-to-end, not just static geometry. Reuses the REAL
# scenes/main.tscn unmodified (instantiated as a child, same "don't
# reimplement production code" pattern asset_showcase.gd already
# established for WorldDressing) — same _ready(), same menu, same
# EnemyManager, same Game autoload — so a real state-machine bug shows up
# exactly as it would in normal play, not laundered through a stub.
#
# Deliberately does NOT edit scripts/main.gd (contested — a sibling
# session is mid-flight on an on-foot feature there) — everything here
# drives the real game through its existing public API (Game autoload,
# main_inst.player/menu/world) the same way tools/*.gd's --smoke/--shots
# modes already do internally.
#
# Enemies are force-killed directly (take_damage(99999, pos)) to drive wave
# progression deterministically and quickly — this is a QA tool proving the
# WAVE-TRANSITION LOGIC works, not a simulation of human aiming skill.
#
# Run: godot --headless --path . scenes/gameplay_qa.tscn  (auto-quits when done)
extends Node3D

var main_inst: Node3D
var _results := []


func _log(check: String, ok: bool, detail: String = "") -> void:
	_results.append({"check": check, "ok": ok, "detail": detail})
	print("[gameplay_qa] %s: %s%s" % [check, ("PASS" if ok else "FAIL"), ("  (%s)" % detail) if detail else ""])


func _ready() -> void:
	main_inst = load("res://scenes/main.tscn").instantiate()
	add_child(main_inst)
	await get_tree().create_timer(1.0).timeout
	await _test_solo_flow()
	await _test_coop_vs_menu_wiring()
	_print_summary()
	get_tree().quit(0)


func _find_enemy_manager() -> Node:
	if main_inst.world == null:
		return null
	for c in main_inst.world.get_children():
		if c is EnemyManager:
			return c
	return null


func _test_solo_flow() -> void:
	print("\n===== SOLO: menu -> drive/fire/reload -> waves -> game over -> menu -> restart =====")
	Game.mode = Game.Mode.SOLO
	_log("menu visible before start", Game.state == Game.GState.MENU)
	main_inst.menu.start_requested.emit(Game.Mode.SOLO, "outdoor", 1, "")
	await get_tree().create_timer(2.0).timeout

	var player = main_inst.player
	_log("state == PLAYING after start_requested", Game.state == Game.GState.PLAYING)
	_log("player tank instantiated", player != null)
	if player == null:
		_log("solo flow aborted", false, "no player — cannot continue this phase")
		return

	# ---- drive/fire/reload cycle ----
	player.quick_start()
	await get_tree().create_timer(0.6).timeout
	player.set_stick_drive(Vector2(0.2, 1.0))
	await get_tree().create_timer(1.0).timeout
	player.set_stick_drive(Vector2.ZERO)
	_log("drive stick did not crash the vehicle", is_instance_valid(player))

	# Cannon is semi-auto with a real reload cycle, NOT "fire decrements ammo
	# instantly" — read from source before assuming a bug (player_tank.gd):
	# fire_cannon() only fires if `loaded` (starts true), sets loaded=false
	# and (for stick-fire) auto_reload=true/auto_reload_t=2.6; ammo itself
	# only decrements later in _chamber(), once auto_reload_t elapses AND
	# `not loaded`. So: shot 1 fires "for free" (pre-loaded round), and ammo
	# only drops ~2.6s later when the round auto-chambers. Test the REAL
	# cycle, not an instant-decrement assumption.
	var loaded_before: bool = player.loaded
	player.stick_fire()
	await get_tree().create_timer(0.3).timeout
	_log("first cannon shot consumes the pre-loaded round", loaded_before and not player.loaded,
		"loaded %s -> %s" % [loaded_before, player.loaded])
	var ammo_before_reload: int = player.ammo
	await get_tree().create_timer(3.2).timeout   # auto_reload_t=2.6s + margin
	_log("cannon auto-reloads (ammo decrements, loaded goes true) ~2.6s after firing",
		player.loaded and player.ammo == ammo_before_reload - 1,
		"loaded=%s ammo %d -> %d" % [player.loaded, ammo_before_reload, player.ammo])

	var rockets_before: int = player.rockets_left
	player.stick_rockets()
	await get_tree().create_timer(0.4).timeout
	_log("rocket fire did not crash (armed-gate may block first press)", is_instance_valid(player),
		"rockets_left %d -> %d, armed=%s" % [rockets_before, player.rockets_left, player.rockets_armed])

	player.set_mg(true)
	await get_tree().create_timer(0.5).timeout
	player.set_mg(false)
	_log("MG hold/release did not crash", is_instance_valid(player))

	# Soak test: fire-and-wait-for-reload repeatedly (respecting the real
	# ~2.6-3s cycle, not spamming faster than the weapon can cycle) and
	# confirm ammo trends down over a real magazine's worth of cycles.
	var ammo_soak_start: int = player.ammo
	for i in 6:
		if player.loaded:
			player.stick_fire()
		await get_tree().create_timer(3.0).timeout
	_log("ammo trends down over multiple real fire/reload cycles", player.ammo < ammo_soak_start,
		"ammo %d -> %d over 6 cycles" % [ammo_soak_start, player.ammo])

	# ---- wave progression (force-kill to drive it deterministically) ----
	# _spawn_wave() only fires once `alive==0` has held for `_between`
	# seconds (4.0s initially, 8.0s after any wave has spawned) — read from
	# enemy_manager.gd before assuming a bug. Wait long enough per round.
	var em := _find_enemy_manager()
	_log("EnemyManager present in the running level", em != null)
	var waves_seen: Array = [Game.wave]
	var wave_conn := func(w): waves_seen.append(w)
	Game.wave_changed.connect(wave_conn)
	if em:
		for round_i in 3:
			for i in 120:  # wait for _spawn_wave() to populate this round
				if em.get_child_count() > 0:
					break
				await get_tree().process_frame
			var killed_this_round := 0
			for e in em.get_children():
				if not is_instance_valid(e):
					continue
				if e.has_method("take_damage"):
					e.take_damage(999999.0, e.global_position)
					killed_this_round += 1
				elif "hp" in e:
					e.hp = 0
					killed_this_round += 1
			await get_tree().create_timer(9.0).timeout   # > _between's 8.0s worst case
			print("[gameplay_qa]   round %d: force-killed %d enemies, wave now %d" % [round_i, killed_this_round, Game.wave])
	Game.wave_changed.disconnect(wave_conn)
	_log("wave advanced at least twice via force-kill", waves_seen.size() >= 2, "waves seen: %s" % [str(waves_seen)])

	# ---- death: game_over signal, but NO automatic menu return ----
	# Confirmed from source (player_tank.gd/game.gd): death just sets
	# alive=false + emits game_over — nothing listens to that signal to call
	# to_menu(). Returning to the level requires physically pulling the
	# cockpit "restart" lever (Game.restart(), same level); returning to
	# the actual main menu requires toggling the separate "menu_switch"
	# cockpit control. Test the REAL two paths, not an assumed auto-return.
	# NOTE: a plain `var flag := false` mutated inside a lambda does NOT
	# propagate to this outer scope — GDScript lambdas capture local
	# variables BY VALUE, not by reference (only reference types like
	# Array/Dictionary/Object share state with the outer scope, which is
	# why `waves_seen.append(w)` above worked). Use a 1-element array as a
	# mutable box instead — a real gotcha this test hit on its first run.
	var game_over_box := [false]
	var go_conn := func(): game_over_box[0] = true
	Game.game_over.connect(go_conn, CONNECT_ONE_SHOT)
	player.take_damage(999999.0, player.global_position)
	await get_tree().create_timer(1.0).timeout
	_log("game_over signal fired on death", game_over_box[0])
	_log("Game.alive false after death", not Game.alive)
	_log("state stays PLAYING after death (by design — no auto-menu-return)", Game.state == Game.GState.PLAYING,
		"state=%d (confirms death doesn't silently strand the player in a broken state)" % Game.state)
	if Game.game_over.is_connected(go_conn):
		Game.game_over.disconnect(go_conn)

	# ---- restart lever: respawn in the SAME level ----
	var c: Dictionary = player.cockpit.get("controls", {})
	if c.has("restart"):
		c["restart"].value_changed.emit(1.0)
		await get_tree().create_timer(1.0).timeout
		_log("restart lever respawns player in-level", Game.alive, "alive=%s hp=%.0f" % [Game.alive, Game.hp])
	else:
		_log("restart lever control found on cockpit", false, "no 'restart' key in cockpit controls")

	# ---- menu_switch: actual return to the main menu ----
	if c.has("menu_switch"):
		c["menu_switch"].toggled_on.emit(true)
		await get_tree().create_timer(1.0).timeout
		_log("menu_switch cockpit control returns to MENU", Game.state == Game.GState.MENU, "state=%d" % Game.state)
	else:
		_log("menu_switch control found on cockpit", false, "no 'menu_switch' key in cockpit controls")

	# ---- restart: menu -> game again, proving the loop isn't one-shot ----
	main_inst.menu.start_requested.emit(Game.Mode.SOLO, "outdoor", 1, "")
	await get_tree().create_timer(2.0).timeout
	_log("can start a NEW game after returning to menu (menu loop not one-shot)", Game.state == Game.GState.PLAYING)
	_log("player/world in a valid state after the full loop", main_inst.player != null and is_instance_valid(main_inst.player))


# Full co-op/versus netcode (two real instances, --mp-host/--mp-join) is a
# separate, heavier test — see tools/net_smoke_coop.sh. This just proves the
# MODE WIRING itself (mode switch, level assignment) doesn't crash the menu
# state machine locally, cheap enough to run every time this script runs.
func _test_coop_vs_menu_wiring() -> void:
	print("\n===== MENU MODE WIRING: coop/versus selection doesn't break state machine =====")
	# start_game() sets main_inst.menu = null once a level is running
	# (confirmed in scripts/main.gd) — the solo flow above left a game
	# PLAYING, so `menu` is currently null. Go back through the real
	# to_menu() path (a public method, same one the menu_switch cockpit
	# control calls) before touching main_inst.menu again.
	main_inst.to_menu()
	await get_tree().create_timer(0.5).timeout
	_log("to_menu() recreates a usable menu instance", main_inst.menu != null)
	if main_inst.menu == null:
		_log("coop/versus wiring test aborted", false, "no menu instance to drive")
		return
	main_inst.menu.start_requested.emit(Game.Mode.VERSUS, "outdoor", 1, "")
	await get_tree().create_timer(1.5).timeout
	_log("VERSUS mode reaches PLAYING without crashing", Game.state == Game.GState.PLAYING, "mode=%d" % Game.mode)
	main_inst.to_menu()   # same start_game()-nulls-menu gotcha as above
	await get_tree().create_timer(0.5).timeout
	if main_inst.menu == null:
		_log("can return to SOLO after VERSUS", false, "menu null after to_menu()")
		return
	main_inst.menu.start_requested.emit(Game.Mode.SOLO, "outdoor", 1, "")
	await get_tree().create_timer(1.5).timeout
	_log("can return to SOLO after VERSUS", Game.mode == Game.Mode.SOLO and Game.state == Game.GState.PLAYING)


func _print_summary() -> void:
	print("\n===== GAMEPLAY QA SUMMARY =====")
	var passed := 0
	for r in _results:
		if r["ok"]:
			passed += 1
	print("%d/%d checks passed" % [passed, _results.size()])
	for r in _results:
		if not r["ok"]:
			print("  FAILED: %s  (%s)" % [r["check"], r["detail"]])
	print("Not covered here — needs the heavier 2-instance test:")
	print("  co-op/versus actual netcode sync (peers, snapshot replication) —")
	print("  --mp-host / --mp-join already exist in main.gd for this, run separately.")
	print("Not covered here at all — needs a human in the headset:")
	print("  real VR hand/controller interaction (see tools/xr_interaction_smoke.gd,")
	print("  Goal 4) and any perceptual/feel judgment (\"does this feel right\").")
