class_name TrainingUI
extends Control

signal command_chosen(command: String)

const MOOD_COLORS := {
	-2: Color(0.6, 0.6, 0.85), -1: Color(0.8, 0.72, 0.6), 0: Color.WHITE,
	1: Color(0.7, 0.95, 0.7), 2: Color(1.0, 0.85, 0.3),
}

var _header: Label
var _mood_label: Label
var _extras_label: Label
var _bars := {}
var _vals := {}
var _buttons := {}
var _rest_button: Button
var _toast: Label
var _toast_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	GameState.stats_changed.connect(refresh)
	GameState.mood_changed.connect(refresh)
	GameState.flowers_changed.connect(refresh)
	refresh()


func set_turn_info(stage_name: String, turn: int, turns: int) -> void:
	_header.text = "%s  -  Turn %d / %d" % [stage_name, turn, turns]


func await_command() -> String:
	_set_buttons_enabled(true)
	var cmd: String = await command_chosen
	_set_buttons_enabled(false)
	return cmd


func toast(text: String, duration: float = 1.2) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func refresh() -> void:
	if _mood_label == null:
		return
	_mood_label.text = "Mood: %s" % GameState.mood_label()
	_mood_label.add_theme_color_override("font_color", MOOD_COLORS[GameState.mood])
	var mult := GameState.train_multiplier()
	_extras_label.text = "Flowers: %d     Training x%.2f" % [GameState.flowers, mult]
	for s in GameState.STATS:
		var v: float = GameState.stats[s]
		(_bars[s] as ProgressBar).value = v
		(_vals[s] as Label).text = str(roundi(v))
		var side: String = GameState.SECONDARY[s]
		(_buttons[s] as Button).text = "%s  +%d   (%s +%d)" % [
			GameState.STAT_LABELS[s], roundi(GameState.BASE_GAIN * mult),
			GameState.STAT_LABELS[side], roundi(GameState.SECONDARY_GAIN * mult)]


func _set_buttons_enabled(on: bool) -> void:
	for b in _buttons.values():
		(b as Button).disabled = not on
	_rest_button.disabled = not on


func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(50, 50)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_header = _label(box, 34)
	_mood_label = _label(box, 30)
	_extras_label = _label(box, 24)
	for s in GameState.STATS:
		var row := HBoxContainer.new()
		var n := Label.new()
		n.text = GameState.STAT_LABELS[s]
		n.custom_minimum_size.x = 130
		n.add_theme_font_size_override("font_size", 28)
		var bar := ProgressBar.new()
		bar.max_value = 200
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(320, 26)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var v := Label.new()
		v.custom_minimum_size.x = 64
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.add_theme_font_size_override("font_size", 28)
		row.add_child(n)
		row.add_child(bar)
		row.add_child(v)
		box.add_child(row)
		_bars[s] = bar
		_vals[s] = v

	var cmds := VBoxContainer.new()
	cmds.add_theme_constant_override("separation", 12)
	cmds.custom_minimum_size = Vector2(430, 0)
	add_child(cmds)
	cmds.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	cmds.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cmds.grow_vertical = Control.GROW_DIRECTION_BOTH
	cmds.offset_right = -50
	for s in GameState.STATS:
		var b := _command_button("", s)
		cmds.add_child(b)
		_buttons[s] = b
	_rest_button = _command_button("Rest   (Mood +1)", "rest")
	cmds.add_child(_rest_button)

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 40)
	_toast.modulate.a = 0.0
	add_child(_toast)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 90
	_set_buttons_enabled(false)


func _label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _command_button(text: String, cmd: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(func(): command_chosen.emit(cmd))
	return b
