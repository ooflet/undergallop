extends Control
## Race HUD: player's live rank, JRA-style elapsed clock, course type and distance.
## Reads everything from the RaceManager (found via the "race_manager" group,
## or assign `manager` yourself in the inspector).

@export var manager: Node

@onready var _rank: Label = $Rank
@onready var _elapsed: Label = $Elapsed
@onready var _course_type: Label = $CourseType
@onready var _course_length: Label = $CourseLength

var _bound := false
## Player's finish time; the clock freezes on it. -1 = not finished yet.
var _finish_time := -1.0


func _ready() -> void:
	_rank.visible = false
	_elapsed.text = format_elapsed(0.0)


func _process(_delta: float) -> void:
	if manager == null:
		manager = get_tree().get_first_node_in_group("race_manager")
		if manager == null:
			return
	if not _bound:
		if manager.player == null:
			return  # manager hasn't spawned the field yet
		_bind()

	var started: bool = manager.racing or _finish_time >= 0.0
	_rank.visible = started
	if started:
		_rank.text = "#%d" % manager.player.rank

	var t: float = _finish_time if _finish_time >= 0.0 else manager.race_time
	_elapsed.text = format_elapsed(t)


func _bind() -> void:
	_bound = true
	manager.player.finished.connect(_on_player_finished)
	_course_type.text = manager.course_type
	_course_length.text = "%s m" % _with_commas(manager.course_length_m)


func _on_player_finished(r) -> void:
	_finish_time = r.finish_time


## Under a minute: whole seconds (0, 1, 2 ... 59).
## From one minute on: minutes.seconds (1.00, 1.01 ... 1.59, 2.00 ...).
static func format_elapsed(t: float) -> String:
	var s := int(maxf(t, 0.0))
	if s < 60:
		return str(s)
	return "%d.%02d" % [floori(s / 60.0), s % 60]


static func _with_commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
