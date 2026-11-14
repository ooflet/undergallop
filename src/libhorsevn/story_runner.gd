class_name StoryRunner
extends Node

var gui: VNGui
var data: Dictionary = {}
var hooks: Dictionary = {}

var _abort := false
var _jump := ""

# load a story no wayyy
func load_story(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Can't open story file: " + path)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Story file is not valid JSON: " + path)
		return false
	data = parsed
	return true

func play(scene_id: String) -> void:
	var scenes: Dictionary = data.get("scenes", {})
	if not scenes.has(scene_id):
		# i did a fuckup
		push_error("Unknown scene: " + scene_id)
		return
	_abort = false
	_jump = ""
	await run_commands(scenes[scene_id])
	_abort = false
	gui.set_blush(0)
	if _jump != "":
		var next := _jump
		_jump = ""
		await play(next)


func run_commands(cmds: Array) -> void:
	#idk why this is here
	for c in cmds:
		if _abort:
			return
		await _run(c)


func _run(c: Dictionary) -> void:
	match str(c.get("t", "")):
		"say":
			_visuals(c)
			await gui.say(_display_name(str(c.get("who", ""))), _fmt(str(c.get("text", ""))), c)
		"narrate":
			_visuals(c)
			await gui.say("", _fmt(str(c.get("text", ""))), c)
		"show":
			gui.show_portrait(str(c.get("who", "")), str(c.get("face", "neutral")))
			_visuals(c)
		"hide":
			gui.hide_portrait()
		"face", "blush":
			_visuals(c)
		"choice":
			var opts: Array = c.get("options", [])
			var labels: Array = []
			for o in opts:
				labels.append(_fmt(str(o.get("text", ""))))
			var picked: int = await gui.choose(labels)
			await run_commands(opts[picked].get("do", []))
		"wait":
			await gui.wait_dots(float(c.get("seconds", 10.0)), _display_name(str(c.get("who", ""))))
		"sfx":
			gui.play_sfx(str(c.get("file", "")), float(c.get("vol", 0.0)))
		"bgm":
			gui.play_bgm(str(c.get("song", "")))
		"image":
			gui.show_image(str(c.get("file", "")))
		"image_hide":
			gui.hide_image()
		"ask_name":
			var n: String = await gui.ask_text(str(c.get("prompt", "What's your name, trainer?")), GameState.player_name)
			if n.strip_edges() != "":
				GameState.player_name = n.strip_edges()
		"results":
			await gui.show_results(str(c.get("title", "Results")), c.get("rows", []), int(c.get("highlight", -1)))
		"set_flag":
			GameState.flags[str(c.get("key", ""))] = c.get("value", true)
		"call":
			var h: Variant = hooks.get(str(c.get("name", "")))
			if h is Callable:
				await (h as Callable).call(c.get("args", []))
			else:
				# someone else did a fuckup lol
				push_warning("No hook named '%s'" % str(c.get("name", "")))
		"goto":
			_jump = str(c.get("scene", ""))
			_abort = true
		"end":
			_abort = true
		"comment":
			pass
		_:
			push_warning("Unknown story command: " + JSON.stringify(c))


func _visuals(c: Dictionary) -> void:
	if c.has("face"):
		gui.set_expression(str(c["face"]))
	if c.has("blush"):
		gui.set_blush(int(c["blush"]))
	if c.has("blush_add"):
		gui.add_blush(int(c["blush_add"]))


func _display_name(who: String) -> String:
	if who == "":
		return ""
	var chars: Dictionary = data.get("characters", {})
	if chars.has(who):
		return str(chars[who].get("name", who))
	return who


func _fmt(text: String) -> String:
	return text.replace("{player}", GameState.player_name)
