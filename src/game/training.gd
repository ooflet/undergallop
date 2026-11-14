class_name Training
extends Node
## Runs the turn loop: pick a command -> (maybe) a random event plays as a VN scene -> stats change.
## Events live in data/events.json, so writers can add/edit them without touching code.

const REST_MOOD := 1

var gui: VNGui
var runner: StoryRunner
var ui: TrainingUI
var qte_layer: Node

var event_chance := 0.4
var events: Array = []


func load_events(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Can't open events file: " + path)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("events.json is not valid JSON")
		return false
	event_chance = float(parsed.get("event_chance", 0.4))
	events = parsed.get("events", [])
	return true


## Runs turns until the stage's turn count is reached. Returns "done" or "dead".
func run_until_race(stage: Dictionary) -> String:
	var turns: int = int(stage["turns"])
	while GameState.turn < turns:
		ui.set_turn_info(str(stage["name"]), GameState.turn + 1, turns)
		ui.refresh()
		var cmd: String = await ui.await_command()
		GameState.session_pct = 0
		if cmd == "rest":
			GameState.add_mood(REST_MOOD)
			ui.toast("2steedy rests.  Mood: %s" % GameState.mood_label())
			await get_tree().create_timer(1.2, false).timeout
		else:
			await _do_training(cmd)
			if GameState.dead:
				return "dead"
		GameState.turn += 1
	return "done"


func _do_training(stat: String) -> void:
	if not events.is_empty() and randf() < event_chance:
		await _play_event()
		if GameState.dead:
			return
	var mult := GameState.train_multiplier()
	var side: String = GameState.SECONDARY[stat]
	var main_gain := GameState.BASE_GAIN * mult
	var side_gain := GameState.SECONDARY_GAIN * mult
	GameState.add_stat(stat, main_gain)
	GameState.add_stat(side, side_gain)
	ui.toast("%s +%d    %s +%d" % [GameState.STAT_LABELS[stat], roundi(main_gain), GameState.STAT_LABELS[side], roundi(side_gain)], 1.4)
	await get_tree().create_timer(1.6, false).timeout


func _pick_event() -> Dictionary:
	var total := 0.0
	for e in events:
		total += float(e.get("weight", 1.0))
	var roll := randf() * total
	for e in events:
		roll -= float(e.get("weight", 1.0))
		if roll <= 0.0:
			return e
	return events.back()


## One event = lines -> effects -> optional bounce_back (lines -> effects).
## An event with a "qte" block sometimes swaps to its skill-check variant:
## prompt -> skill check -> pass_lines (base effects) or fail_lines (fail_effects).
func _play_event() -> void:
	var ev := _pick_event()
	ui.hide()
	gui.show()
	gui.show_portrait("2steedy", "neutral")

	var fx: Dictionary = ev.get("effects", {})
	var qte: Dictionary = ev.get("qte", {})
	if not qte.is_empty() and randf() < float(qte.get("chance", 0.4)):
		await runner.run_commands(qte.get("prompt", []))
		var ok: bool = await _run_qte()
		if ok:
			await runner.run_commands(qte.get("pass_lines", []))
		else:
			await runner.run_commands(qte.get("fail_lines", []))
			fx = qte.get("fail_effects", {})
	else:
		await runner.run_commands(ev.get("lines", []))
	await _apply(fx)

	var bounce: Dictionary = ev.get("bounce_back", {})
	if not bounce.is_empty() and not GameState.dead:
		await runner.run_commands(bounce.get("lines", []))
		await _apply(bounce.get("effects", {}))

	gui.hide_portrait()
	gui.hide()
	ui.show()
	ui.refresh()


func _apply(fx: Dictionary) -> void:
	if fx.is_empty():
		return
	var notes: Array = GameState.apply_effects(fx)
	if notes.is_empty():
		return
	await gui.say("", "[ " + "  |  ".join(PackedStringArray(notes)) + " ]", {"auto": 1.8})


func _run_qte() -> bool:
	var check := SkillCheck.new()
	qte_layer.add_child(check)
	check.start()
	var ok: bool = await check.finished
	return ok
