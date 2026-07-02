# Level definitions. Terrain + WorldDressing read these configs.
class_name Levels
extends Object

static var current: Dictionary = {}

const CONFIGS := {
	"outdoor": {
		"title": "OUTDOOR",
		"rolling": 9.0, "dunes": true, "pond": true,
		"flatten": [],  # village/spawn flatten handled by defaults
		"trees": 230, "rocks": 90,
		"village": {"center": Vector2(120, -120), "count": 12, "spread": 42.0},
		"city": {}, "castle": {}, "mud": [],
		"wrecks": 3,
		"spawn": Vector2(0, 90),
		"mortars": [Vector2(-80, -140), Vector2(170, 40)],
		"tint": Color(1, 1, 1),
		"sun_energy": 1.25,
	},
	"city": {
		"title": "CITY",
		"rolling": 4.0, "dunes": false, "pond": false,
		"flatten": [[Vector2(0, -40), 130.0, 1.0]],
		"trees": 60, "rocks": 30,
		"village": {},
		"city": {"center": Vector2(0, -40), "rows": 5, "cols": 6, "spacing": 26.0,
			"h_min": 7.0, "h_max": 22.0, "street": 9.0},
		"castle": {}, "mud": [],
		"wrecks": 5,
		"spawn": Vector2(0, 140),
		"mortars": [Vector2(-110, -120), Vector2(110, -120), Vector2(0, -170)],
		"tint": Color(0.96, 0.96, 1.0),
		"sun_energy": 1.15,
		"calm_track": "music_city",
	},
	"town": {
		"title": "TOWN",
		"rolling": 7.0, "dunes": false, "pond": true,
		"flatten": [],
		"trees": 300, "rocks": 60,
		"village": {"center": Vector2(40, -60), "count": 26, "spread": 75.0},
		"city": {}, "castle": {}, "mud": [],
		"wrecks": 2,
		"spawn": Vector2(-20, 130),
		"mortars": [Vector2(140, -140)],
		"tint": Color(1.0, 1.0, 0.94),
		"sun_energy": 1.3,
		"calm_track": "music_town",
	},
	"mudpit": {
		"title": "MUDPIT",
		"rolling": 3.5, "dunes": false, "pond": false,
		"flatten": [[Vector2(0, 0), 105.0, -2.5]],
		"trees": 25, "rocks": 45,
		"village": {},
		"city": {}, "castle": {},
		"mud": [Vector2(0, 0), Vector2(45, -35), Vector2(-50, 30), Vector2(20, 55), Vector2(-35, -55)],
		"wrecks": 7,
		"spawn": Vector2(0, 150),
		"mortars": [Vector2(-130, -60), Vector2(130, -60)],
		"tint": Color(0.85, 0.78, 0.7),
		"sun_energy": 1.0,
		"calm_track": "music_mudpit",
	},
	"gym": {
		"title": "GYM",
		"rolling": 0.2, "dunes": false, "pond": false, "rim": false,
		"flatten": [],
		"trees": 0, "rocks": 0,
		"village": {}, "city": {}, "castle": {}, "mud": [],
		"wrecks": 0,
		"gym": true, "cardboard": true,
		"floor_tex": "court",
		"arena_radius": 105.0,
		"spawn": Vector2(0, 80),
		"spawn_ring": [55.0, 90.0],
		"mortars": [Vector2(-60, -70), Vector2(60, -70)],
		"tint": Color(1, 1, 1),
		"sun_energy": 1.1,
		"calm_track": "music_gym",
	},
	"beach": {
		"title": "BEACH",
		"rolling": 4.5, "dunes": true, "pond": false, "coast": true,
		"flatten": [],
		"trees": 0, "palms": 70, "rocks": 40,
		"village": {"center": Vector2(60, 60), "count": 8, "spread": 34.0},
		"city": {}, "castle": {}, "mud": [],
		"wrecks": 1,
		"spawn": Vector2(0, 120),
		"mortars": [Vector2(-120, 60)],
		"tint": Color(1.05, 1.0, 0.92),
		"sun_energy": 1.4,
		"calm_track": "music_beach",
		"ambient_loop": "waves_loop",
	},
	"island": {
		"title": "ISLAND",
		"rolling": 8.0, "dunes": false, "pond": false, "island": true,
		"flatten": [],
		"trees": 120, "palms": 50, "rocks": 50,
		"village": {"center": Vector2(0, -40), "count": 7, "spread": 30.0},
		"city": {}, "castle": {}, "mud": [],
		"wrecks": 2,
		"arena_radius": 128.0,
		"spawn": Vector2(0, 90),
		"spawn_ring": [50.0, 100.0],
		"mortars": [Vector2(-70, -70)],
		"tint": Color(1.0, 1.02, 0.95),
		"sun_energy": 1.35,
		"calm_track": "music_island",
		"ambient_loop": "waves_loop",
	},
	"volcano": {
		"title": "VOLCANO",
		"rolling": 2.0, "dunes": false, "pond": false, "volcano": true,
		"flatten": [],
		"trees": 0, "rocks": 60,
		"village": {}, "city": {}, "castle": {}, "mud": [],
		"wrecks": 0,
		"arena_radius": 108.0,
		"lava_y": -3.2,
		"spawn": Vector2(0, 55),
		"spawn_ring": [40.0, 62.0],
		"mortars": [],
		"tint": Color(0.85, 0.72, 0.68),
		"sun_energy": 0.85,
		"ambient_loop": "lava_loop",
		"calm_track": "music_volcano",
	},
	"babyroom": {
		"title": "BABY ROOM",
		"rolling": 0.1, "dunes": false, "pond": false, "rim": false,
		"flatten": [],
		"trees": 0, "rocks": 0,
		"village": {}, "city": {}, "castle": {}, "mud": [],
		"wrecks": 0,
		"gym": false, "babyroom": true, "baby": true, "army_green": true,
		"floor_tex": "carpet",
		"arena_radius": 112.0,
		"spawn": Vector2(0, 85),
		"spawn_ring": [50.0, 90.0],
		"mortars": [],
		"tint": Color(1, 1, 1),
		"sun_energy": 1.05,
		"calm_track": "music_toy",
	},
	"castle": {
		"title": "CASTLE",
		"rolling": 6.0, "dunes": false, "pond": false,
		"flatten": [[Vector2(0, -30), 95.0, 2.0]],
		"trees": 140, "rocks": 70,
		"village": {},
		"city": {}, "castle": {"center": Vector2(0, -30)},
		"mud": [],
		"wrecks": 2,
		"spawn": Vector2(0, 150),
		"mortars": [Vector2(-45, -75), Vector2(45, -75)],  # inside the walls
		"tint": Color(1.0, 0.97, 0.9),
		"sun_energy": 1.2,
		"calm_track": "music_castle",
	},
}

const ORDER := ["outdoor", "city", "town", "mudpit", "castle", "gym", "beach", "island", "volcano", "babyroom"]
static var cardboard := false   # set at level build; enemies check it
static var army_green := false  # baby room: little green army men

static func get_config(id: String) -> Dictionary:
	return CONFIGS.get(id, CONFIGS["outdoor"])

# mud slow-zone query (set by WorldDressing at build)
static var mud_pools: Array = []
static var mud_radius := 26.0

static func mud_factor(pos: Vector3) -> float:
	for p in mud_pools:
		if Vector2(pos.x, pos.z).distance_to(p) < mud_radius:
			return 0.5
	return 1.0
