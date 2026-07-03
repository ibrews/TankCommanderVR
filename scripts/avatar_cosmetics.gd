# Single source of truth for player-avatar tint. Replaces the tint ternary
# duplicated in net.gd's _ensure_crew_avatar() and RemoteTank._ready()
# (host=orange, client=blue — same values as before, just centralized).
class_name AvatarCosmetics
extends Object

enum PlayerId { HOST, CLIENT }

const HOST_TINT := Color(0.9, 0.45, 0.15)
const CLIENT_TINT := Color(0.2, 0.55, 0.9)

static func tint_for(id: int) -> Color:
	return HOST_TINT if id == PlayerId.HOST else CLIENT_TINT
