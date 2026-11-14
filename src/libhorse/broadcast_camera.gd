extends Camera3D
## TV-broadcast style camera director. Instead of chasing one horse it frames the
## whole field and cuts between classic race-coverage shots:
##
##   Gate          pre-race: in front of the stalls, slowly drifting across the line-up
##   Aerial        high and behind the pack, looking down on the whole field
##   Side tracking beside the pack, moving with it (the "long lens" tracking shot)
##   Head-on       just ahead of the leader, low, looking back at the horses coming at you
##   Rail pan      fixed trackside camera that pans (and zooms) as the pack goes past
##   Finish line   locked off at the line for the closing stretch, zooming out as they arrive
##   Winner        slow orbit around the winner once the race is decided
##
## RaceManager creates this node (camera_mode = "Broadcast") and calls update_shot()
## every frame. It frames the *group around the leader*, so one horse that is miles
## behind does not zoom the shot out to nothing.

const Racer := preload("horse_racer.gd")
const Track := preload("track_path.gd")

signal shot_changed(shot_name: String)

enum Shot { GATE, AERIAL, SIDE_TRACK, HEAD_ON, RAIL_PAN, FINISH, WINNER }
const SHOT_NAMES := ["Gate", "Aerial", "Side tracking", "Head-on", "Rail pan", "Finish line", "Winner"]
const FREE_SHOTS := [Shot.AERIAL, Shot.SIDE_TRACK, Shot.HEAD_ON, Shot.RAIL_PAN]

# --- tuning (RaceManager copies its exports into these) --------------------------------
var shot_length_min := 4.0
var shot_length_max := 8.0
## Leader progress (0..1) at which we lock off to the finish-line camera.
var finale_progress := 0.8
## Seconds after the first horse finishes before cutting to the winner orbit.
var winner_delay := 3.0
var fov_min := 8.0
var fov_max := 70.0
## Extra room around the pack when framing (1.0 = tight).
var margin := 1.25
## Horses further than this many track-widths from the leader are ignored when framing.
var pack_radius_widths := 2.0

var shot: int = Shot.GATE
var mgr: Node
var track: Track
var rng: RandomNumberGenerator

var _started := false
var _shot_time := 0.0
var _shot_len := 5.0
var _snap := true
var _side := 1.0
var _free_count := 0
var _since_win := 0.0
var _finale := false
var _orbit := 0.0
var _fixed_pos := Vector3.ZERO
var _off := Vector3.ZERO

# pack measurements, refreshed every frame
var _leader: Racer
var _len_w := 0.4
var _c := Vector3.ZERO        # raw centre of the group
var _c_s := Vector3.ZERO      # smoothed centre (velocity-compensated, so it doesn't lag)
var _vel := Vector3.ZERO
var _f := Vector3.FORWARD     # average heading, flat
var _rgt := Vector3.RIGHT
var _e_s := 0.5               # half-extent of the group along the track (smoothed)
var _l_s := 0.5               # half-extent across the track (smoothed)
var _s_mean := 0.0            # mean track position of the group
var _have_pack := false


func _init() -> void:
	top_level = true
	near = 0.01
	far = 500.0


func setup(manager: Node, random: RandomNumberGenerator) -> void:
	mgr = manager
	track = manager.track
	rng = random


func current_shot_name() -> String:
	return SHOT_NAMES[shot]


# ====================================================================================
# director
# ====================================================================================

func update_shot(delta: float) -> void:
	if mgr == null or track == null or mgr.racers.is_empty() or not is_inside_tree():
		return
	if mgr.results.size() > 0:
		_since_win += delta
	_measure_pack(delta)

	var forced := _forced_shot()
	if forced != -1:
		if forced != shot or not _started:
			_begin_shot(forced)
	elif not _started or shot == Shot.GATE or shot == Shot.FINISH or shot == Shot.WINNER \
			or _shot_time >= _shot_len:
		if _started and _time_to_finale() < shot_length_min:
			# not enough time for another full shot: go to the line early
			_finale = true
			_begin_shot(Shot.FINISH)
		else:
			_begin_shot(_pick_free_shot())

	_shot_time += delta
	_run_shot(delta)


## Shots the story demands: gate before the off, finish line for the closing stretch,
## winner at the end. Returns -1 while the director is free to pick coverage.
func _forced_shot() -> int:
	if not mgr.racing:
		if mgr.results.is_empty():
			return Shot.GATE
		return Shot.WINNER
	if _since_win >= winner_delay:
		return Shot.WINNER
	if _finale or (_leader != null and _leader.progress() >= finale_progress):
		_finale = true
		return Shot.FINISH
	return -1


## Rough seconds until the leader reaches the finish-line-camera point.
func _time_to_finale() -> float:
	var remaining := (finale_progress - _leader.progress()) * _leader.total_distance
	return remaining / maxf(_leader.speed, 0.5)


func _pick_free_shot() -> int:
	var pick: int
	if _free_count == 0:
		pick = Shot.AERIAL        # open on the whole field breaking from the gate
	elif _free_count == 1:
		pick = Shot.SIDE_TRACK
	else:
		var options: Array = []
		for s in FREE_SHOTS:
			if s != shot:
				options.append(s)
		pick = options[rng.randi_range(0, options.size() - 1)]
	_free_count += 1
	return pick


func _begin_shot(s: int) -> void:
	_started = true
	shot = s
	_shot_time = 0.0
	_shot_len = rng.randf_range(shot_length_min, maxf(shot_length_max, shot_length_min))
	_snap = true
	_side = 1.0 if rng.randf() < 0.5 else -1.0
	_orbit = rng.randf() * TAU
	if shot == Shot.RAIL_PAN or shot == Shot.FINISH:
		_fixed_pos = _static_position()
	shot_changed.emit(SHOT_NAMES[shot])


## Trackside spot for the fixed cameras.
func _static_position() -> Vector3:
	var lw := _len_w
	var lateral := _side * (track.width * 0.5 + lw * 1.8)
	var s := _s_mean
	var height := lw * 0.9
	if shot == Shot.FINISH:
		s = _leader.start_s + _leader.total_distance      # the finish line
		lateral = _side * (track.width * 0.5 + lw * 2.4)
		height = lw * 0.8
	else:
		# place it ahead of the pack so they arrive mid-shot
		s += maxf(_vel.length() * _shot_len * 0.45, track.width * 0.8)
	return track.position_at(s, lateral) + Vector3.UP * height


# ====================================================================================
# measuring the field
# ====================================================================================

func _measure_pack(delta: float) -> void:
	var racers: Array = mgr.racers
	_leader = null
	for r in racers:
		if _leader == null or r.rank < _leader.rank:
			_leader = r
	_len_w = _leader.len_world
	var lead_pos: Vector3 = _leader.global_position
	var max_r := track.width * pack_radius_widths

	var group: Array = []
	var psum := Vector3.ZERO
	var fsum := Vector3.ZERO
	var vsum := Vector3.ZERO
	var ssum := 0.0
	for r in racers:
		if r.global_position.distance_to(lead_pos) > max_r:
			continue
		group.append(r)
		psum += r.global_position
		var fw: Vector3 = r.forward()
		vsum += fw * r.speed
		fw.y = 0.0
		fsum += fw
		ssum += r.start_s + r.distance
	var n := float(group.size())
	_c = psum / n + Vector3.UP * (_len_w * 0.4)
	_vel = vsum / n
	_s_mean = ssum / n

	if fsum.length() > 0.001:
		_f = fsum.normalized()
	else:
		_f = track.tangent_at(_s_mean)
		_f.y = 0.0
		_f = _f.normalized()
	_rgt = _f.cross(Vector3.UP).normalized()

	var e := 0.0
	var l := 0.0
	for r in group:
		var d: Vector3 = r.global_position + Vector3.UP * (_len_w * 0.4) - _c
		e = maxf(e, absf(d.dot(_f)))
		l = maxf(l, absf(d.dot(_rgt)))

	if not _have_pack:
		_have_pack = true
		_c_s = _c
		_e_s = e
		_l_s = l
	else:
		# Advance by the pack's velocity first, then correct: smooth but lag-free.
		var k := _rate(delta, 5.0)
		_c_s = (_c_s + _vel * delta).lerp(_c, k)
		_e_s = lerpf(_e_s, e, k)
		_l_s = lerpf(_l_s, l, k)


func _winner() -> Racer:
	var best: Racer = null
	for r in mgr.racers:
		if best == null or r.rank < best.rank:
			best = r
	return best


# ====================================================================================
# shots
# ====================================================================================

func _run_shot(delta: float) -> void:
	var lw := _len_w
	var tw := track.width
	var look_target := _c_s
	var target_fov := 40.0
	var pos := global_position
	var relative := true
	var off := Vector3.ZERO

	match shot:
		Shot.GATE:
			var hh := _l_s + lw * 1.2
			var hv := lw * 1.3
			var d := clampf(_fit_dist(hh, hv, 38.0), tw * 0.8, tw * 3.0)
			off = _f * d + Vector3.UP * lw * 0.55 + _rgt * sin(_shot_time * 0.35) * _l_s * 0.7
			target_fov = _fit_fov(hh, hv, off.length())
		Shot.AERIAL:
			var rad := Vector2(_e_s, _l_s).length() + lw
			var d := clampf(_fit_dist(rad, rad, 46.0), tw * 1.2, tw * 5.0)
			off = -_f * d * 0.55 + Vector3.UP * d * 0.75 + _rgt * _side * d * 0.12
			target_fov = _fit_fov(rad, rad, off.length())
		Shot.SIDE_TRACK:
			var hh := _e_s + lw * 0.9
			var hv := lw * 1.2
			var d := clampf(_fit_dist(hh, hv, 34.0), lw * 2.5, tw * 2.5)
			off = _rgt * _side * d + Vector3.UP * (lw * 0.45 + d * 0.08) + _f * _e_s * 0.15
			target_fov = _fit_fov(hh, hv, off.length())
		Shot.HEAD_ON:
			var hh := _l_s + lw
			var hv := lw * 1.2
			var d := clampf(_fit_dist(hh, hv, 38.0), tw * 0.9, tw * 3.0)
			var ahead := _e_s + d
			off = track.position_at(_s_mean + ahead) - track.position_at(_s_mean) + Vector3.UP * lw * 0.3
			target_fov = _fit_fov(hh, hv, off.length())
		Shot.RAIL_PAN, Shot.FINISH:
			relative = false
			pos = _fixed_pos
			var hh := maxf(_e_s, _l_s) + lw
			target_fov = _fit_fov(hh, lw * 1.2, (_c_s - pos).length())
		Shot.WINNER:
			relative = false
			var w := _winner()
			look_target = w.global_position + Vector3.UP * lw * 0.55
			_orbit += delta * 0.3
			pos = look_target + Vector3(cos(_orbit), 0.0, sin(_orbit)) * lw * 3.2 + Vector3.UP * lw * 0.5
			target_fov = 40.0

	if relative:
		_off = off if _snap else _off.lerp(off, _rate(delta, 2.5))
		pos = _c_s + _off

	global_position = pos
	var dir := look_target - pos
	if dir.length_squared() > 0.000001:
		var up := Vector3.UP
		if absf(dir.normalized().dot(up)) > 0.995:
			up = Vector3.FORWARD
		look_at(look_target, up)
	fov = target_fov if _snap else lerpf(fov, target_fov, _rate(delta, 3.0))
	_snap = false


# ====================================================================================
# helpers
# ====================================================================================

func _rate(delta: float, speed: float) -> float:
	return 1.0 - exp(-speed * delta)


func _aspect() -> float:
	var vp := get_viewport()
	if vp == null:
		return 16.0 / 9.0
	var size := vp.get_visible_rect().size
	return size.x / maxf(size.y, 1.0)


## Camera distance at which a box of half_h x half_v fills the frame at `fov_deg` (vertical fov).
func _fit_dist(half_h: float, half_v: float, fov_deg: float) -> float:
	var t := tan(deg_to_rad(fov_deg) * 0.5)
	return maxf(half_h / (t * _aspect()), half_v / t) * margin


## The fov that frames a half_h x half_v box from `dist` away (the "zoom lens").
func _fit_fov(half_h: float, half_v: float, dist: float) -> float:
	var need := maxf(half_h / _aspect(), half_v) * margin / maxf(dist, 0.001)
	return clampf(rad_to_deg(2.0 * atan(need)), fov_min, fov_max)
