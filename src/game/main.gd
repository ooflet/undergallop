# welcome to hrse brother

extends Node

const STAGES := [
	{"name": "Semi-Demi Finals", "turns": 12, "rating_scale": 1.0, "pass_top": 3},
]
const RESULT_SCENES := {1: "race_1st", 2: "race_2nd", 3: "race_3rd"}

@export var debug_skip_gags := false
@export var fake_crash_really_quits := true

var gui: VNGui
var ui: TrainingUI
var runner: StoryRunner
var training: Training
var _pause_panel: PanelContainer


func _ready() -> void:
	GameState.reset_run()

	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.1)
	bg_layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	ui = TrainingUI.new()
	ui_layer.add_child(ui)
	ui.hide()

	var vn_layer := CanvasLayer.new()
	vn_layer.layer = 10
	add_child(vn_layer)
	gui = (load("res://scenes/vn_gui.tscn") as PackedScene).instantiate() as VNGui
	gui.gag_wait_scale = 0.0 if debug_skip_gags else 1.0
	vn_layer.add_child(gui)
	ui.theme = gui.name_label.theme

	var qte_layer := CanvasLayer.new()
	qte_layer.layer = 20
	add_child(qte_layer)

	runner = StoryRunner.new()
	runner.gui = gui
	runner.hooks = {"fake_crash": _fake_crash}
	add_child(runner)
	runner.load_story("res://data/story.json")

	training = Training.new()
	training.gui = gui
	training.runner = runner
	training.ui = ui
	training.qte_layer = qte_layer
	add_child(training)
	training.load_events("res://data/events.json")

	_build_pause_menu()
	gui.pause_pressed.connect(_toggle_pause)

	await get_tree().process_frame
	_run_game()


func _run_game() -> void:
	await runner.play("intro")
	gui.hide_portrait()
	for stage in STAGES:
		await _run_stage(stage)
	gui.show()
	await runner.play("to_be_continued")


func _run_stage(stage: Dictionary) -> void:
	GameState.turn = 0
	GameState.save_checkpoint()
	var race_only := false
	while true:
		if not race_only:
			gui.hide()
			ui.show()
			var outcome: String = await training.run_until_race(stage)
			if outcome == "dead":
				await _handle_death()
				continue
		race_only = false

		ui.hide()
		gui.show()
		if await _run_race(stage):
			return
		await runner.play("race_fail")
		if GameState.flowers > 0:
			GameState.flowers -= 1
			await runner.play("race_flower_retry")
			race_only = true
		else:
			GameState.load_checkpoint()
			await runner.play("race_checkpoint_retry")


func _run_race(stage: Dictionary) -> bool:
	await gui.say("", "The %s begin..." % str(stage["name"]), {"auto": 1.5})
	var rows := Race.run(GameState.race_score(), float(stage["rating_scale"]))
	var place := Race.placement(rows)
	var lines: Array = []
	for i in rows.size():
		lines.append("%d.   %s" % [i + 1, rows[i]["name"]])
	await gui.show_results(str(stage["name"]), lines, place - 1)
	if place <= int(stage["pass_top"]):
		gui.show_portrait("2steedy", "neutral")
		await runner.play(RESULT_SCENES[place])
		gui.hide_portrait()
		return true
	return false


func _handle_death() -> void:
	ui.hide()
	gui.show()
	gui.show_portrait("2steedy", "dead")
	await runner.play("dead")
	if GameState.flowers > 0:
		GameState.flowers -= 1
		GameState.dead = false
		GameState.set_mood(GameState.MOOD_MIN)
		await runner.play("revive_flower")
	else:
		GameState.load_checkpoint()
		await runner.play("revive_checkpoint")
	gui.hide_portrait()

func _fake_crash(_args: Variant) -> void:
	gui.show_image("slimey")
	gui.play_sfx("res://audio/scream.ogg", 4.0)
	await get_tree().create_timer(1.2, false).timeout
	if fake_crash_really_quits:
		get_tree().quit()
	else:
		get_tree().reload_current_scene()


func _build_pause_menu() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_pause_panel = PanelContainer.new()
	_pause_panel.theme = gui.name_label.theme
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(_toggle_pause)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	for b in [resume, quit]:
		b.custom_minimum_size = Vector2(320, 64)
		b.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	box.add_child(resume)
	box.add_child(quit)
	_pause_panel.add_child(box)
	layer.add_child(_pause_panel)
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause_panel.hide()


func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	_pause_panel.visible = get_tree().paused
