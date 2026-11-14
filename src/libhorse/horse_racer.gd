extends Node3D

signal finished(racer: Node3D)

const Track := preload("track_path.gd")

# umamusume running styles
enum Style { FRONT_RUNNER, PACE_CHASER, LATE_SURGER, END_CLOSER }
enum State { GATE, RACING, FINISHED }

const MODEL_LENGTH := 2.69
const MODEL_WIDTH := 0.82
const MODEL_HEIGHT := 2.16

const STYLE_PHASE := {
	Style.FRONT_RUNNER: Vector3(1.05, 1.01, 0.99),
	Style.PACE_CHASER: Vector3(1.00, 1.00, 1.00),
	Style.LATE_SURGER: Vector3(0.96, 0.98, 1.00),
	Style.END_CLOSER: Vector3(0.93, 0.96, 1.00),
}
const SPURT_START := {
	Style.FRONT_RUNNER: 0.76,
	Style.PACE_CHASER: 0.72,
	Style.LATE_SURGER: 0.69,
	Style.END_CLOSER: 0.66,
}
const SPURT_BONUS := {
	Style.FRONT_RUNNER: 0.0,
	Style.PACE_CHASER: 0.012,
	Style.LATE_SURGER: 0.025,
	Style.END_CLOSER: 0.04,
}
const STYLE_NAMES := ["Front Runner", "Pace Chaser", "Late Surger", "End Closer"]

var horse_name := "Horse"
var is_player := false
var style: Style = Style.PACE_CHASER
var coat_tint := Color.WHITE
var silks_tint := Color.WHITE
var stat_speed := 0.5
var stat_stamina := 0.5
var stat_power := 0.5
var stat_guts := 0.5
var stat_wisdom := 0.5

var track: Track
var base_speed := 1.0
var total_distance := 1.0
var start_s := 0.0
var horse_scale := 0.1
var lateral_limit := 0.1
var lane_move_speed := 0.1
var rng := RandomNumberGenerator.new()
var stride_length_factor := 2.6
var stride_hz_min := 1.4
var stride_hz_max := 2.6
var bank_gain := 1.2
var max_lean := deg_to_rad(18.0)
var show_name_tag := true
var anim_speed_mult := 1.0
var height_offset := 0.0

var state: State = State.GATE
var distance := 0.0
var speed := 0.0
var lateral := 0.0
var target_lateral := 0.0
var speed_cap := INF
var hp := 1.0
var hp_max := 1.0
var rank := 0
var finish_time := -1.0
var in_last_spurt := false

var skill_left := 0.0
var skill_used := false

var _model: Node3D
var _anim: AnimationPlayer
var _gallop_name := ""
var _idle_name := ""
var _current_anim := ""
var _heading := Vector3.ZERO
var _lean := 0.0
var _lateral_vel := 0.0
var _spurt_speed := 0.0
var _rush_left := 0.0
var _cooldown_t := 0.0
var _ph1 := 0.0
var _ph2 := 0.0

var len_world: float:
	get: return MODEL_LENGTH * horse_scale
var wid_world: float:
	get: return MODEL_WIDTH * horse_scale



func build(scene: PackedScene) -> void:
	_model = scene.instantiate() as Node3D
	_model.scale = Vector3.ONE * horse_scale
	add_child(_model)
	_find_animations()
	_apply_tints()
	if show_name_tag:
		_make_tag()

	hp_max = (total_distance / base_speed) * (0.80 + 0.45 * stat_stamina)
	hp = hp_max
	_ph1 = rng.randf() * TAU
	_ph2 = rng.randf() * TAU
	if rng.randf() < (1.0 - stat_wisdom) * 0.25:
		_rush_left = rng.randf_range(3.0, 6.0)


func _find_animations() -> void:
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		# cock
		push_warning("HorseRacer: no AnimationPlayer in the horse scene")
		return
	_anim = players[0] as AnimationPlayer
	for n in _anim.get_animation_list():
		var lower := String(n).to_lower()
		if lower.contains("gallop"):
			_gallop_name = String(n)
		elif lower.contains("idle"):
			_idle_name = String(n)
		else:
			continue
		_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR


func _apply_tints() -> void:
	_tint_mesh("Skin", coat_tint)
	_tint_mesh("Cloth", silks_tint)


func _tint_mesh(mesh_name: String, color: Color) -> void:
	if color == Color.WHITE:
		return
	var mi := _model.find_child(mesh_name, true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for surf in mi.mesh.get_surface_count():
		var m := mi.get_active_material(surf)
		if m is StandardMaterial3D:
			var copy := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
			copy.albedo_color = color
			mi.set_surface_override_material(surf, copy)


func _make_tag() -> void:
	var l := Label3D.new()
	l.text = ("[YOU] " if is_player else "") + horse_name
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 48
	l.outline_size = 12
	l.pixel_size = horse_scale * 0.01
	l.position = Vector3(0.0, MODEL_HEIGHT * horse_scale * 1.3, 0.0)
	l.modulate = Color(1.0, 0.9, 0.3) if is_player else Color.WHITE
	add_child(l)


func start_race() -> void:
	if state == State.GATE:
		state = State.RACING


func use_skill() -> bool:
	if state == State.RACING and not skill_used:
		skill_used = true
		skill_left = 3.0
		return true
	return false



func tick(delta: float, race_time: float) -> void:
	match state:
		State.GATE:
			speed = 0.0
		State.RACING:
			_race_step(delta, race_time)
		State.FINISHED:
			_cooldown_step(delta)
	_update_transform(delta)
	_update_animation()


func progress() -> float:
	return clampf(distance / total_distance, 0.0, 1.0)


func preferred_lateral(inside: float) -> float:
	# what dose ANY OF THIS mean
	var f := 0.0
	match style:
		Style.FRONT_RUNNER: f = 0.95
		Style.PACE_CHASER: f = 0.55
		Style.LATE_SURGER: f = 0.15
		Style.END_CLOSER: f = -0.15
	if progress() > 0.62 and (style == Style.LATE_SURGER or style == Style.END_CLOSER):
		f = -0.5
	return inside * f * lateral_limit


func _race_step(delta: float, race_time: float) -> void:
	var target := _target_speed(race_time)
	var accel := base_speed * (0.5 + 0.9 * stat_power)
	if target > speed:
		speed = minf(target, speed + accel * delta)
	else:
		speed = maxf(target, speed - accel * 1.6 * delta)
	speed = minf(speed, speed_cap)

	var drain := pow(speed / base_speed, 2.4)
	if _rush_left > 0.0:
		drain *= 1.5
	hp -= drain * delta
	_rush_left = maxf(0.0, _rush_left - delta)
	skill_left = maxf(0.0, skill_left - delta)

	_update_lateral(delta)

	var s := start_s + distance
	distance += speed * delta / track.lane_factor(s, lateral)
	if distance >= total_distance:
		var overshoot := distance - total_distance
		finish_time = race_time - overshoot / maxf(speed, 0.001)
		state = State.FINISHED
		finished.emit(self)


func _target_speed(race_time: float) -> float:
	var p := progress()
	var top := base_speed * (1.06 + 0.12 * stat_speed + float(SPURT_BONUS[style]))
	var cruise := base_speed * (0.94 + 0.05 * stat_speed)
	
	# theres a reason im in mathematics standard 2

	var ph: Vector3 = STYLE_PHASE[style]
	var mult := ph.x
	if p >= 1.0 / 6.0:
		mult = ph.y
	if p >= 2.0 / 3.0:
		mult = ph.z
	var t := cruise * mult

	var spurt_at: float = SPURT_START[style] - 0.02 * stat_wisdom
	if p >= spurt_at:
		if not in_last_spurt:
			in_last_spurt = true
			var remaining := (1.0 - p) * total_distance
			var cost := remaining / top * pow(top / base_speed, 2.4)
			var ratio := clampf(hp / maxf(cost, 0.001), 0.0, 1.0)
			_spurt_speed = lerpf(cruise, top, ratio)
		t = maxf(t, _spurt_speed)

	if hp <= 0.0:
		t = minf(t, base_speed * (0.80 + 0.12 * stat_guts))

	if _rush_left > 0.0:
		t *= 1.04
	if skill_left > 0.0:
		t *= 1.08
	var wobble := (sin(race_time * 0.8 + _ph1) + sin(race_time * 2.1 + _ph2)) * 0.5
	return t * (1.0 + wobble * 0.012 * (1.3 - stat_wisdom))


func _update_lateral(delta: float) -> void:
	var rate := lane_move_speed * (0.7 + 0.6 * stat_wisdom)
	var old := lateral
	target_lateral = clampf(target_lateral, -lateral_limit, lateral_limit)
	lateral = move_toward(lateral, target_lateral, rate * delta)
	_lateral_vel = (lateral - old) / maxf(delta, 0.0001)


func _cooldown_step(delta: float) -> void:
	_cooldown_t += delta
	var target := base_speed * 0.45 if _cooldown_t < 1.5 else 0.0
	speed = move_toward(speed, target, base_speed * 0.7 * delta)
	_update_lateral(delta)
	distance += speed * delta / track.lane_factor(start_s + distance, lateral)



func _update_transform(delta: float) -> void:
	var s := start_s + distance
	var ground := track.position_at(s, lateral) + Vector3.UP * height_offset
	var ahead := track.position_at(s + maxf(len_world * 0.6, 0.001), lateral)
	var dir := (ahead - ground).normalized()
	var right := track.right_at(s)

	var heading := dir
	if speed > base_speed * 0.05:
		heading = (dir * speed + right * _lateral_vel).normalized()
	if _heading == Vector3.ZERO:
		_heading = heading
	else:
		_heading = _heading.slerp(heading, 1.0 - exp(-10.0 * delta)).normalized()

	var rel := speed / base_speed
	var lean_target := clampf(rel * rel * track.curvature_at(s) * track.width * bank_gain, -max_lean, max_lean)
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-6.0 * delta))
	var up := (Vector3.UP + right * tan(_lean)).normalized()

	global_transform = Transform3D(Basis.looking_at(_heading, up), ground)


func _update_animation() -> void:
	if _anim == null:
		return
	if speed > base_speed * 0.08 and _gallop_name != "":
		_play(_gallop_name)
		_anim.speed_scale = clampf(speed / (len_world * stride_length_factor), stride_hz_min, stride_hz_max) * anim_speed_mult
	elif _idle_name != "":
		_play(_idle_name)
		_anim.speed_scale = 1.0


func _play(anim_name: String) -> void:
	if anim_name == _current_anim:
		return
	var first := _current_anim == ""
	_current_anim = anim_name
	_anim.play(anim_name, 0.25)
	if first:
		_anim.seek(rng.randf() * _anim.current_animation_length, true)


func forward() -> Vector3:
	return -global_transform.basis.z
