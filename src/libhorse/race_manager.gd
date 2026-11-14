# horse

extends Node3D

const Racer := preload("horse_racer.gd")
const Track := preload("track_path.gd")

signal countdown_tick(seconds_left: int)
signal race_started
signal race_finished(results: Array)

@export_group("Assets")
@export var horse_scene: PackedScene
@export_file("*.json") var track_json := ""
@export var track_mesh: Node3D
@export var track_root: Node3D
@export var track_scale := 4.0
@export var track_offset := Vector3.ZERO
@export var reverse_direction := false
@export_range(0.0, 1.0, 0.001) var start_position := 0.0

@export_group("Race")
@export var laps := 1
@export var race_duration := 20.0
@export_range(0, 17) var opponents := 7
@export_range(1, 8) var lane_count := 4
@export var auto_start := true
@export var start_delay := 3.0
@export var random_seed := 0
@export_range(0.0, 1.0, 0.05) var opponent_strength := 0.5

@export_group("Player horse")
@export var player_name := "Slow Dancer"
@export_enum("Front Runner", "Pace Chaser", "Late Surger", "End Closer") var player_style := 1
@export_range(0.0, 1.0, 0.01) var player_speed := 0.6
@export_range(0.0, 1.0, 0.01) var player_stamina := 0.6
@export_range(0.0, 1.0, 0.01) var player_power := 0.6
@export_range(0.0, 1.0, 0.01) var player_guts := 0.5
@export_range(0.0, 1.0, 0.01) var player_wisdom := 0.5
@export var player_gate := -1

@export_group("Visuals")
@export var horse_scale := 0.14
@export var follow_camera := true
@export_range(30.0, 120.0, 1.0) var camera_fov := 80.0
@export var camera_distance := 6.0
@export var camera_height := 2.2
@export var show_hud := false
@export var show_name_tags := true
@export var horse_height := 0.0
@export_range(0.1, 5.0, 0.05) var animation_speed := 1.1
@export var bank_gain := 1.2

var track: Track
var racers: Array[Racer] = []
var player: Racer
var race_time := 0.0
var racing := false
var results: Array = []

var _rng := RandomNumberGenerator.new()
var _root: Node3D
var _camera: Camera3D
var _hud: Label
var _countdown := -1.0
var _base_speed := 1.0
var _total_distance := 1.0
var _decision_timers := {}
var _pending_start := false

const NAMES := ["Nettstallion", "Beuck", "Osamuzzle", "2hooves", "Jane Trotter",
	"understables", "Fakemane", "Racersobased", "Lucy Baroque"]
const COATS := [Color(0.62, 0.45, 0.34), Color(0.38, 0.34, 0.32), Color(0.82, 0.70, 0.55),
	Color(0.50, 0.38, 0.30), Color(0.72, 0.72, 0.76), Color(0.30, 0.26, 0.25), Color.WHITE]
const SILKS := [Color(1.0, 0.45, 0.45), Color(0.55, 1.0, 0.55), Color(1.0, 0.7, 0.3), Color(0.85, 0.5, 1.0),
	Color(1.0, 1.0, 0.45), Color(0.45, 0.9, 1.0), Color(1.0, 0.55, 0.85), Color(0.75, 0.75, 0.75)]


func _ready() -> void:
	if random_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = random_seed

	var dir := (get_script() as Script).resource_path.get_base_dir()
	if horse_scene == null:
		horse_scene = load(dir + "/horse_gallop.glb") as PackedScene
	var json_path := track_json if track_json != "" else dir + "/track_path.json"
	var mesh_node: Node3D = track_mesh
	if mesh_node == null and track_root != null:
		mesh_node = _find_track_mesh(track_root)
	if mesh_node != null:
		print("RaceManager: using track mesh '%s' (scale %s)" % [mesh_node.get_path(), mesh_node.global_transform.basis.get_scale()])
	else:
		push_warning("RaceManager: no track mesh found; using the raw track.obj coordinates")
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * track_scale), track_offset)
	if mesh_node != null:
		xf = mesh_node.global_transform
	track = Track.new()
	if not track.load_from(json_path, xf, reverse_direction) or horse_scene == null:
		track = null
		push_error("RaceManager: missing track or horse scene")
		return

	_root = Node3D.new()
	_root.name = "Racers"
	_root.top_level = true
	add_child(_root)

	_total_distance = track.length * laps
	_base_speed = _total_distance / race_duration

	spawn_default_field()
	if follow_camera:
		_make_camera()
	if show_hud:
		_make_hud()
	if auto_start:
		begin_countdown()


func _find_track_mesh(root: Node) -> Node3D:
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	var biggest: Node3D = null
	var biggest_size := -1.0
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		if String(mi.name).to_lower().contains("track"):
			return mi
		var size := mi.get_aabb().get_longest_axis_size() * mi.global_transform.basis.get_scale().x
		if size > biggest_size:
			biggest_size = size
			biggest = mi
	return biggest



func spawn_default_field() -> void:
	var lineup: Array[Dictionary] = []
	lineup.append({
		"name": player_name, "player": true, "style": player_style,
		"speed": player_speed, "stamina": player_stamina, "power": player_power,
		"guts": player_guts, "wisdom": player_wisdom,
		"coat": Color.WHITE, "silks": Color.WHITE,
	})
	var names := NAMES.duplicate()
	_shuffle(names)
	var coats := COATS.duplicate()
	var silks := SILKS.duplicate()
	for i in opponents:
		var st := i % 4
		var base := 0.35 + 0.4 * opponent_strength
		var biases: Dictionary = {
			Racer.Style.FRONT_RUNNER: [0.08, -0.06, 0.0],
			Racer.Style.PACE_CHASER: [0.0, 0.0, 0.0],
			Racer.Style.LATE_SURGER: [-0.02, 0.02, 0.05],
			Racer.Style.END_CLOSER: [-0.03, 0.05, 0.08],
		}
		var bias: Array = biases[st]
		lineup.append({
			"name": names[i % names.size()], "player": false, "style": st,
			"speed": _stat(base + bias[0]), "stamina": _stat(base + bias[1]),
			"power": _stat(base + bias[2]), "guts": _stat(base), "wisdom": _stat(base),
			"coat": coats[i % coats.size()], "silks": silks[i % silks.size()],
		})
	spawn_lineup(lineup)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp


func _stat(v: float) -> float:
	return clampf(v + _rng.randf_range(-0.15, 0.15), 0.15, 0.95)


func spawn_lineup(lineup: Array[Dictionary]) -> void:
	var n := lineup.size()
	var usable := track.width * 0.92
	var lanes := n
	var spacing := usable / float(lanes)
	var scale_v := horse_scale if horse_scale > 0.001 else 0.045
	var len_w := Racer.MODEL_LENGTH * scale_v
	var limit := usable * 0.5 - Racer.MODEL_WIDTH * scale_v * 0.5

	var gates: Array[int] = []
	for i in n:
		gates.append(i)
	_shuffle(gates)
	for i in n:
		if lineup[i].get("player", false) and player_gate >= 0 and player_gate < n:
			var idx := gates.find(player_gate)
			var tmp := gates[i]
			gates[i] = player_gate
			gates[idx] = tmp

	for i in n:
		var info := lineup[i]
		var g := gates[i]
		var r := Racer.new()
		r.name = String(info["name"]).replace(" ", "_")
		r.horse_name = info["name"]
		r.is_player = info.get("player", false)
		r.style = info["style"]
		r.stat_speed = info["speed"]
		r.stat_stamina = info["stamina"]
		r.stat_power = info["power"]
		r.stat_guts = info["guts"]
		r.stat_wisdom = info["wisdom"]
		r.coat_tint = info.get("coat", Color.WHITE)
		r.silks_tint = info.get("silks", Color.WHITE)
		r.track = track
		r.base_speed = _base_speed
		r.total_distance = _total_distance
		r.start_s = start_position * track.length
		r.horse_scale = scale_v
		r.lateral_limit = maxf(limit, 0.0)
		r.lane_move_speed = usable * 0.35
		r.rng = _rng
		r.bank_gain = bank_gain
		r.show_name_tag = show_name_tags
		r.height_offset = horse_height
		r.anim_speed_mult = animation_speed

		var lane := g % lanes
		var row := 0
		r.lateral = clampf(-usable * 0.5 + spacing * (lane + 0.5), -r.lateral_limit, r.lateral_limit)
		r.target_lateral = r.lateral
		r.distance = -len_w * 0.5

		_root.add_child(r)
		r.build(horse_scene)
		r.finished.connect(_on_racer_finished)
		racers.append(r)
		if r.is_player:
			player = r
		r.tick(0.0, 0.0)
	_update_ranks()



func begin_countdown() -> void:
	_countdown = start_delay
	_pending_start = true


func start_race() -> void:
	racing = true
	race_time = 0.0
	for r in racers:
		r.start_race()
	race_started.emit()


func _process(delta: float) -> void:
	if track == null:
		return
	delta = minf(delta, 0.05)

	if _pending_start:
		var before := ceili(_countdown)
		_countdown -= delta
		if ceili(_countdown) != before and _countdown > 0.0:
			countdown_tick.emit(ceili(_countdown))
		if _countdown <= 0.0:
			_pending_start = false
			start_race()

	if racing:
		race_time += delta
		_run_ai(delta)

	for r in racers:
		r.tick(delta, race_time)
	_update_ranks()
	_update_camera(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if player != null and event.is_action_pressed("ui_accept"):
		player.use_skill()


func _on_racer_finished(r: Racer) -> void:
	results.append({"rank": results.size() + 1, "name": r.horse_name, "time": r.finish_time,
		"is_player": r.is_player, "style": Racer.STYLE_NAMES[r.style]})
	if results.size() == racers.size():
		racing = false
		race_finished.emit(results)


func _update_ranks() -> void:
	var order := racers.duplicate()
	order.sort_custom(_ahead_of)
	for i in order.size():
		order[i].rank = i + 1


func _ahead_of(a: Racer, b: Racer) -> bool:
	var af := a.state == Racer.State.FINISHED
	var bf := b.state == Racer.State.FINISHED
	if af and bf:
		return a.finish_time < b.finish_time
	if af != bf:
		return af
	return a.distance > b.distance


func _by_rank(a: Racer, b: Racer) -> bool:
	return a.rank < b.rank



func _run_ai(delta: float) -> void:
	for h in racers:
		h.speed_cap = INF
		if h.state != Racer.State.RACING:
			continue
		var len_w := h.len_world
		var wid_w := h.wid_world

		var blocked := false
		for o in racers:
			if o == h or o.state == Racer.State.GATE:
				continue
			var gap := o.distance - h.distance
			if gap > 0.0 and gap < len_w * 1.1 and absf(o.lateral - h.lateral) < wid_w * 1.1:
				h.speed_cap = minf(h.speed_cap, o.speed * 0.995)
			if gap > 0.0 and gap < len_w * 2.2 and absf(o.lateral - h.lateral) < wid_w * 1.15 \
					and o.speed < h.speed * 1.02:
				blocked = true

		var t: float = _decision_timers.get(h, _rng.randf() * 0.3) - delta
		if t <= 0.0:
			t = 0.25 + _rng.randf() * 0.15
			var step := wid_w * 1.25
			if blocked:
				var order := [1.0, -1.0] if _rng.randf() < 0.5 else [-1.0, 1.0]
				for side in order:
					var cand := clampf(h.target_lateral + side * step, -h.lateral_limit, h.lateral_limit)
					if cand != h.target_lateral and _lane_clear(h, cand):
						h.target_lateral = cand
						break
			else:
				var want := h.preferred_lateral(track.inside_sign)
				var diff := want - h.target_lateral
				if absf(diff) > wid_w * 0.3:
					var cand := h.target_lateral + signf(diff) * minf(step, absf(diff))
					if _lane_clear(h, cand):
						h.target_lateral = cand
		_decision_timers[h] = t


func _lane_clear(h: Racer, lat: float) -> bool:
	for o in racers:
		if o == h or o.state == Racer.State.GATE:
			continue
		var gap := o.distance - h.distance
		if gap > -h.len_world * 1.2 and gap < h.len_world * 1.6:
			if absf(o.lateral - lat) < h.wid_world * 1.2 or absf(o.target_lateral - lat) < h.wid_world * 1.2:
				return false
	return true



func _make_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "RaceCamera"
	_camera.top_level = true
	_camera.near = 0.01
	_camera.fov = camera_fov
	_camera.far = 500.0
	add_child(_camera)
	_camera.current = true
	_update_camera(1.0)


func _update_camera(delta: float) -> void:
	if _camera == null or player == null:
		return
	var len_w := track.width * 0.32
	var fwd := player.forward()
	var focus := player.global_position + Vector3.UP * len_w * 0.3
	var desired := focus - fwd * len_w * camera_distance + Vector3.UP * len_w * camera_height
	var k := 1.0 - exp(-5.0 * delta)
	_camera.global_position = _camera.global_position.lerp(desired, k)
	_camera.look_at(focus, Vector3.UP)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)


func _update_hud() -> void:
	if _hud == null:
		return
	if _pending_start:
		_hud.text = "Starting in %d..." % maxi(1, ceili(_countdown))
		return
	var order := racers.duplicate()
	order.sort_custom(_by_rank)
	var lines := PackedStringArray()
	for r in order:
		var mark := ">" if r.is_player else " "
		var stamina := int(clampf(r.hp / r.hp_max, 0.0, 1.0) * 100.0)
		var tail := "  %.2fs" % r.finish_time if r.state == Racer.State.FINISHED else "  STA %d%%" % stamina
		lines.append("%s %2d. %s %s%s" % [mark, r.rank, r.horse_name.rpad(15), Racer.STYLE_NAMES[r.style], tail])
	if player != null and not player.skill_used and racing:
		lines.append("")
		lines.append("[Enter/Space] use skill (+8% speed for 3 s)")
	_hud.text = "\n".join(lines)
