class_name SkillCheck
extends Control
## Timing QTE: a marker sweeps back and forth, press Space/Enter/click while it's in the green zone.
## Usage:  var c := SkillCheck.new(); layer.add_child(c); c.start(); var ok: bool = await c.finished

signal finished(success: bool)

@export var bar_size := Vector2(760, 54)
@export var zone_width := 0.20
@export var sweeps_per_second := 0.85

var _pos := 0.0
var _dir := 1.0
var _zone_start := 0.0
var _armed := false
var _done := false
var _title: Label


func start() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_zone_start = randf_range(0.30, 1.0 - zone_width - 0.05)
	_title = Label.new()
	_title.text = "SKILL CHECK!\nPress SPACE / click when the marker is in the green zone"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 34)
	add_child(_title)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.offset_top = 300
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	await get_tree().create_timer(0.35, false).timeout  # grace period so a stray click doesn't fail it
	_armed = true


func _process(delta: float) -> void:
	if _done:
		return
	if _armed:
		_pos += _dir * sweeps_per_second * delta
		if _pos >= 1.0:
			_pos = 1.0
			_dir = -1.0
		elif _pos <= 0.0:
			_pos = 0.0
			_dir = 1.0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	var o := (size - bar_size) * 0.5
	draw_rect(Rect2(o, bar_size), Color(0.15, 0.15, 0.2))
	draw_rect(Rect2(o + Vector2(bar_size.x * _zone_start, 0), Vector2(bar_size.x * zone_width, bar_size.y)), Color(0.25, 0.85, 0.4))
	draw_rect(Rect2(o + Vector2(bar_size.x * _pos - 4, -10), Vector2(8, bar_size.y + 20)), Color.WHITE)


func _input(event: InputEvent) -> void:
	if not _armed or _done:
		return
	var mb := event as InputEventMouseButton
	if event.is_action_pressed("ui_accept") or (mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()
		_resolve()


func _resolve() -> void:
	_done = true
	var ok := _pos >= _zone_start and _pos <= _zone_start + zone_width
	_title.text = "SUCCESS!" if ok else "FAILED..."
	await get_tree().create_timer(0.8, false).timeout
	finished.emit(ok)
	queue_free()
