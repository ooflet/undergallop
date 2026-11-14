extends Node
## AUTOLOAD this as "GameState"  (Project > Project Settings > Globals > Autoload).
## Holds everything that makes a "run" what it is: stats, mood, flowers, checkpoint.

signal stats_changed
signal mood_changed
signal flowers_changed

const STATS := ["speed", "stamina", "power", "guts", "wit"]
const STAT_LABELS := {"speed": "Speed", "stamina": "Stamina", "power": "Power", "guts": "Guts", "wit": "Wit"}
const START_STATS := {"speed": 18.0, "stamina": 18.0, "power": 18.0, "guts": 14.0, "wit": 14.0}

## Training a stat also gives a smaller bonus to a second one.
const SECONDARY := {"speed": "power", "stamina": "guts", "power": "stamina", "guts": "power", "wit": "speed"}
const BASE_GAIN := 12.0
const SECONDARY_GAIN := 4.0

## How much each stat counts in a race. (Tuned so a good run reaches top 3 ~65% of the time.)
const RACE_WEIGHTS := {"speed": 1.0, "stamina": 0.9, "power": 0.9, "guts": 0.8, "wit": 0.7}

const MOOD_MIN := -2
const MOOD_MAX := 2
const MOOD_LABELS := {-2: "2tired", -1: "2meh", 0: "2chill", 1: "2good", 2: "2happy"}  # rename freely
const MOOD_TRAIN_PCT := 10   # each mood level = +/-10% training gains, +/-3% race power

var player_name := "Trainer"
var stats: Dictionary = {}
var mood := 0
var dead := false             # "2dead"
var flowers := 0              # extra lives
var turn := 0
var session_pct := 0          # % modifier on the training session currently being resolved
var flags: Dictionary = {}
var checkpoint: Dictionary = {}


func reset_run() -> void:
	stats = START_STATS.duplicate()
	mood = 0
	dead = false
	flowers = 0
	turn = 0
	session_pct = 0
	flags = {}
	checkpoint = {}
	stats_changed.emit()
	mood_changed.emit()
	flowers_changed.emit()


func mood_label() -> String:
	return str(MOOD_LABELS[mood])


func set_mood(value: int) -> void:
	mood = clampi(value, MOOD_MIN, MOOD_MAX)
	mood_changed.emit()


func add_mood(delta: int) -> void:
	set_mood(mood + delta)


func add_stat(stat: String, amount: float) -> void:
	stats[stat] = float(stats[stat]) + amount
	stats_changed.emit()


func train_multiplier() -> float:
	return maxf(0.0, 1.0 + mood * MOOD_TRAIN_PCT / 100.0 + session_pct / 100.0)


func race_score() -> float:
	var total := 0.0
	for s in STATS:
		total += float(stats[s]) * float(RACE_WEIGHTS[s])
	return total * (1.0 + 0.03 * mood)


# ---------------------------------------------------------------- checkpoints
func snapshot() -> Dictionary:
	return {"stats": stats.duplicate(), "mood": mood, "flowers": flowers, "turn": turn, "flags": flags.duplicate(true)}


func save_checkpoint() -> void:
	checkpoint = snapshot()


func load_checkpoint() -> bool:
	if checkpoint.is_empty():
		return false
	stats = checkpoint["stats"].duplicate()
	mood = int(checkpoint["mood"])
	flowers = int(checkpoint["flowers"])
	turn = int(checkpoint["turn"])
	flags = checkpoint["flags"].duplicate(true)
	dead = false
	session_pct = 0
	stats_changed.emit()
	mood_changed.emit()
	flowers_changed.emit()
	return true


# ---------------------------------------------------------------- event effects
## Applies an "effects" block from events.json. Returns short text notes for the player.
## Keys: train_pct (add) | train_pct_set | mood (delta) | mood_set | tired_or_dead |
##       stat_pct (all stats +%) | flowers (+n) | checkpoint (true)
func apply_effects(fx: Dictionary) -> Array:
	var notes: Array = []
	if fx.has("train_pct_set"):
		session_pct = int(fx["train_pct_set"])
		notes.append("Training progress now %+d%%" % session_pct)
	if fx.has("train_pct"):
		session_pct += int(fx["train_pct"])
		notes.append("Training progress %+d%%" % int(fx["train_pct"]))
	if fx.has("mood_set"):
		set_mood(int(fx["mood_set"]))
		notes.append("Mood: %s" % mood_label())
	if fx.has("mood"):
		add_mood(int(fx["mood"]))
		notes.append("Mood %+d" % int(fx["mood"]))
	if fx.get("tired_or_dead", false):
		if mood <= MOOD_MIN:
			dead = true
			notes.append("2dead")
		else:
			set_mood(MOOD_MIN)
			notes.append("Mood: %s" % mood_label())
	if fx.has("stat_pct"):
		var p: float = float(fx["stat_pct"]) / 100.0
		for s in STATS:
			stats[s] = float(stats[s]) * (1.0 + p)
		stats_changed.emit()
		notes.append("All stats %+d%%" % int(fx["stat_pct"]))
	if fx.has("flowers"):
		flowers += int(fx["flowers"])
		flowers_changed.emit()
		notes.append("Flowers %+d" % int(fx["flowers"]))
	if fx.get("checkpoint", false):
		save_checkpoint()
		notes.append("Checkpoint saved")
	return notes
