# Autoload "NetManager": LAN multiplayer over ENet with UDP-broadcast
# discovery (same Wi-Fi, zero config), plus a Cloudflare WebSocket relay
# fallback for when the two headsets aren't on the same LAN.
#
# CO-OP: host simulates everything. Host station = driver + MG; client is the
# gunner (turret, cannon, breech, rockets) in a puppet tank that mirrors host
# state. Client streams gunner inputs up; host streams tank/enemy snapshots +
# shot events down. Client damage simulation is disabled.
#
# VERSUS: each peer simulates its own tank; opponents appear as a replica
# body. Shooter detects hits on the replica and RPCs damage to the victim.
#
# TWO TRANSPORTS, kept deliberately un-intertwined:
#   ENET  — Godot's own multiplayer_peer + @rpc. LAN only. _peer holds it.
#   RELAY — a WebSocketPeer talking JSON to the deployed worker's broadcast
#           relay. _relay holds it. RPCs don't exist here; every send is a
#           manual put_packet and every receive is dispatched by _relay_recv.
# _transport says which one is live. The rest of the codebase only ever calls
# host()/search()/leave() + the same s_*/c_*/v_* senders; those fan out to the
# right transport internally so callers never learn there are two.
extends Node

signal join_found(cfg: Dictionary)
# Relay-only lifecycle for the menu to surface ("reconnecting...", "lost").
signal relay_status(text: String)

const PORT := 40123
const BCAST := 40124
const SNAP_HZ := 15.0

# --- relay ---
const RELAY_URL := "wss://tank-commander.alexcoulombe.workers.dev/ws"
const RELAY_ROOM := "main"                 # always-on fallback room
const LAN_SEARCH_TIMEOUT := 4.0            # give the LAN beacon this long, then relay
const RECONNECT_MAX := 6                   # attempts before giving up
const RECONNECT_CAP := 15.0                # backoff ceiling (s)

enum Transport { NONE, ENET, RELAY }
var _transport := Transport.NONE

var hosting := false
var client := false
var searching := false
var _peer_up := false     # host: an ENet client is fully connected right now

var _peer: ENetMultiplayerPeer
var _beacon: PacketPeerUDP
var _listen: PacketPeerUDP
var _beacon_t := 0.0
var _snap_t := 0.0

# --- relay state ---
var _relay: WebSocketPeer = null
var _relay_id := ""                        # our id from 'welcome'
var _relay_host := false                   # are WE the relay room's host?
var _relay_roster := {}                    # id -> color, for has_player()
var _search_t := 0.0                       # LAN-beacon countdown before relay
var _host_relay_t := 0.0                   # host: LAN-wait countdown before ALSO opening the relay
var _reconnect_at := 0.0                   # seconds until next reconnect try
var _reconnect_left := 0                   # attempts remaining
var _relay_want_open := false              # true while we intend to stay connected
var _relay_cfg := {}                       # {mode,level,diff} chosen at connect time

var tank: Node3D = null              # coop tank (both sides, always PlayerTank) / my vehicle (versus, any type exposing get_aim_yaw_pitch())
var replicas: ReplicaPool = null     # client: enemy visuals
var remote_vehicle: RemoteVehicle = null  # versus: opponent replica (any vehicle type)
var _versus_world: Node3D = null     # stashed by setup_versus() for _ensure_remote_vehicle()'s lazy build
var projectiles: Projectiles = null
var fx: FxPool = null
var terrain: Terrain = null
var gunner_input := Vector2.ZERO     # host: last gunner aim from client
var gunner_mg_held := false          # host: last coax-MG button state from a client-gunner
var driver_input := Vector2.ZERO     # host: last drive stick from a client-driver (post seat-swap)

# co-op seat assignment: which peer id currently drives (the other gunners).
# Starts as the host (peer 1); flipped by the seat-swap hotkey via s_swap_seats.
var driver_is_host := true

var _round_bcast_t := 0.0            # host: throttle s_round to ~4 Hz

func _ready() -> void:
	# Name/team handshake — one-shot per side right after the link is up. The
	# host's half lives in _on_peer_connected (connected only while host() is
	# active, see host()/leave()); the client fires once it's fully connected
	# to the server. Both send v_hello (any_peer, reliable) so each side learns
	# the other's display name and current team assignment.
	multiplayer.connected_to_server.connect(_on_connected_to_server)

func _on_connected_to_server() -> void:
	if client:
		_send_hello()

func _send_hello() -> void:
	if Game.display_name == "":
		Game.display_name = Game.default_name()
	# v_hello.rpc() only dispatches over the ENet transport (it needs
	# multiplayer.multiplayer_peer set); the relay has no such peer, so route
	# through the same generic typed-message channel _relay_recv()'s "hello"
	# case unpacks back into a direct v_hello(...) call.
	if _transport == Transport.RELAY:
		_relay_send({"type": "hello", "name": Game.display_name, "team": Game.my_team,
			"tmode": Game.team_mode, "vehicle": Game.vehicle})
	else:
		v_hello.rpc(Game.display_name, Game.my_team, Game.team_mode, Game.vehicle)

func my_id() -> int:
	return AvatarCosmetics.PlayerId.HOST if hosting else AvatarCosmetics.PlayerId.CLIENT

func their_id() -> int:
	return AvatarCosmetics.PlayerId.CLIENT if hosting else AvatarCosmetics.PlayerId.HOST

func is_client() -> bool:
	return client

func active() -> bool:
	return hosting or client

# co-op seat helpers: which station does THIS peer currently occupy? Solo
# (not active) is always "both", so callers that gate on these still work.
func i_am_driver() -> bool:
	if not active():
		return true
	return hosting == driver_is_host

func i_am_gunner() -> bool:
	if not active():
		return true
	return hosting != driver_is_host

# "someone else is here." ENet: gate on the peer_connected signal via
# _peer_up, not just get_peers().size() -- the host used to start blasting
# authority-RPCs (s_coop_snap/s_driver_head, 15 Hz, with the enemy Array
# payload) the instant the peer count ticked up, which on-device is
# mid-ENet-handshake -- the peer's channel isn't ready and the host would
# push into a half-open connection ("multiplayer peer which is not
# connected"). _peer_up only flips true once ENet confirms the link. RELAY:
# the room roster has anyone besides us. Both gate the same snapshot-send
# logic in _process().
func has_player() -> bool:
	if _transport == Transport.RELAY:
		return _relay_roster.size() > 0
	return _peer_up

func leave() -> void:
	# Drop the connect/disconnect handlers so the next host() doesn't stack a
	# second connection (they're re-added there). connected_to_server on the
	# client is CONNECT_ONE_SHOT, so it cleans itself up.
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	_relay_want_open = false
	if _relay:
		_relay.close()
		_relay = null
	_relay_id = ""
	_relay_host = false
	_relay_roster.clear()
	_reconnect_left = 0
	_relay_cfg = {}
	_transport = Transport.NONE
	hosting = false
	client = false
	searching = false
	_peer_up = false
	_snap_seen = false
	if _beacon:
		_beacon.close()
		_beacon = null
	if _listen:
		_listen.close()
		_listen = null
	tank = null
	replicas = null
	if remote_vehicle:
		remote_vehicle.queue_free()
	remote_vehicle = null
	_versus_world = null
	driver_is_host = true
	# Input + avatar state must not leak into the NEXT session (2026-07-16 MP
	# audit): gunner/driver inputs only otherwise reset in _on_peer_connected,
	# which the relay path never runs — a fresh relay coop session started
	# with the previous one's last aim/MG-held/drive vector. And _crew_avatar
	# is freed WITH the tank when main tears the world down, but a freed node
	# is not `== null`, so _ensure_crew_avatar()'s null-guard never rebuilt it
	# — the peer's crew body silently never spawned again.
	gunner_input = Vector2.ZERO
	gunner_mg_held = false
	driver_input = Vector2.ZERO
	if is_instance_valid(_crew_avatar):
		_crew_avatar.queue_free()
	_crew_avatar = null
	Game.round_active = false
	Game.peer_name = ""
	Game.peer_vehicle = ""
	_name_billboards.clear()

func host() -> void:
	leave()
	_transport = Transport.ENET
	_peer = ENetMultiplayerPeer.new()
	_peer.create_server(PORT, 1)
	multiplayer.multiplayer_peer = _peer
	hosting = true
	# Own the connect/disconnect edges instead of polling get_peers() in
	# _process: the host must NOT emit any snapshot until ENet says the peer
	# is really up, and must stop the instant it drops (an .rpc() into a
	# torn-down peer is the "not connected" spam and, on-device, the join-time
	# crash). One_shot-free connect so a client can rejoin after leaving.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", BCAST)
	print("[net] hosting on :%d, beaconing" % PORT)
	# If nobody joins over LAN within the window, ALSO open the relay as
	# host — previously host() was ENet/LAN-only with no relay fallback of
	# its own (only search()/join had one), so a host + a remote joiner on a
	# different network could never actually meet, even via the "always-on"
	# relay room (Alex, live report 2026-07-06: "can't get into a game...
	# whether we both try to join the cloudflare server or one of us hosts
	# and the other tries to join"). Mirrors search()'s own LAN-then-relay
	# pattern. See _process() for the actual fallback trigger.
	_host_relay_t = LAN_SEARCH_TIMEOUT

func _on_peer_connected(id: int) -> void:
	# Fresh session state so a re-joiner doesn't inherit the last gunner's
	# aim or a stale crew avatar built against the previous connection.
	_peer_up = true
	_snap_seen = false
	gunner_input = Vector2.ZERO
	gunner_mg_held = false
	# Seats back to default too: a guest who dropped mid-swap and rejoins
	# builds its fresh setup_coop() with driver_is_host=true — if the host
	# kept the stale swapped value the two sides would silently hold INVERTED
	# seat beliefs (both-think-they're-gunner deadlock, 2026-07-16 MP audit).
	driver_is_host = true
	driver_input = Vector2.ZERO
	_apply_seat_roles()
	print("[net] peer %d connected" % id)
	_send_hello()

func _on_peer_disconnected(id: int) -> void:
	_peer_up = false
	# Don't let the ghost keep driving: if the guest held the driver seat and
	# dropped while pushing forward, driver_input would stay latched and the
	# unmanned tank would drive itself forever (2026-07-16 MP audit).
	driver_input = Vector2.ZERO
	gunner_input = Vector2.ZERO
	gunner_mg_held = false
	print("[net] peer %d disconnected" % id)

func search() -> void:
	leave()
	_listen = PacketPeerUDP.new()
	_listen.bind(BCAST)
	searching = true
	_search_t = LAN_SEARCH_TIMEOUT     # ...then fall through to the relay
	print("[net] searching for host beacon (relay fallback in %ds)..." % int(LAN_SEARCH_TIMEOUT))

# =============================================================== RELAY FALLBACK
# Reached when search()'s LAN beacon-listen window elapses with no host found.
# We join the shared room; the worker's 'welcome' tells us if we're host.
func _start_relay(cfg := {}) -> void:
	# tear the LAN listen down but keep the join_found contract alive
	if _listen:
		_listen.close()
		_listen = null
	searching = false
	_transport = Transport.RELAY
	_relay_cfg = cfg
	_relay_want_open = true
	_reconnect_left = RECONNECT_MAX
	relay_status.emit("connecting to online room...")
	_relay_open()

func _relay_open() -> void:
	_relay = WebSocketPeer.new()
	var url := "%s/%s" % [RELAY_URL, RELAY_ROOM]
	var err := _relay.connect_to_url(url)
	if err != OK:
		push_warning("[net] relay connect_to_url failed: %s" % err)
		_relay_schedule_reconnect()
		return
	print("[net] relay connecting to ", url)

# Exponential backoff: 1,2,4,8,15,15... capped, give up after RECONNECT_MAX.
func _relay_schedule_reconnect() -> void:
	if not _relay_want_open:
		return
	if _reconnect_left <= 0:
		relay_status.emit("connection lost")
		print("[net] relay gave up after reconnects")
		leave()
		return
	var attempt := RECONNECT_MAX - _reconnect_left
	_reconnect_at = minf(RECONNECT_CAP, pow(2.0, attempt))
	_reconnect_left -= 1
	_relay = null
	relay_status.emit("reconnecting in %ds..." % int(ceil(_reconnect_at)))
	print("[net] relay reconnect in %.0fs (%d left)" % [_reconnect_at, _reconnect_left])

func _relay_send(msg: Dictionary) -> void:
	if _relay == null or _relay.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_relay.put_packet(JSON.stringify(msg).to_utf8_buffer())

func _process(delta: float) -> void:
	# host beacon (until someone joins)
	if hosting and _transport == Transport.ENET and _beacon and not has_player():
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var msg := "TCVR|%d|%s|%d" % [Game.mode, Game.level_id, Game.difficulty]
			_beacon.put_packet(msg.to_utf8_buffer())
		# no LAN joiner within the window -> also become a relay host, so a
		# remote joiner (different network, or the relay's persistent "main"
		# room) can still find this session. Tears down the ENet-only pieces
		# directly (NOT leave() -- that would also clear `hosting` and the
		# rest of the session state this same call is trying to preserve).
		_host_relay_t -= delta
		if _host_relay_t <= 0.0:
			print("[net] no LAN joiner; also opening relay as host")
			if multiplayer.peer_connected.is_connected(_on_peer_connected):
				multiplayer.peer_connected.disconnect(_on_peer_connected)
			if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
				multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
			if _peer:
				_peer.close()
				_peer = null
			multiplayer.multiplayer_peer = null
			if _beacon:
				_beacon.close()
				_beacon = null
			_start_relay({"mode": Game.mode, "level": Game.level_id, "diff": Game.difficulty})
			return
	# join search
	if searching and _listen and _listen.get_available_packet_count() > 0:
		var pkt := _listen.get_packet().get_string_from_utf8()
		var ip := _listen.get_packet_ip()
		if pkt.begins_with("TCVR|"):
			var parts := pkt.split("|")
			searching = false
			_listen.close()
			_listen = null
			_peer = ENetMultiplayerPeer.new()
			_peer.create_client(ip, PORT)
			multiplayer.multiplayer_peer = _peer
			client = true
			print("[net] joining host at ", ip)
			multiplayer.connected_to_server.connect(func():
				join_found.emit({"mode": int(parts[1]), "level": parts[2], "diff": int(parts[3])}),
				CONNECT_ONE_SHOT)
	# no LAN host within the window -> fall through to the online relay room
	if searching:
		_search_t -= delta
		if _search_t <= 0.0:
			print("[net] no LAN host; falling back to relay room '%s'" % RELAY_ROOM)
			_start_relay()
	# relay pump: reconnect countdown + poll + snapshots handled below
	if _transport == Transport.RELAY:
		_relay_process(delta)
		return
	# snapshots (ENet)
	if Game.state != Game.GState.PLAYING or not active():
		return
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = 1.0 / SNAP_HZ
		if hosting and has_player():
			if Game.mode == Game.Mode.COOP and tank:
				_send_coop_snap()
			elif Game.mode == Game.Mode.VERSUS and tank:
				var aim: Vector2 = tank.get_aim_yaw_pitch()
				s_versus_state.rpc(tank.global_transform, aim.x, aim.y,
					_my_head_rel(), _my_hand_rel(true), _my_hand_rel(false), _my_move_flags())
		elif client and tank:
			if Game.mode == Game.Mode.COOP:
				# co-op is invariantly tank-only (setup_coop() only ever accepts a
				# PlayerTank) even though `tank` is now typed generically Node3D
				# to also cover versus-mode's other vehicle types -- cast is safe.
				var co_tank: PlayerTank = tank
				# stream whichever station this client currently holds; the host
				# routes it to the turret (gunner) or the tracks (driver)
				if i_am_driver():
					c_driver.rpc_id(1, co_tank.stick_drive, _my_head_rel(),
						_my_hand_rel(true), _my_hand_rel(false), _my_move_flags())
				else:
					c_gunner.rpc_id(1, co_tank.effective_turret_input(), _my_head_rel(),
						_my_hand_rel(true), _my_hand_rel(false), _my_move_flags(), co_tank.mg_held)
			elif Game.mode == Game.Mode.VERSUS:
				var aim: Vector2 = tank.get_aim_yaw_pitch()
				s_versus_state.rpc(tank.global_transform, aim.x, aim.y,
					_my_head_rel(), _my_hand_rel(true), _my_hand_rel(false), _my_move_flags())

# --------------------------------------------------------------- relay per-frame
func _relay_process(delta: float) -> void:
	# waiting on a scheduled reconnect
	if _relay == null:
		if not _relay_want_open:
			return
		_reconnect_at -= delta
		if _reconnect_at <= 0.0:
			_relay_open()
		return
	_relay.poll()
	var st := _relay.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		while _relay.get_available_packet_count() > 0:
			_relay_recv(_relay.get_packet())
	elif st == WebSocketPeer.STATE_CLOSED:
		# unexpected drop while we still want to be connected -> backoff retry
		if _relay_want_open:
			_relay_roster.clear()
			push_warning("[net] relay closed (code %d); reconnecting" % _relay.get_close_code())
			_relay_schedule_reconnect()
		return
	# STATE_CONNECTING / STATE_CLOSING: just keep polling next frame
	# snapshots over the relay (only once OPEN and playing)
	if st != WebSocketPeer.STATE_OPEN or Game.state != Game.GState.PLAYING or not active():
		return
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = 1.0 / SNAP_HZ
		_relay_send_snapshot()

# ------------------------------------------------------------- relay: receive
# The worker hands us: welcome/join/leave (roster), verbatim 'state' from other
# peers, and byId/byColor/byHost-stamped one-off typed messages. We map those
# back onto the same s_*/c_*/v_* handlers the ENet path already uses.
func _relay_recv(bytes: PackedByteArray) -> void:
	var env = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(env) != TYPE_DICTIONARY:
		return
	match env.get("type", ""):
		"welcome":
			# Mid-game role flip = unrecoverable: the worker tags "host" as
			# first-socket-in-room and never re-promotes, so a host that drops
			# and reconnects while its guest stayed comes back tagged guest —
			# leaving BOTH peers as clients, nobody simulating, tank.puppet
			# stale (2026-07-16 MP audit). No in-place repair is safe (the
			# whole sim authority would have to rebuild), so end the session
			# cleanly instead of leaving a permanently frozen game.
			if active() and Game.state == Game.GState.PLAYING \
					and hosting != bool(env.get("host", false)):
				relay_status.emit("host changed — session ended")
				push_warning("[net] relay role flipped mid-game; returning to menu")
				var m_flip = get_tree().get_first_node_in_group("main")
				if m_flip:
					m_flip.call_deferred("to_menu")
				return
			_relay_id = str(env.get("id", ""))
			_relay_host = bool(env.get("host", false))
			_relay_roster.clear()
			for r in env.get("roster", []):
				var rid := str(r.get("id", ""))
				if rid != _relay_id:
					_relay_roster[rid] = r.get("color", "")
			# reconnect succeeded: refresh the budget for next time
			_reconnect_left = RECONNECT_MAX
			# host drives coop sim; everyone else is a client (gunner/opponent)
			hosting = _relay_host
			client = not _relay_host
			print("[net] relay welcome id=%s host=%s roster=%d" % [_relay_id, _relay_host, _relay_roster.size()])
			relay_status.emit("connected (%s)" % ("host" if _relay_host else "guest"))
			# Declare ourselves (name/team/vehicle) on every (re)connect -- the
			# ENet path gets this for free via connected_to_server/peer_connected
			# signals, but the relay's "welcome" is the only equivalent moment.
			_send_hello()
			# first connect: hand main.gd a level cfg the same way join_found does
			if not _relay_cfg.get("_emitted", false):
				_relay_cfg["_emitted"] = true
				join_found.emit({
					"mode": _relay_cfg.get("mode", Game.mode),
					"level": _relay_cfg.get("level", Game.level_id),
					"diff": _relay_cfg.get("diff", Game.difficulty),
				})
		"join":
			var jid := str(env.get("id", ""))
			if jid != _relay_id:
				_relay_roster[jid] = env.get("color", "")
			relay_status.emit("player joined")
		"leave":
			_relay_roster.erase(str(env.get("id", "")))
			relay_status.emit("player left")
		"full":
			# Worker capped the room at 2 (see worker.js) — stop retrying, the
			# session is genuinely unavailable, not flaky.
			relay_status.emit("online room is full — try again later")
			_relay_want_open = false
			leave()
		"host_left":
			# Sim authority is gone; no safe mid-session re-election (see the
			# welcome role-flip guard above). End cleanly.
			if Game.state == Game.GState.PLAYING:
				relay_status.emit("host left — session ended")
				var m_hl = get_tree().get_first_node_in_group("main")
				if m_hl:
					m_hl.call_deferred("to_menu")
		"hello":
			v_hello(str(env.get("name", "")), int(env.get("team", 0)),
				bool(env.get("tmode", false)), str(env.get("vehicle", "tank")))
		"state":
			_relay_apply_state(env.get("s", {}))
		# one-off typed messages (stamped byId/byColor/byHost by the worker)
		"evt":
			_relay_apply_evt(env)
		_:
			pass

# high-frequency snapshot, shaped per role/mode, sent as {type:'state', s:{...}}
func _relay_send_snapshot() -> void:
	if hosting and has_player():
		if Game.mode == Game.Mode.COOP and tank:
			_relay_send({"type": "state", "s": _coop_snap_dict()})
		elif Game.mode == Game.Mode.VERSUS and tank:
			_relay_send({"type": "state", "s": _versus_state_dict()})
	elif client and tank:
		if Game.mode == Game.Mode.COOP:
			# co-op is invariantly tank-only -- see the matching cast note in _process().
			# Branch on the CURRENT seat exactly like the ENet path in _process()
			# does -- this used to be hardcoded to the gunner shape, which left a
			# relay client-driver with NO channel for its drive stick at all
			# (post-swap the tank was simply undrivable; 2026-07-16 MP audit).
			var co_tank: PlayerTank = tank
			if i_am_driver():
				_relay_send({"type": "state", "s": {
					"k": "driver",
					"in": _v2(co_tank.stick_drive),
					"head": _t3(_my_head_rel()),
					"hl": _t3(_my_hand_rel(true)),
					"hr": _t3(_my_hand_rel(false)),
					"mf": _my_move_flags(),
				}})
			else:
				_relay_send({"type": "state", "s": {
					"k": "gunner",
					"in": _v2(co_tank.effective_turret_input()),
					"head": _t3(_my_head_rel()),
					"hl": _t3(_my_hand_rel(true)),
					"hr": _t3(_my_hand_rel(false)),
					"mf": _my_move_flags(),
					"mg": co_tank.mg_held,
				}})
		elif Game.mode == Game.Mode.VERSUS:
			_relay_send({"type": "state", "s": _versus_state_dict()})

func _coop_snap_dict() -> Dictionary:
	# co-op is invariantly tank-only -- see the matching cast note in _process().
	var co_tank: PlayerTank = tank
	var enemies: Array = []
	for grp in ["enemies", "planes"]:
		for n in get_tree().get_nodes_in_group(grp):
			if not n is Node3D:
				continue
			var type := 0
			var aux := 0.0
			if n is EnemyTank:
				type = 0
				aux = n.turret.rotation.y
			elif n is EnemyPlane:
				type = 1
			elif n is EnemyLight.Jeep:
				type = 2
			elif n is EnemyLight.Gunner:
				type = 3
			elif n is EnemyLight.Mortar:
				type = 4
			enemies.append([type, n.get_instance_id(), _t3(n.global_transform), aux])
	return {
		"k": "coop",
		"t": _t3(co_tank.global_transform), "ty": co_tank.turret.rotation.y, "ge": co_tank.gun_elev,
		"hp": Game.hp, "ammo": co_tank.ammo, "rk": co_tank.rockets_left, "ld": co_tank.loaded,
		"eng": co_tank.engine_on, "wave": Game.wave, "score": Game.score, "en": enemies,
		"head": _t3(_my_head_rel()), "hl": _t3(_my_hand_rel(true)), "hr": _t3(_my_hand_rel(false)),
		"mf": _my_move_flags(),
	}

func _versus_state_dict() -> Dictionary:
	var aim: Vector2 = tank.get_aim_yaw_pitch()
	return {
		"k": "versus",
		"t": _t3(tank.global_transform), "ty": aim.x, "ge": aim.y,
		"head": _t3(_my_head_rel()), "hl": _t3(_my_hand_rel(true)), "hr": _t3(_my_hand_rel(false)),
		"mf": _my_move_flags(),
	}

# apply an incoming state dict from the other peer (reuses ENet-path handlers)
func _relay_apply_state(s: Dictionary) -> void:
	match s.get("k", ""):
		"coop":
			var enemies: Array = []
			for e in s.get("en", []):
				enemies.append([int(e[0]), int(e[1]), _un_t3(e[2]), float(e[3])])
			s_coop_snap(_un_t3(s["t"]), s["ty"], s["ge"], s["hp"], int(s["ammo"]),
				int(s["rk"]), s["ld"], s["eng"], int(s["wave"]), int(s["score"]), enemies)
			s_driver_head(_un_t3(s["head"]), _un_t3(s["hl"]), _un_t3(s["hr"]), int(s["mf"]))
		"gunner":
			c_gunner(_un_v2(s["in"]), _un_t3(s["head"]), _un_t3(s["hl"]), _un_t3(s["hr"]),
				int(s["mf"]), s.get("mg", false))
		"driver":
			c_driver(_un_v2(s["in"]), _un_t3(s["head"]), _un_t3(s["hl"]), _un_t3(s["hr"]),
				int(s["mf"]))
		"versus":
			s_versus_state(_un_t3(s["t"]), s["ty"], s["ge"], _un_t3(s["head"]),
				_un_t3(s["hl"]), _un_t3(s["hr"]), int(s["mf"]))

# apply a one-off typed event {type:'evt', e:<name>, ...}
func _relay_apply_evt(env: Dictionary) -> void:
	match env.get("e", ""):
		"c_event": c_event(env.get("kind", ""))
		"s_shot":
			if projectiles:
				projectiles.fire(int(env["kind"]), _un_v3(env["pos"]), _un_v3(env["vel"]), [], true)
		"v_i_died": v_i_died()
		"v_shot":
			if projectiles:
				projectiles.fire(int(env["kind"]), _un_v3(env["pos"]), _un_v3(env["vel"]), [], true, true)
		"v_damage": v_damage(float(env.get("amount", 0.0)))
		"s_round":
			s_round(float(env.get("left", 0.0)), bool(env.get("active", false)),
				bool(env.get("tmode", false)), int(env.get("red", 0)), int(env.get("blue", 0)))
		"s_round_end":
			s_round_end(int(env.get("red", 0)), int(env.get("blue", 0)))
		# host god-mode + seat-swap — relay counterparts of the authority RPCs
		# (2026-07-16 MP audit: these five had no relay path at either end)
		"s_session":
			s_session(int(env.get("mode", Game.mode)), str(env.get("level", Game.level_id)),
				int(env.get("diff", Game.difficulty)), str(env.get("mut", "")))
		"s_add_bots":
			s_add_bots(int(env.get("count", 0)))
		"s_team_mode":
			s_team_mode(bool(env.get("on", false)))
		"c_swap_seats":
			c_swap_seats()
		"s_seats":
			s_seats(bool(env.get("hd", true)))

# ---- (de)serialization helpers: JSON only carries floats/arrays, so pack
# Transform3D/Vector2/Vector3 into plain number arrays and back.
func _t3(t: Transform3D) -> Array:
	var b := t.basis
	var o := t.origin
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]

func _un_t3(a) -> Transform3D:
	if typeof(a) != TYPE_ARRAY or a.size() < 12:
		return Transform3D()
	return Transform3D(
		Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
		Vector3(a[9], a[10], a[11]))

func _v2(v: Vector2) -> Array: return [v.x, v.y]
func _un_v2(a) -> Vector2: return Vector2(a[0], a[1]) if typeof(a) == TYPE_ARRAY else Vector2.ZERO
func _v3(v: Vector3) -> Array: return [v.x, v.y, v.z]
func _un_v3(a) -> Vector3: return Vector3(a[0], a[1], a[2]) if typeof(a) == TYPE_ARRAY else Vector3.ZERO

# ================================================================ CO-OP
# Driving/engine controls that belong to whoever holds the DRIVER seat.
const _DRIVE_CONTROLS := ["tiller_l", "tiller_r", "gear", "battery", "starter", "lights", "fuel_pump", "horn"]

func setup_coop(t: PlayerTank) -> void:
	tank = t
	if client:
		t.puppet = true
		if t.projectiles:
			t.projectiles.damage_enabled = false
	driver_is_host = true
	_apply_seat_roles()
	# co-op wave-survival framing: host arms a round clock both sides display
	# (coop stays wave-based; the timer is just an optional shared countdown)
	if hosting:
		Game.start_round(Game.round_len)
		_broadcast_round(Game.round_left, true, Game.team_mode, 0, 0)
	_spawn_name_billboard(t, their_id())

# Enable/disable this peer's cockpit controls for its CURRENT seat. Split out
# of setup_coop() so the seat-swap hotkey (s_swap_seats) can re-apply it live.
# "am I the driver?" = (I'm host) == (driver is host).
func _apply_seat_roles() -> void:
	if tank == null:
		return
	# co-op is invariantly tank-only -- see the matching cast note in _process().
	var co_tank: PlayerTank = tank
	var c: Dictionary = co_tank.cockpit["controls"]
	var i_drive := hosting == driver_is_host
	# driver owns the tillers/engine; gunner owns the turret grip
	for k in _DRIVE_CONTROLS:
		if c.has(k):
			c[k].enabled = i_drive
	if c.has("grip"):
		c["grip"].enabled = not i_drive

func make_replica_pool(t: Terrain) -> ReplicaPool:
	replicas = ReplicaPool.new()
	terrain = t
	return replicas

func _send_coop_snap() -> void:
	# co-op is invariantly tank-only -- see the matching cast note in _process().
	var co_tank: PlayerTank = tank
	var head := _my_head_rel()
	if head != Transform3D():
		s_driver_head.rpc(head, _my_hand_rel(true), _my_hand_rel(false), _my_move_flags())
	var enemies: Array = []
	for grp in ["enemies", "planes"]:
		for n in get_tree().get_nodes_in_group(grp):
			if not n is Node3D:
				continue
			var type := 0
			var aux := 0.0
			if n is EnemyTank:
				type = 0
				aux = n.turret.rotation.y
			elif n is EnemyPlane:
				type = 1
			elif n is EnemyLight.Jeep:
				type = 2
			elif n is EnemyLight.Gunner:
				type = 3
			elif n is EnemyLight.Mortar:
				type = 4
			enemies.append([type, n.get_instance_id(), n.global_transform, aux])
	s_coop_snap.rpc(co_tank.global_transform, co_tank.turret.rotation.y, co_tank.gun_elev,
		Game.hp, co_tank.ammo, co_tank.rockets_left, co_tank.loaded, co_tank.engine_on, Game.wave, Game.score, enemies)

@rpc("any_peer", "unreliable_ordered")
func c_gunner(input: Vector2, head_rel := Transform3D(), hand_l_rel := Transform3D(),
		hand_r_rel := Transform3D(), move_flags := 0, mg_held := false) -> void:
	gunner_input = input
	gunner_mg_held = mg_held
	if head_rel != Transform3D():
		_apply_crew_avatar(head_rel, hand_l_rel, hand_r_rel, move_flags)

# Seat-swapped coop: a client that now holds the DRIVER seat streams its drive
# stick here; PlayerTank._update_drive() consumes driver_input on the host.
@rpc("any_peer", "unreliable_ordered")
func c_driver(drive: Vector2, head_rel := Transform3D(), hand_l_rel := Transform3D(),
		hand_r_rel := Transform3D(), move_flags := 0) -> void:
	driver_input = drive
	if head_rel != Transform3D():
		_apply_crew_avatar(head_rel, hand_l_rel, hand_r_rel, move_flags)

@rpc("any_peer", "reliable")
func c_event(kind: String) -> void:
	# gunner actions applied on the host's authoritative tank (co-op only --
	# see the matching cast note in _process())
	if not hosting or tank == null:
		return
	var co_tank: PlayerTank = tank
	match kind:
		"fire":
			co_tank.fire_cannon(false)
		"breech":
			if not co_tank.loaded and co_tank.ammo > 0:
				co_tank._chamber()
		"rockets":
			co_tank.rockets_armed = true
			co_tank.fire_rockets()

var _snap_seen := false

@rpc("authority", "unreliable_ordered")
func s_coop_snap(tank_t: Transform3D, turret_y: float, gun_e: float, hp: float,
		ammo: int, rkts: int, loaded: bool, engine: bool, wave: int, score: int, enemies: Array) -> void:
	if not _snap_seen:
		_snap_seen = true
		print("[net] first coop snapshot applied (%d enemies)" % enemies.size())
	if tank == null:
		return
	# co-op is invariantly tank-only -- see the matching cast note in _process().
	var co_tank: PlayerTank = tank
	co_tank.net_apply(tank_t, turret_y, gun_e, ammo, rkts, loaded, engine)
	Game.hp = hp
	Game.hp_changed.emit(hp)
	if wave != Game.wave:
		Game.set_wave(wave)
	if score != Game.score:
		Game.score = score
		Game.score_changed.emit(score)
	if hp <= 0.0 and Game.alive:
		Game.alive = false
		Game.game_over.emit()
	elif hp > 0.0 and not Game.alive:
		Game.alive = true
		Game.game_restarted.emit()
	if replicas:
		replicas.apply(enemies)

@rpc("authority", "unreliable_ordered")
func s_driver_head(head_rel: Transform3D, hand_l_rel := Transform3D(), hand_r_rel := Transform3D(),
		move_flags := 0) -> void:
	_apply_crew_avatar(head_rel, hand_l_rel, hand_r_rel, move_flags)

@rpc("authority", "reliable")
func s_shot(kind: int, pos: Vector3, vel: Vector3) -> void:
	# visual projectile on the client (damage disabled there)
	if projectiles:
		projectiles.fire(kind, pos, vel, [], true)

func broadcast_shot(kind: int, pos: Vector3, vel: Vector3) -> void:
	if not (hosting and has_player()):
		return
	if _transport == Transport.RELAY:
		_relay_send({"type": "evt", "e": "s_shot", "kind": kind, "pos": _v3(pos), "vel": _v3(vel), "echo": false})
	else:
		s_shot.rpc(kind, pos, vel)

# Client gunner -> host, applied to the authoritative tank (fire/breech/rockets).
# Wrapper so player_tank.gd stays transport-agnostic (was c_event.rpc_id(1,...)).
func send_client_event(kind: String) -> void:
	if _transport == Transport.RELAY:
		_relay_send({"type": "evt", "e": "c_event", "kind": kind, "echo": false})
	else:
		c_event.rpc_id(1, kind)

# ================================================================ VERSUS
func setup_versus(world: Node3D, t: Terrain, p: Projectiles, f: FxPool, my_tank: Node3D) -> void:
	tank = my_tank
	terrain = t
	projectiles = p
	fx = f
	_versus_world = world
	# spawn placement: host south, client north
	var s := t.spawn
	if client:
		my_tank.global_position = Vector3(-s.x, 0, -s.y)
		my_tank.set("yaw", 0.0)   # dynamic: not every vehicle has a `yaw` var (plane orients via basis directly)
	my_tank.global_position.y = t.height(my_tank.global_position.x, my_tank.global_position.z) + 0.04
	Sfx.vo("robot_versus_2", 3, 20.0)  # "Round begin. Fight!"
	Game.game_over.connect(_on_versus_death)
	# host arms the shared round clock; the client mirrors it via s_round()
	if hosting:
		Game.start_round(Game.round_len)
		_broadcast_round(Game.round_left, true, Game.team_mode, 0, 0)
	# Opponent's replica is built lazily once we know their vehicle type (see
	# v_hello/_ensure_remote_vehicle) -- each peer can pick a DIFFERENT vehicle
	# in versus, so there's nothing correct to build synchronously here.
	_ensure_remote_vehicle()

# Builds the opponent's replica once both (a) setup_versus() has run (so we
# have `terrain`/`_versus_world`) and (b) their v_hello has told us their
# vehicle type -- called from both places, whichever lands second actually
# builds it. A brief pop-in before the opponent appears is the acceptable
# cost (same idiom as _ensure_crew_avatar()'s lazy co-op build).
func _ensure_remote_vehicle() -> void:
	if remote_vehicle != null or Game.mode != Game.Mode.VERSUS or not (hosting or client):
		return
	if _versus_world == null or terrain == null:
		return
	var vtype: int
	match Game.peer_vehicle:
		"jeep": vtype = RemoteVehicle.VehicleType.JEEP
		"boat": vtype = RemoteVehicle.VehicleType.BOAT
		"plane", "biplane": vtype = RemoteVehicle.VehicleType.PLANE
		_: vtype = RemoteVehicle.VehicleType.TANK   # default/safety: also covers "tank" and an empty pre-handshake value
	remote_vehicle = RemoteVehicle.new(vtype)
	_versus_world.add_child(remote_vehicle)
	var s := terrain.spawn
	remote_vehicle.global_position = Vector3(-s.x, terrain.height(-s.x, -s.y) + 0.04, -s.y) if not client \
		else Vector3(s.x, terrain.height(s.x, s.y) + 0.04, s.y)
	_spawn_name_billboard(remote_vehicle, their_id(), Vector3(0, 2.4, 0))

func _on_versus_death() -> void:
	if Game.mode != Game.Mode.VERSUS or not active():
		return
	if _transport == Transport.RELAY:
		_relay_send({"type": "evt", "e": "v_i_died", "echo": false})
	else:
		v_i_died.rpc()
	Game.their_kills += 1
	# team mode: my death is a point for the OTHER team (the killer's)
	if Game.team_mode:
		Game.add_team_score(_other_team(Game.my_team), 1)
	Game.kills_changed.emit()
	get_tree().create_timer(4.0).timeout.connect(func():
		if Game.state == Game.GState.PLAYING:
			Game.restart())

@rpc("any_peer", "reliable")
func v_i_died() -> void:
	Game.my_kills += 1
	# team mode: I killed them, my team scores
	if Game.team_mode:
		Game.add_team_score(Game.my_team, 1)
	Game.kills_changed.emit()
	Sfx.vo("vo_kill", 2, 5.0)
	if fx and remote_vehicle:
		fx.explosion(remote_vehicle.global_position + Vector3(0, 1.5, 0), true, tank.global_position if tank else Vector3.ZERO)

@rpc("any_peer", "unreliable_ordered")
func s_versus_state(t: Transform3D, aim_yaw: float, aim_pitch: float, head_rel := Transform3D(),
		hand_l_rel := Transform3D(), hand_r_rel := Transform3D(), move_flags := 0) -> void:
	if remote_vehicle:
		remote_vehicle.net_target(t, aim_yaw, aim_pitch, head_rel, hand_l_rel, hand_r_rel, move_flags)

@rpc("any_peer", "reliable")
func v_shot(kind: int, pos: Vector3, vel: Vector3) -> void:
	if projectiles:
		projectiles.fire(kind, pos, vel, [], true, true)  # visual only

func versus_shot(kind: int, pos: Vector3, vel: Vector3) -> void:
	if not (active() and Game.mode == Game.Mode.VERSUS):
		return
	if _transport == Transport.RELAY:
		_relay_send({"type": "evt", "e": "v_shot", "kind": kind, "pos": _v3(pos), "vel": _v3(vel), "echo": false})
	else:
		v_shot.rpc(kind, pos, vel)

# Symmetric pvp damage sent to the victim (from RemoteVehicle.take_damage).
func send_damage(amount: float) -> void:
	if _transport == Transport.RELAY:
		_relay_send({"type": "evt", "e": "v_damage", "amount": amount, "echo": false})
	else:
		v_damage.rpc(amount)

@rpc("any_peer", "reliable")
func v_damage(amount: float) -> void:
	Game.damage_player(amount / Game.diff(0.6, 1.0, 1.35))  # undo diff scale: pvp is symmetric

func _other_team(t: int) -> int:
	return Game.Team.BLUE if t == Game.Team.RED else Game.Team.RED

# ================================================================ round + tally
# The host owns the countdown (Game._process ticks Game.round_left locally on
# the host, then calls tick_round() here to broadcast + detect expiry). The
# client never counts down; it just displays the last s_round() value.
func tick_round(_delta: float) -> void:
	if not hosting or not has_player():
		return
	_round_bcast_t -= _delta
	if _round_bcast_t <= 0.0:
		_round_bcast_t = 0.25   # ~4 Hz is plenty for a visible clock
		_broadcast_round(Game.round_left, Game.round_active, Game.team_mode,
			int(Game.team_score.get(Game.Team.RED, 0)), int(Game.team_score.get(Game.Team.BLUE, 0)))
	if Game.round_active and Game.round_left <= 0.0:
		Game.round_active = false
		# Each peer computes its OWN tally (my_kills/their_kills are per-peer,
		# so a pre-baked "YOU/THEM" summary would be backwards on the client).
		# Team scores are symmetric, so we hand those over for the client to
		# use; the client still calls round_tally() itself.
		_broadcast_round_end(int(Game.team_score.get(Game.Team.RED, 0)), int(Game.team_score.get(Game.Team.BLUE, 0)))
		Game.round_ended.emit(Game.round_tally())

# Both callers of s_round/s_round_end (above, plus setup_coop()/setup_versus()'s
# initial arm) used to call .rpc() unconditionally -- harmless the moment
# hosting starts (still Transport.ENET then, see host()), but tick_round()
# fires every frame for the rest of the session, including well after a
# LAN-less host has fallen over to Transport.RELAY (host()'s relay-fallback
# timer, see _process()) -- at that point multiplayer.multiplayer_peer is
# null and every one of these ticks threw "Trying to call an RPC while no
# multiplayer peer is active" (confirmed via a live dual-instance relay test,
# 2026-07-06), silently breaking the shared round clock/score sync for any
# cross-network relay session. Mirrors broadcast_shot()/versus_shot()'s
# existing transport branch.
func _broadcast_round(left: float, active: bool, team_mode: bool, red: int, blue: int) -> void:
	if _transport == Transport.RELAY:
		_relay_send({"type": "evt", "e": "s_round", "left": left, "active": active,
			"tmode": team_mode, "red": red, "blue": blue, "echo": false})
	else:
		s_round.rpc(left, active, team_mode, red, blue)

func _broadcast_round_end(red: int, blue: int) -> void:
	if _transport == Transport.RELAY:
		_relay_send({"type": "evt", "e": "s_round_end", "red": red, "blue": blue, "echo": false})
	else:
		s_round_end.rpc(red, blue)

# Client mirror of the authoritative round state. Never ticks down here.
@rpc("authority", "unreliable_ordered")
func s_round(left: float, active: bool, team_mode: bool, red: int, blue: int) -> void:
	Game.round_left = left
	Game.round_active = active
	Game.team_mode = team_mode
	Game.team_score = {Game.Team.RED: red, Game.Team.BLUE: blue}
	Game.round_state_changed.emit()

@rpc("authority", "reliable")
func s_round_end(red: int, blue: int) -> void:
	Game.round_active = false
	Game.team_score = {Game.Team.RED: red, Game.Team.BLUE: blue}
	Game.round_ended.emit(Game.round_tally())  # client's own perspective

# ================================================================ host god-mode
# One small "any_peer authority-checked" surface: only the host acts on these,
# and only the host is allowed to SEND them (host_change_* helpers guard on
# `hosting`). Changing map/mode/difficulty restarts the level with new params
# on BOTH peers; add_bots spawns extra enemies into the running wave.

# Every sender below branches on transport like _broadcast_round() does —
# these five used to call bare .rpc() unconditionally, which THROWS and drops
# the message once a host has fallen back from LAN to the relay (no
# multiplayer peer exists there). Confirmed 2026-07-16 MP audit: over relay,
# a host difficulty/map change desynced the whole session (guest stranded in
# the old level with an orphaned puppet), team-mode toggles never reached the
# guest, and seat swap was a complete no-op in both directions.

func host_change_session(mode: int, level_id: String, diff: int, mutator: String) -> void:
	if not hosting:
		return
	_apply_session_change(mode, level_id, diff, mutator)
	if has_player():
		if _transport == Transport.RELAY:
			_relay_send({"type": "evt", "e": "s_session", "mode": mode, "level": level_id,
				"diff": diff, "mut": mutator, "echo": false})
		else:
			s_session.rpc(mode, level_id, diff, mutator)

func host_add_bots(count: int) -> void:
	if not hosting:
		return
	_apply_add_bots(count)
	if has_player():
		# (Functionally host-only — bots reach the guest via the replica
		# snapshot stream — but the bare .rpc() still threw error spam per
		# press over relay, so it branches like the rest.)
		if _transport == Transport.RELAY:
			_relay_send({"type": "evt", "e": "s_add_bots", "count": count, "echo": false})
		else:
			s_add_bots.rpc(count)

func host_set_team_mode(on: bool) -> void:
	if not hosting:
		return
	Game.team_mode = on
	# host RED, client BLUE (only meaningful once teams are on)
	Game.my_team = Game.Team.RED if hosting else Game.Team.BLUE
	Game.round_state_changed.emit()
	if has_player():
		if _transport == Transport.RELAY:
			_relay_send({"type": "evt", "e": "s_team_mode", "on": on, "echo": false})
		else:
			s_team_mode.rpc(on)

@rpc("authority", "reliable")
func s_session(mode: int, level_id: String, diff: int, mutator: String) -> void:
	_apply_session_change(mode, level_id, diff, mutator)

@rpc("authority", "reliable")
func s_add_bots(count: int) -> void:
	_apply_add_bots(count)

@rpc("authority", "reliable")
func s_team_mode(on: bool) -> void:
	Game.team_mode = on
	Game.my_team = Game.Team.RED if hosting else Game.Team.BLUE
	Game.round_state_changed.emit()

# Restart the level with the host's new selection. Routes through main.gd's
# start_game() (same path menu.gd's board uses), so nothing here re-implements
# level construction. Difficulty/mutator apply live; mode/level rebuild.
func _apply_session_change(mode: int, level_id: String, diff: int, mutator: String) -> void:
	Game.mode = mode
	Game.level_id = level_id
	Game.difficulty = diff
	Game.mutator = mutator
	var m = get_tree().get_first_node_in_group("main")
	if m:
		m.call_deferred("start_game")

# Host-only: drop `count` extra enemy tanks into the live EnemyManager. Client
# receives them through the normal coop snapshot replica stream, so this only
# actually spawns on the host (the sim authority).
func _apply_add_bots(count: int) -> void:
	if not hosting:
		return
	var em := get_tree().get_first_node_in_group("enemy_manager")
	if em and em.has_method("spawn_bots"):
		em.spawn_bots(count)

# ================================================================ seat-swap
# Co-op only: swap which peer drives vs. gunners. Either peer can request it
# (any_peer); the host is the authority that flips driver_is_host and echoes
# the new assignment to the client via s_seats().
func request_seat_swap() -> void:
	if Game.mode != Game.Mode.COOP or not active() or not has_player():
		return
	if hosting:
		_do_seat_swap()
	elif _transport == Transport.RELAY:
		_relay_send({"type": "evt", "e": "c_swap_seats", "echo": false})
	else:
		c_swap_seats.rpc_id(1)

@rpc("any_peer", "reliable")
func c_swap_seats() -> void:
	if hosting:
		_do_seat_swap()

func _do_seat_swap() -> void:
	driver_is_host = not driver_is_host
	_apply_seat_roles()
	if _transport == Transport.RELAY:
		_relay_send({"type": "evt", "e": "s_seats", "hd": driver_is_host, "echo": false})
	else:
		s_seats.rpc(driver_is_host)
	Sfx.play_at("switch", tank.global_position if tank else Vector3.ZERO, -2.0)

@rpc("authority", "reliable")
func s_seats(host_drives: bool) -> void:
	driver_is_host = host_drives
	_apply_seat_roles()
	Sfx.play_at("switch", tank.global_position if tank else Vector3.ZERO, -2.0)

# ================================================================ names + teams
@rpc("any_peer", "reliable")
func v_hello(pname: String, _team: int, tmode: bool, p_vehicle := "tank") -> void:
	Game.peer_name = pname
	Game.peer_vehicle = p_vehicle
	Game.team_mode = tmode
	# assign fixed teams once team mode is on: host RED, client BLUE
	if tmode:
		Game.my_team = Game.Team.RED if hosting else Game.Team.BLUE
	_refresh_name_billboards()
	Game.round_state_changed.emit()
	# versus: now that we know the peer's vehicle, build (or rebuild, if they
	# picked something else on a reconnect) their replica.
	if Game.mode == Game.Mode.VERSUS:
		_ensure_remote_vehicle()

# Label3D billboard over a peer's head/turret — same idiom as
# energy_drink.gd's brand label (Label3D, billboard-enabled, no depth cull).
# Keyed by the target node so leave()/_refresh can restyle or drop them.
var _name_billboards := {}

func _spawn_name_billboard(target: Node3D, id: int, offset := Vector3(0, 1.9, 0)) -> void:
	if target == null:
		return
	var l := Label3D.new()
	l.text = Game.peer_name if Game.peer_name != "" else "Player"
	l.font_size = 96
	l.pixel_size = 0.0016
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Game.team_tint(_team_for(id)) if Game.team_mode else AvatarCosmetics.tint_for(id)
	l.position = offset
	target.add_child(l)
	_name_billboards[target] = l

func _team_for(id: int) -> int:
	# host is RED, client is BLUE (see host_set_team_mode); `id` is that peer's
	# AvatarCosmetics id, so map HOST->RED, CLIENT->BLUE.
	return Game.Team.RED if id == AvatarCosmetics.PlayerId.HOST else Game.Team.BLUE

func _refresh_name_billboards() -> void:
	for target in _name_billboards.keys():
		if not is_instance_valid(target):
			continue
		var l: Label3D = _name_billboards[target]
		l.text = Game.peer_name if Game.peer_name != "" else "Player"
		l.modulate = Game.team_tint(_team_for(their_id())) if Game.team_mode else AvatarCosmetics.tint_for(their_id())

# ================================================================ avatars
# Rec Room energy: round head, big visor body. AvatarRig (scripts/
# avatar_rig.gd) absorbs the old hand-built mesh here — SEATED mode is the
# same legless bean, now with arms that track the gunner's hands.
var _crew_avatar: AvatarRig = null

# Team mode recolors avatars by team (host RED, client BLUE) instead of by
# per-player id — a single knob so crew-avatar + remote-tank + name billboard
# all agree on the same color scheme.
func _avatar_tint(id: int) -> Color:
	return Game.team_tint(_team_for(id)) if Game.team_mode else AvatarCosmetics.tint_for(id)

func _ensure_crew_avatar() -> void:
	# is_instance_valid, NOT == null: the avatar is freed with the tank on
	# world teardown, and a freed instance doesn't equal null -- the old check
	# meant the crew body never respawned in any later session (2026-07-16).
	if not is_instance_valid(_crew_avatar) and tank:
		_crew_avatar = AvatarRig.new()
		tank.add_child(_crew_avatar)
		_crew_avatar.configure(AvatarRig.Mode.SEATED, _avatar_tint(their_id()))
		CockpitBuilder.set_interior_layer(_crew_avatar)

func _my_head_rel() -> Transform3D:
	var m = get_tree().get_first_node_in_group("main")
	if m and tank and m.rig and m.rig.get("camera"):
		return tank.global_transform.affine_inverse() * m.rig.camera.global_transform
	return Transform3D()

## Sibling to _my_head_rel() — hand transform relative to the tank. left=true
## for hand_l, false for hand_r. Returns identity if no hand tracking exists
## (e.g. DesktopRig has no hand_l/hand_r at all).
func _my_hand_rel(left: bool) -> Transform3D:
	var m = get_tree().get_first_node_in_group("main")
	if not (m and tank and m.rig):
		return Transform3D()
	var hand = m.rig.get("hand_l") if left else m.rig.get("hand_r")
	if hand == null:
		return Transform3D()
	return tank.global_transform.affine_inverse() * hand.global_transform

## Stub returning 0 until Phase A's on-foot locomotion exposes real
## sprint/climb/grapple state through a queryable API — flagged dependency,
## see the plan's Phase B section on "both-players-on-foot-simultaneously".
## Seated driver/gunner crew never sprint/climb/grapple anyway, so 0 is
## correct today, not just a placeholder.
func _my_move_flags() -> int:
	return 0

func _apply_crew_avatar(head_rel: Transform3D, hand_l_rel: Transform3D, hand_r_rel: Transform3D, move_flags: int) -> void:
	_ensure_crew_avatar()
	if _crew_avatar:
		_crew_avatar.set_net_target(head_rel, hand_l_rel, hand_r_rel, move_flags)

# ================================================================ replicas
class RemoteVehicle:
	extends CharacterBody3D

	# Local to versus-mode replication -- deliberately NOT ReplicaPool's enemy-
	# type ints (co-op's "type 3" means gunner infantry there; reusing that
	# numbering here would be a confusing coincidence, not a shared meaning).
	enum VehicleType { TANK, JEEP, BOAT, PLANE }

	# Tank-sized box was the only option pre-refactor; a jeep/boat/plane
	# replica with a tank hitbox is an immediately-visible correctness bug,
	# not a cosmetic one -- kept as a small per-type table instead.
	const _HITBOX_SIZE := {
		VehicleType.TANK: Vector3(3.2, 1.4, 6.2),
		VehicleType.JEEP: Vector3(1.8, 1.6, 3.4),
		VehicleType.BOAT: Vector3(2.0, 1.4, 5.0),
		VehicleType.PLANE: Vector3(6.0, 1.6, 6.0),
	}

	var type: int
	var turret: Node3D          # only tank has a genuinely separate turret mesh to spin (see _ready())
	var _avatar: AvatarRig
	var _target := Transform3D()
	var _turret_y := 0.0
	var _has_target := false

	func _init(p_type: int) -> void:
		type = p_type
		collision_layer = 4
		collision_mask = 0
		add_to_group("enemies")

	func _ready() -> void:
		match type:
			VehicleType.JEEP:
				EnemyLight.Jeep._build()
				var m := MeshInstance3D.new()
				m.mesh = EnemyLight.Jeep._mesh
				add_child(m)
			VehicleType.BOAT:
				EnemyShip._build()
				var m := MeshInstance3D.new()
				m.mesh = EnemyShip._mesh
				add_child(m)
			VehicleType.PLANE:
				EnemyPlane._build_mesh()
				var m := MeshInstance3D.new()
				m.mesh = EnemyPlane._mesh
				add_child(m)
			_:  # TANK -- the only type with a real separate turret node, so it's
				# the only one that visually shows the opponent's aim (see
				# net_target()/_physics_process()). Jeep/boat meshes are single
				# unified ArrayMesh blobs (gun built into the hull mesh, not a
				# separable sub-mesh) -- splitting those is real extra scope
				# (touches enemy_light.gd/enemy_ship.gd), so v1 replicates their
				# position only; their gun doesn't visibly track aim yet.
				EnemyTank._build_meshes()
				var hull := MeshInstance3D.new()
				hull.mesh = EnemyTank._hull_mesh
				add_child(hull)
				turret = Node3D.new()
				turret.position = Vector3(0, 1.45, -0.2)
				add_child(turret)
				var tm := MeshInstance3D.new()
				tm.mesh = EnemyTank._turret_mesh
				turret.add_child(tm)
		# the other kid, peeking out of the hatch/cockpit -- rides on the
		# turret when there is one (tank), else on the hull root directly.
		_avatar = AvatarRig.new()
		_avatar.position = Vector3(-0.28, 1.15, 0.25)
		(turret if turret else self).add_child(_avatar)
		_avatar.configure(AvatarRig.Mode.SEATED, NetManager._avatar_tint(NetManager.their_id()))
		if Game.mutator == "balloon":
			Game.balloonize(self)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = _HITBOX_SIZE.get(type, _HITBOX_SIZE[VehicleType.TANK])
		shape.shape = box
		shape.position = Vector3(0, 1.0, 0)
		add_child(shape)

	func net_target(t: Transform3D, aim_yaw: float, _aim_pitch: float, head_rel := Transform3D(),
			hand_l_rel := Transform3D(), hand_r_rel := Transform3D(), move_flags := 0) -> void:
		_target = t
		_turret_y = aim_yaw
		_has_target = true
		if _avatar and head_rel != Transform3D():
			_avatar.set_net_target(head_rel, hand_l_rel, hand_r_rel, move_flags)

	func _physics_process(delta: float) -> void:
		if not _has_target:
			return
		global_transform = global_transform.interpolate_with(_target, clampf(10.0 * delta, 0, 1))
		if turret:
			turret.rotation.y = lerp_angle(turret.rotation.y, _turret_y, clampf(10.0 * delta, 0, 1))

	func take_damage(amount: float, at: Vector3) -> void:
		Sfx.play_at("hit", at, -4.0)
		NetManager.send_damage(amount)   # routes to ENet rpc or relay


class ReplicaPool:
	extends Node3D

	var _nodes := {}   # net id -> {root, turret, type}

	func apply(enemies: Array) -> void:
		var seen := {}
		for e in enemies:
			var type: int = e[0]
			var id: int = e[1]
			var t: Transform3D = e[2]
			var aux: float = e[3]
			seen[id] = true
			if not _nodes.has(id):
				_nodes[id] = _spawn(type)
			var n: Dictionary = _nodes[id]
			n.root.set_meta("target", t)
			if n.turret:
				n.turret.rotation.y = aux
		for id in _nodes.keys():
			if not seen.has(id):
				_nodes[id].root.queue_free()
				_nodes.erase(id)

	func _physics_process(delta: float) -> void:
		for id in _nodes:
			var n: Dictionary = _nodes[id]
			var target = n.root.get_meta("target", null)
			if target != null:
				n.root.global_transform = n.root.global_transform.interpolate_with(target, clampf(12.0 * delta, 0, 1))

	func _spawn(type: int) -> Dictionary:
		var root := Node3D.new()
		add_child(root)
		var turret: Node3D = null
		match type:
			0:
				EnemyTank._build_meshes()
				var h := MeshInstance3D.new()
				h.mesh = EnemyTank._hull_mesh
				root.add_child(h)
				turret = Node3D.new()
				turret.position = Vector3(0, 1.45, -0.2)
				root.add_child(turret)
				var tm := MeshInstance3D.new()
				tm.mesh = EnemyTank._turret_mesh
				turret.add_child(tm)
			1:
				EnemyPlane._build_mesh()
				var m := MeshInstance3D.new()
				m.mesh = EnemyPlane._mesh
				root.add_child(m)
			2:
				EnemyLight.Jeep._build()
				var m := MeshInstance3D.new()
				m.mesh = EnemyLight.Jeep._mesh
				root.add_child(m)
			3:
				# Gunner's visual body is an AvatarRig now (no static _mesh to
				# reuse) — client-side replicas get their own idle-pose
				# instance, driven by the same authored pose constants.
				var av := AvatarRig.new()
				root.add_child(av)
				av.configure(AvatarRig.Mode.ON_FOOT, EnemyLight.Gunner.UNIFORM)
				av.update_live(0.0, EnemyLight.Gunner.HEAD_LOCAL, EnemyLight.Gunner.HAND_L_LOCAL, EnemyLight.Gunner.HAND_R_LOCAL)
			4:
				EnemyLight.Mortar._build()
				var m := MeshInstance3D.new()
				m.mesh = EnemyLight.Mortar._mesh
				root.add_child(m)
		return {"root": root, "turret": turret, "type": type}
