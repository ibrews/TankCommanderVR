# Autoload "NetManager": LAN multiplayer over ENet with UDP-broadcast
# discovery (same Wi-Fi, zero config).
#
# CO-OP: host simulates everything. Host station = driver + MG; client is the
# gunner (turret, cannon, breech, rockets) in a puppet tank that mirrors host
# state. Client streams gunner inputs up; host streams tank/enemy snapshots +
# shot events down. Client damage simulation is disabled.
#
# VERSUS: each peer simulates its own tank; opponents appear as a replica
# body. Shooter detects hits on the replica and RPCs damage to the victim.
extends Node

signal join_found(cfg: Dictionary)

const PORT := 40123
const BCAST := 40124
const SNAP_HZ := 15.0

var hosting := false
var client := false
var searching := false

var _peer: ENetMultiplayerPeer
var _beacon: PacketPeerUDP
var _listen: PacketPeerUDP
var _beacon_t := 0.0
var _snap_t := 0.0

var tank: PlayerTank = null          # coop tank (both sides) / my tank (versus)
var replicas: ReplicaPool = null     # client: enemy visuals
var remote_tank: RemoteTank = null   # versus: opponent replica
var projectiles: Projectiles = null
var fx: FxPool = null
var terrain: Terrain = null
var gunner_input := Vector2.ZERO     # host: last gunner aim from client

func is_client() -> bool:
	return client

func active() -> bool:
	return hosting or client

func has_player() -> bool:
	return _peer != null and multiplayer.get_peers().size() > 0

func leave() -> void:
	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	hosting = false
	client = false
	searching = false
	if _beacon:
		_beacon.close()
		_beacon = null
	if _listen:
		_listen.close()
		_listen = null
	tank = null
	replicas = null
	remote_tank = null

func host() -> void:
	leave()
	_peer = ENetMultiplayerPeer.new()
	_peer.create_server(PORT, 1)
	multiplayer.multiplayer_peer = _peer
	hosting = true
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", BCAST)
	print("[net] hosting on :%d, beaconing" % PORT)

func search() -> void:
	leave()
	_listen = PacketPeerUDP.new()
	_listen.bind(BCAST)
	searching = true
	print("[net] searching for host beacon...")

func _process(delta: float) -> void:
	# host beacon (until someone joins)
	if hosting and _beacon and not has_player():
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var msg := "TCVR|%d|%s|%d" % [Game.mode, Game.level_id, Game.difficulty]
			_beacon.put_packet(msg.to_utf8_buffer())
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
	# snapshots
	if Game.state != Game.GState.PLAYING or not active():
		return
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = 1.0 / SNAP_HZ
		if hosting and has_player():
			if Game.mode == Game.Mode.COOP and tank:
				_send_coop_snap()
			elif Game.mode == Game.Mode.VERSUS and tank:
				s_versus_state.rpc(tank.global_transform, tank.turret.rotation.y, tank.gun_elev)
		elif client and tank:
			if Game.mode == Game.Mode.COOP:
				c_gunner.rpc_id(1, tank.turret_input, _my_head_rel())
			elif Game.mode == Game.Mode.VERSUS:
				s_versus_state.rpc(tank.global_transform, tank.turret.rotation.y, tank.gun_elev)

# ================================================================ CO-OP
func setup_coop(t: PlayerTank) -> void:
	tank = t
	var c: Dictionary = t.cockpit["controls"]
	if client:
		t.puppet = true
		if t.projectiles:
			t.projectiles.damage_enabled = false
		# gunner station: driving/engine controls are the host's job
		for k in ["tiller_l", "tiller_r", "gear", "battery", "starter", "lights", "fuel_pump", "horn"]:
			if c.has(k):
				c[k].enabled = false
	else:
		# host = driver: the turret grip belongs to the gunner
		c["grip"].enabled = false

func make_replica_pool(t: Terrain) -> ReplicaPool:
	replicas = ReplicaPool.new()
	terrain = t
	return replicas

func _send_coop_snap() -> void:
	var head := _my_head_rel()
	if head != Transform3D():
		s_driver_head.rpc(head)
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
	s_coop_snap.rpc(tank.global_transform, tank.turret.rotation.y, tank.gun_elev,
		Game.hp, tank.ammo, tank.rockets_left, tank.loaded, tank.engine_on, Game.wave, Game.score, enemies)

@rpc("any_peer", "unreliable_ordered")
func c_gunner(input: Vector2, head_rel := Transform3D()) -> void:
	gunner_input = input
	if head_rel != Transform3D():
		_apply_crew_head(head_rel)

@rpc("any_peer", "reliable")
func c_event(kind: String) -> void:
	# gunner actions applied on the host's authoritative tank
	if not hosting or tank == null:
		return
	match kind:
		"fire":
			tank.fire_cannon(false)
		"breech":
			if not tank.loaded and tank.ammo > 0:
				tank._chamber()
		"rockets":
			tank.rockets_armed = true
			tank.fire_rockets()

var _snap_seen := false

@rpc("authority", "unreliable_ordered")
func s_coop_snap(tank_t: Transform3D, turret_y: float, gun_e: float, hp: float,
		ammo: int, rkts: int, loaded: bool, engine: bool, wave: int, score: int, enemies: Array) -> void:
	if not _snap_seen:
		_snap_seen = true
		print("[net] first coop snapshot applied (%d enemies)" % enemies.size())
	if tank == null:
		return
	tank.net_apply(tank_t, turret_y, gun_e, ammo, rkts, loaded, engine)
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
func s_driver_head(head_rel: Transform3D) -> void:
	_apply_crew_head(head_rel)

@rpc("authority", "reliable")
func s_shot(kind: int, pos: Vector3, vel: Vector3) -> void:
	# visual projectile on the client (damage disabled there)
	if projectiles:
		projectiles.fire(kind, pos, vel, [], true)

func broadcast_shot(kind: int, pos: Vector3, vel: Vector3) -> void:
	if hosting and has_player():
		s_shot.rpc(kind, pos, vel)

# ================================================================ VERSUS
func setup_versus(world: Node3D, t: Terrain, p: Projectiles, f: FxPool, my_tank: PlayerTank) -> void:
	tank = my_tank
	terrain = t
	projectiles = p
	fx = f
	# spawn placement: host south, client north
	var s := t.spawn
	if client:
		my_tank.global_position = Vector3(-s.x, 0, -s.y)
		my_tank.yaw = 0.0
	my_tank.global_position.y = t.height(my_tank.global_position.x, my_tank.global_position.z) + 0.04
	remote_tank = RemoteTank.new()
	world.add_child(remote_tank)
	Sfx.vo("robot_versus_2", 3, 20.0)  # "Round begin. Fight!"
	remote_tank.global_position = Vector3(-s.x, t.height(-s.x, -s.y) + 0.04, -s.y) if not client \
		else Vector3(s.x, t.height(s.x, s.y) + 0.04, s.y)
	Game.game_over.connect(_on_versus_death)

func _on_versus_death() -> void:
	if Game.mode != Game.Mode.VERSUS or not active():
		return
	v_i_died.rpc()
	Game.their_kills += 1
	Game.kills_changed.emit()
	get_tree().create_timer(4.0).timeout.connect(func():
		if Game.state == Game.GState.PLAYING:
			Game.restart())

@rpc("any_peer", "reliable")
func v_i_died() -> void:
	Game.my_kills += 1
	Game.kills_changed.emit()
	Sfx.vo("vo_kill", 2, 5.0)
	if fx and remote_tank:
		fx.explosion(remote_tank.global_position + Vector3(0, 1.5, 0), true, tank.global_position if tank else Vector3.ZERO)

@rpc("any_peer", "unreliable_ordered")
func s_versus_state(t: Transform3D, turret_y: float, gun_e: float) -> void:
	if remote_tank:
		remote_tank.net_target(t, turret_y, gun_e)

@rpc("any_peer", "reliable")
func v_shot(kind: int, pos: Vector3, vel: Vector3) -> void:
	if projectiles:
		projectiles.fire(kind, pos, vel, [], true, true)  # visual only

func versus_shot(kind: int, pos: Vector3, vel: Vector3) -> void:
	if active() and Game.mode == Game.Mode.VERSUS:
		v_shot.rpc(kind, pos, vel)

@rpc("any_peer", "reliable")
func v_damage(amount: float) -> void:
	Game.damage_player(amount / Game.diff(0.6, 1.0, 1.35))  # undo diff scale: pvp is symmetric

# ================================================================ avatars
# Rec Room energy: round head, big visor, floating bean body. No legs. Ever.
static func build_avatar(tint: Color) -> Node3D:
	var root := Node3D.new()
	var st := MeshKit.begin()
	# bean torso
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, -0.32, 0)), 0.13, 0.17, 0.30, 10, tint)
	var body := MeshInstance3D.new()
	body.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.6))
	root.add_child(body)
	# head
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.135
	sm.height = 0.27
	sm.radial_segments = 14
	sm.rings = 8
	head.mesh = sm
	var hm := StandardMaterial3D.new()
	hm.albedo_color = tint.lightened(0.25)
	hm.roughness = 0.5
	head.material_override = hm
	root.add_child(head)
	# visor
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.19, 0.085, 0.09)
	visor.mesh = vb
	var vm := StandardMaterial3D.new()
	vm.albedo_color = Color(0.08, 0.08, 0.1)
	vm.roughness = 0.15
	vm.metallic = 0.4
	visor.material_override = vm
	visor.position = Vector3(0, 0.02, -0.105)
	root.add_child(visor)
	# smile
	var smile := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.07, 0.014, 0.01)
	smile.mesh = sb
	var smm := StandardMaterial3D.new()
	smm.albedo_color = Color(0.15, 0.1, 0.1)
	smile.material_override = smm
	smile.position = Vector3(0, -0.075, -0.128)
	root.add_child(smile)
	return root

var _crew_avatar: Node3D = null
var _crew_target := Transform3D()

func _ensure_crew_avatar() -> void:
	if _crew_avatar == null and tank:
		_crew_avatar = build_avatar(Color(0.9, 0.45, 0.15) if hosting else Color(0.2, 0.55, 0.9))
		tank.add_child(_crew_avatar)
		CockpitBuilder.set_interior_layer(_crew_avatar)

func _my_head_rel() -> Transform3D:
	var m = get_tree().get_first_node_in_group("main")
	if m and tank and m.rig and m.rig.get("camera"):
		return tank.global_transform.affine_inverse() * m.rig.camera.global_transform
	return Transform3D()

func _apply_crew_head(rel: Transform3D) -> void:
	_ensure_crew_avatar()
	if _crew_avatar:
		_crew_target = rel
		_crew_avatar.transform = _crew_avatar.transform.interpolate_with(rel, 0.5)

# ================================================================ replicas
class RemoteTank:
	extends CharacterBody3D

	var turret: Node3D
	var _target := Transform3D()
	var _turret_y := 0.0
	var _has_target := false

	func _init() -> void:
		collision_layer = 4
		collision_mask = 0
		add_to_group("enemies")

	func _ready() -> void:
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
		# the other kid, peeking out of the hatch
		var av := NetManager.build_avatar(Color(0.2, 0.55, 0.9) if NetManager.hosting else Color(0.9, 0.45, 0.15))
		av.position = Vector3(-0.28, 1.15, 0.25)
		turret.add_child(av)
		if Game.mutator == "balloon":
			Game.balloonize(self)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.2, 1.4, 6.2)
		shape.shape = box
		shape.position = Vector3(0, 1.0, 0)
		add_child(shape)

	func net_target(t: Transform3D, ty: float, _ge: float) -> void:
		_target = t
		_turret_y = ty
		_has_target = true

	func _physics_process(delta: float) -> void:
		if not _has_target:
			return
		global_transform = global_transform.interpolate_with(_target, clampf(10.0 * delta, 0, 1))
		turret.rotation.y = lerp_angle(turret.rotation.y, _turret_y, clampf(10.0 * delta, 0, 1))

	func take_damage(amount: float, at: Vector3) -> void:
		Sfx.play_at("hit", at, -4.0)
		NetManager.v_damage.rpc(amount)


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
				EnemyLight.Gunner._build()
				var m := MeshInstance3D.new()
				m.mesh = EnemyLight.Gunner._mesh
				root.add_child(m)
			4:
				EnemyLight.Mortar._build()
				var m := MeshInstance3D.new()
				m.mesh = EnemyLight.Mortar._mesh
				root.add_child(m)
		return {"root": root, "turret": turret, "type": type}
