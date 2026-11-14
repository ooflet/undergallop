# please KILL ME ITS 4 IN THE MORNING and im working on THIS BULLSHIT

class_name VNGui
extends Control

signal pause_pressed
signal _advance
signal _choice_made(index: int)
signal _text_done(value: String)

const NARRATION_COLOR := Color(0.78, 0.82, 0.92)
const MAX_BLUSH := 3

@export var talk_sfx: AudioStream
@export var talk_volume_db := 0
@export var talk_every := 2
@export var talk_pitch_min := 0.9
@export var talk_pitch_max := 1.1

var _talk_player: AudioStreamPlayer

@export var ellipsis_pause := 0.25
@export var dash_pause := 0.25
@export var stutter_pause := 0.25

@export var chars_per_second := 45.0
@export var gag_wait_scale := 1.0
@export var portrait_dir := "res://assets/characters"
@export var marquee_speed := 60.0
@export var option_rise := 60.0
@export var option_time := 0.35
@export var option_stagger := 0.12

@onready var name_label: Label = $Name
@onready var dialogue: Label = $Dialogue
@onready var next_icon: TextureRect = $Next
@onready var pause_button: TextureButton = $Pause
@onready var marquee: Label = $Marquee
@onready var option_buttons: Control = $OptionButtons
@onready var option_box: BoxContainer = $OptionButtons/BoxContainer
@onready var name_picker: Control = $NamePicker
@onready var name_prompt: Label = $NamePicker/Label
@onready var name_edit: LineEdit = $NamePicker/LineEdit
@onready var name_ok: Button = $NamePicker/Button

var blush := 0
var _char_id := ""
var _expression := "neutral"
var _typing := false
var _skip_typing := false
var _waiting := false

@onready var _portrait: Control = $Portrait
var _option_slots: Array[Button] = []
var _image_layer: ColorRect
var _image_tex: TextureRect
var _image_label: Label
var _portrait_home: Vector2


func _ready() -> void:
	next_icon.hide()
	pause_button.pressed.connect(func(): pause_pressed.emit())
	_build_extras()
	_portrait_home = _portrait.position
	option_buttons.hide()
	name_picker.hide()
	for c in option_box.get_children():
		if c is Button:
			_option_slots.append(c)
	name_edit.text_submitted.connect(func(t: String): _text_done.emit(t))
	name_ok.pressed.connect(func(): _text_done.emit(name_edit.text))
	await get_tree().process_frame
	_start_marquee()
	var y := next_icon.position.y
	var t := create_tween().set_loops()
	t.tween_property(next_icon, "position:y", y + 8.0, 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(next_icon, "position:y", y, 0.5).set_trans(Tween.TRANS_SINE)
	_talk_player = AudioStreamPlayer.new()
	_talk_player.volume_db = talk_volume_db
	add_child(_talk_player)
	if talk_sfx == null and ResourceLoader.exists("res://audio/horse.ogg"):
		talk_sfx = load("res://audio/horse.ogg")
	_talk_player.stream = talk_sfx

func _play_talk() -> void:
	if _talk_player.stream == null:
		return
	_talk_player.pitch_scale = randf_range(talk_pitch_min, talk_pitch_max)
	_talk_player.play()

func _pause_for(text: String, idx: int) -> float:
	var ch := text[idx]
	var prev := text[idx - 1] if idx > 0 else ""
	var next := text[idx + 1] if idx + 1 < text.length() else ""
	match ch:
		"…":
			return ellipsis_pause * 3.0
		".":
			if prev == "." or next == ".":
				return ellipsis_pause
		"—", "–":
			return dash_pause
		"-":
			if prev == "-" or next == "-" or (prev == " " and next == " "):
				return dash_pause * 0.5
			if prev != "" and next != "" and prev.to_lower() == next.to_lower() and prev.to_lower() != prev.to_upper():
				return stutter_pause
	return 0.0

func say(speaker: String, text: String, opts: Dictionary = {}) -> void:
	_set_speaker(speaker)
	dialogue.text = text
	dialogue.visible_characters = 0
	next_icon.hide()
	_typing = true
	_skip_typing = false
	var i := 0
	var total := text.length()
	while i < total and not _skip_typing:
		i += 1
		dialogue.visible_characters = i
		var ch := text[i - 1]
		var pause := _pause_for(text, i - 1)
		if speaker != "" and pause == 0.0 and i % talk_every == 0 and ch != " ":
			_play_talk()
		await _wait(1.0 / chars_per_second + pause)
	dialogue.visible_characters = -1
	_typing = false

	var lock: float = float(opts.get("lock", 0.0)) * gag_wait_scale
	if lock > 0.0:
		await _wait(lock)
	var auto: float = float(opts.get("auto", 0.0))
	if auto > 0.0:
		await _wait(auto)
		return
	next_icon.show()
	_waiting = true
	await _advance
	_waiting = false
	next_icon.hide()


func wait_dots(seconds: float, speaker: String = "") -> void:
	_set_speaker(speaker)
	next_icon.hide()
	dialogue.visible_characters = -1
	dialogue.text = ""
	var total := seconds * gag_wait_scale
	var elapsed := 0.0
	while elapsed < total:
		await _wait(0.5)
		elapsed += 0.5
		dialogue.text += ".  "


func choose(options: Array) -> int:
	next_icon.hide()
	var buttons: Array[Button] = []
	var extras: Array[Button] = []
	for i in maxi(options.size(), _option_slots.size()):
		var b: Button
		if i < _option_slots.size():
			b = _option_slots[i]
		else:
			b = _option_slots.back().duplicate(0) as Button
			option_box.add_child(b)
			extras.append(b)
		if i < options.size():
			b.text = str(options[i])
			b.modulate.a = 0.0
			b.show()
			buttons.append(b)
		else:
			b.hide()

	var conns: Array[Callable] = []
	for i in buttons.size():
		var cb := func(): _choice_made.emit(i)
		buttons[i].pressed.connect(cb)
		conns.append(cb)

	option_buttons.show()
	await get_tree().process_frame
	await get_tree().process_frame

	var tween := create_tween().set_parallel(true)
	for i in buttons.size():
		var b := buttons[i]
		var end_y := b.position.y
		var delay := i * option_stagger
		b.position.y = end_y + option_rise
		tween.tween_property(b, "position:y", end_y, option_time) \
			.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(b, "modulate:a", 1.0, option_time * 0.6).set_delay(delay)
	buttons[0].grab_focus()

	var picked: int = await _choice_made
	tween.kill()
	for i in buttons.size():
		buttons[i].pressed.disconnect(conns[i])
	for b in extras:
		b.hide()
		b.queue_free()
	option_buttons.hide()
	return picked


func ask_text(prompt: String, default_text: String = "") -> String:
	name_prompt.text = prompt
	name_edit.text = default_text
	name_edit.max_length = 16
	name_picker.show()
	name_edit.grab_focus()
	name_edit.select_all()
	var result: String = await _text_done
	name_picker.hide()
	return result


func show_results(title: String, rows: Array, highlight: int = -1) -> void:
	var panel := PanelContainer.new()
	panel.theme = name_label.theme
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.88)
	sb.set_content_margin_all(28)
	sb.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 40)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	for i in rows.size():
		var l := Label.new()
		l.text = str(rows[i])
		l.add_theme_font_size_override("font_size", 30)
		if i == highlight:
			l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		box.add_child(l)
	panel.add_child(box)
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(panel)
	next_icon.show()
	_waiting = true
	await _advance
	_waiting = false
	next_icon.hide()
	holder.queue_free()


const CHEEK_POSITIONS := [Vector2(0.175, 0.175), Vector2(0.35, 0.175)]
const CHEEK_SIZE := Vector2(90, 60)
const BLUSH_COLOR := Color(1.0, 0.3, 0.4)


func _make_cheek_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(BLUSH_COLOR, 0.85))
	g.set_color(1, Color(BLUSH_COLOR, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

func show_image(path: String) -> void:
	if path == "slimey":
		$slimey.visible = true
		return
	_image_tex.texture = load(path) if ResourceLoader.exists(path) else null
	_image_label.text = "" if _image_tex.texture else "(missing image)\n" + path
	_image_layer.show()


func hide_image() -> void:
	_image_layer.hide()


func play_sfx(path: String, volume_db: float = 0.0) -> void:
	if not ResourceLoader.exists(path):
		push_warning("Missing sfx: " + path)
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = volume_db
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()

func play_bgm(song: String) -> void:
	$BGM.play()

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_on_advance_input()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_accept"):
		_on_advance_input()
		get_viewport().set_input_as_handled()


func _on_advance_input() -> void:
	if _typing:
		_skip_typing = true
	elif _waiting:
		_advance.emit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false).timeout


func _set_speaker(display: String) -> void:
	name_label.visible = display != ""
	name_label.text = display
	if display == "":
		dialogue.add_theme_color_override("font_color", NARRATION_COLOR)
	else:
		dialogue.remove_theme_color_override("font_color")


func _start_marquee() -> void:
	var unit := marquee.text
	if unit.strip_edges() == "":
		return
	var font := marquee.get_theme_font("font")
	var font_size := marquee.get_theme_font_size("font_size")
	var unit_w := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if unit_w <= 0.0:
		return
	marquee.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	marquee.grow_horizontal = Control.GROW_DIRECTION_END
	marquee.text = unit.repeat(ceili(get_viewport_rect().size.x / unit_w) + 1)
	marquee.reset_size()
	await get_tree().process_frame
	marquee.position.x = 0.0
	var t := create_tween().set_loops()
	t.tween_property(marquee, "position:x", -unit_w, unit_w / marquee_speed).from(0.0)

func _apply_blush(animate: bool) -> void:
	var target_alpha := blush / float(MAX_BLUSH)
	if _blush_tween:
		_blush_tween.kill()
	if not animate:
		_blush_layer.modulate.a = target_alpha
		return
	_blush_tween = create_tween()
	_blush_tween.tween_property(_blush_layer, "modulate:a", target_alpha, 0.4)

func _stop_fx() -> void:
	if _fx_tween:
		_fx_tween.kill()
		_fx_tween = null
	_portrait.scale = Vector2.ONE
	_portrait.rotation = 0.0
	_portrait.position = _portrait_home


func _play_fx() -> void:
	_stop_fx()
	_portrait.pivot_offset = Vector2(_portrait.size.x * 0.5, _portrait.size.y)
	match _expression:
		"crying", "sad":
			_fx_tween = create_tween().set_loops()
			_fx_tween.tween_property(_portrait, "scale", Vector2(1.04, 0.93), 0.45).set_trans(Tween.TRANS_SINE)
			_fx_tween.tween_property(_portrait, "scale", Vector2(0.98, 1.02), 0.45).set_trans(Tween.TRANS_SINE)
		"happy":
			_fx_tween = create_tween().set_loops()
			_fx_tween.tween_property(_portrait, "position:y", _portrait_home.y - 18.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_fx_tween.tween_property(_portrait, "position:y", _portrait_home.y, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_fx_tween.tween_interval(0.5)
		"angry":
			_fx_tween = create_tween().set_loops()
			_fx_tween.tween_property(_portrait, "position:x", 6.0, 0.04)
			_fx_tween.tween_property(_portrait, "position:x", -6.0, 0.04)
		"scared":
			_fx_tween = create_tween().set_loops()
			_fx_tween.tween_property(_portrait, "rotation_degrees", 1.5, 0.05)
			_fx_tween.tween_property(_portrait, "rotation_degrees", -1.5, 0.05)
		"embarrassed", "flustered":
			_fx_tween = create_tween().set_loops()
			_fx_tween.tween_property(_portrait, "rotation_degrees", 3.0, 0.3).set_trans(Tween.TRANS_SINE)
			_fx_tween.tween_property(_portrait, "rotation_degrees", -3.0, 0.6).set_trans(Tween.TRANS_SINE)
			_fx_tween.tween_property(_portrait, "rotation_degrees", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
		_:
			_fx_tween = create_tween().set_loops()
			_fx_tween.tween_property(_portrait, "scale", Vector2(1.0, 1.015), 1.4).set_trans(Tween.TRANS_SINE)
			_fx_tween.tween_property(_portrait, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_SINE)

func show_portrait(id: String = "", expression: String = "neutral") -> void:
	_char_id = id
	_expression = expression
	_portrait.show()
	_apply_blush(false)
	_play_fx()

func hide_portrait() -> void:
	_stop_fx()
	_portrait.hide()


func set_expression(expression: String) -> void:
	if expression == _expression:
		return
	_expression = expression
	_play_fx()


func set_blush(level: int) -> void:
	blush = clampi(level, 0, MAX_BLUSH)
	_apply_blush(true)


func add_blush(delta: int) -> void:
	set_blush(blush + delta)


func _load_portrait_texture() -> void:
	var tex: Texture2D = null
	for p in ["%s/%s.png" % [portrait_dir, _char_id], "%s/%s/neutral.png" % [portrait_dir, _char_id]]:
		if ResourceLoader.exists(p):
			tex = load(p)
			break

var _blush_layer: Control
var _fx_tween: Tween
var _blush_tween: Tween

func _build_extras() -> void:
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.hide()

	_blush_layer = Control.new()
	_blush_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blush_layer.modulate.a = 0.0
	_portrait.add_child(_blush_layer)
	_blush_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cheek_tex := _make_cheek_texture()
	for pos in CHEEK_POSITIONS:
		var c := TextureRect.new()
		c.texture = cheek_tex
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_blush_layer.add_child(c)
		c.anchor_left = pos.x
		c.anchor_right = pos.x
		c.anchor_top = pos.y
		c.anchor_bottom = pos.y
		c.offset_left = -CHEEK_SIZE.x * 0.5
		c.offset_right = CHEEK_SIZE.x * 0.5
		c.offset_top = -CHEEK_SIZE.y * 0.5
		c.offset_bottom = CHEEK_SIZE.y * 0.5

	_image_layer = ColorRect.new()
	_image_layer.color = Color.BLACK
	_image_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_layer.hide()
	add_child(_image_layer)
	_image_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image_tex = TextureRect.new()
	_image_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_layer.add_child(_image_tex)
	_image_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image_label = Label.new()
	_image_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_image_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_image_label.add_theme_font_size_override("font_size", 40)
	_image_layer.add_child(_image_label)
	_image_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
