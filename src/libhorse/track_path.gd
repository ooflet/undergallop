extends RefCounted

var points := PackedVector3Array()
var tangents := PackedVector3Array()
var rights := PackedVector3Array()
var curvature := PackedFloat32Array()

var length := 0.0
var width := 0.3
var step := 0.0
var inside_sign := 1.0

var _frac := 0.0


func load_from(path: String, xf: Transform3D = Transform3D.IDENTITY, reverse := false) -> bool:
	if not FileAccess.file_exists(path):
		push_error("TrackPath: file not found: %s" % path)
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not data.has("points"):
		push_error("TrackPath: could not parse %s" % path)
		return false
	var pts := PackedVector3Array()
	for p in data["points"]:
		pts.append(xf * Vector3(p[0], p[1], p[2]))
	if reverse:
		pts.reverse()
	_build(pts)
	width = float(data.get("width", 0.3)) * xf.basis.get_scale().x
	return true


func _build(pts: PackedVector3Array) -> void:
	points = pts
	var n := pts.size()
	length = 0.0
	for i in n:
		length += pts[i].distance_to(pts[(i + 1) % n])
	step = length / float(n)

	tangents.resize(n)
	rights.resize(n)
	curvature.resize(n)
	for i in n:
		var d := pts[(i + 1) % n] - pts[(i - 1 + n) % n]
		tangents[i] = d.normalized()
		rights[i] = tangents[i].cross(Vector3.UP).normalized()

	var total := 0.0
	for i in n:
		var dt := tangents[(i + 1) % n] - tangents[(i - 1 + n) % n]
		var k := (dt / (2.0 * step)).dot(rights[i])
		curvature[i] = k
		total += k
	inside_sign = 1.0 if total >= 0.0 else -1.0



func _locate(s: float) -> Vector3i:
	var f := fposmod(s, length) / step
	var i0 := int(f) % points.size()
	_frac = f - floorf(f)
	return Vector3i(i0, (i0 + 1) % points.size(), 0)


func position_at(s: float, lateral := 0.0) -> Vector3:
	var ix := _locate(s)
	var c := points[ix.x].lerp(points[ix.y], _frac)
	if lateral == 0.0:
		return c
	var r := rights[ix.x].lerp(rights[ix.y], _frac).normalized()
	return c + r * lateral


func tangent_at(s: float) -> Vector3:
	var ix := _locate(s)
	return tangents[ix.x].lerp(tangents[ix.y], _frac).normalized()


func right_at(s: float) -> Vector3:
	var ix := _locate(s)
	return rights[ix.x].lerp(rights[ix.y], _frac).normalized()


func curvature_at(s: float) -> float:
	var ix := _locate(s)
	return lerpf(curvature[ix.x], curvature[ix.y], _frac)


func lane_factor(s: float, lateral: float) -> float:
	return maxf(0.25, 1.0 - lateral * curvature_at(s))
