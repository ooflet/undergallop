class_name Race
extends RefCounted

const NOISE := 0.08
const PLAYER_NAME := "2steedy"

const ROSTER := [
	{"name": "Understables", "rating": 240.0},
	{"name": "Jane Trotter", "rating": 231.0},
	{"name": "Fakemane", "rating": 222.0},
	{"name": "Beuck", "rating": 214.0},
	{"name": "Lucy Baroque", "rating": 206.0},
	{"name": "Nettstallion", "rating": 198.0},
	{"name": "2hooves", "rating": 186.0},
	{"name": "Racersobased", "rating": 176.0},
	{"name": "Osamuzzle", "rating": 166.0},
]


static func run(player_score: float, rating_scale: float = 1.0) -> Array:
	var rows: Array = [{"name": PLAYER_NAME, "score": player_score * randf_range(1.0 - NOISE, 1.0 + NOISE), "is_player": true}]
	for r in ROSTER:
		var rating: float = float(r["rating"]) * rating_scale
		rows.append({"name": r["name"], "score": rating * randf_range(1.0 - NOISE, 1.0 + NOISE), "is_player": false})
	rows.sort_custom(func(a, b): return a["score"] > b["score"])
	return rows


static func placement(rows: Array) -> int:
	for i in rows.size():
		if rows[i]["is_player"]:
			return i + 1
	return rows.size()
