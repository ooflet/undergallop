

@tool
class_name Sky3D
extends WorldEnvironment

signal environment_changed

const SKY_SHADER: String = "res://addons/sky_3d/shaders/SkyMaterial.gdshader"

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var version: String = "2.1"

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var tod: TimeOfDay
var sky: SkyDome
var sky_material: ShaderMaterial

@export var sky3d_enabled: bool = true :
	set(value):
		sky3d_enabled = value
		if value:
			show_sky()
			resume()
		else:
			hide_sky()
			pause()



@export_group("Visibility")


@export var sky_enabled: bool = true :
	set(value):
		sky_enabled = value
		if sky and sky_material:
			sky_material.set_shader_parameter("sky_visible", value)
			sky.cumulus_visible = clouds_enabled and value
			sky.cirrus_visible = clouds_enabled and value


@export var clouds_enabled: bool = true :
	set(value):
		clouds_enabled = value
		if sky:
			sky.cumulus_visible = value
			sky.cirrus_visible = value


@export var lights_enabled: bool = true :
	set(value):
		lights_enabled = value
		if sky:
			sky.sun_light_enabled = value
			sky.moon_light_enabled = value


@export var fog_enabled: bool = true :
	set(value):
		fog_enabled = value
		if sky:
			sky.fog_visible = value


func hide_sky() -> void:
	sky_enabled = false
	lights_enabled = false
	fog_enabled = false
	clouds_enabled = false


func show_sky() -> void:
	sky_enabled = true
	lights_enabled = true
	fog_enabled = true
	clouds_enabled = true



@export_group("Time")


@export var editor_time_enabled: bool = true :
	set(value):
		if tod:
			tod.editor_time_enabled = value
	get:
		return tod.editor_time_enabled if tod else editor_time_enabled


@export var game_time_enabled: bool = true :
	set(value):
		if tod:
			tod.game_time_enabled = value
	get:
		return tod.game_time_enabled if tod else game_time_enabled


@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var game_date: String = "" :
	get:
		return tod.game_date if tod else game_date


@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var game_time: String = "" :
	get:
		return tod.game_time if tod else game_time


@export_range(0.0, 23.9998, 0.01) var current_time: float = 8.0 :
	set(value):
		if tod:
			tod.current_time = value
	get:
		return tod.current_time if tod else current_time


@export_range(-1440, 1440, 0.1) var minutes_per_day: float = 15.0 :
	set(value):
		if tod:
			tod.minutes_per_day = value
	get:
		return tod.minutes_per_day if tod else minutes_per_day


@export_range(0.016, 10.0) var update_interval: float = 0.016 :
	set(value):
		if tod:
			tod.update_interval = value
	get:
		return tod.update_interval if tod else update_interval


func is_day() -> bool:
	return sky and sky.is_day()


func is_night() -> bool:
	return sky and not sky.is_day()


func pause() -> void:
	if tod:
		tod.pause()


func resume() -> void:
	if tod:
		tod.resume()


var _contrib_tween: Tween

func _start_sky_contrib_tween(daytime: bool = is_day()) -> void:
	if not (sky and environment and is_inside_tree()):
		return

	if _contrib_tween:
		_contrib_tween.kill()
	_contrib_tween = get_tree().create_tween()
	_contrib_tween.set_parallel(true)

	if daytime:
		_contrib_tween.tween_property(environment, "ambient_light_sky_contribution", sky_contribution, contribution_tween_time)
	else:
		var night_contrib: float = minf(night_sky_contribution, sky_contribution) if night_ambient_boost else sky_contribution
		_contrib_tween.tween_property(environment, "ambient_light_sky_contribution", night_contrib, contribution_tween_time)



@export_group("Lighting")


@export_range(0, 16, 0.005) var camera_exposure: float = 1.0 :
	set(value):
		if camera_attributes:
			camera_attributes.exposure_multiplier = value
	get:
		return camera_attributes.exposure_multiplier if camera_attributes else camera_exposure


@export_range(0, 16, 0.005) var tonemap_exposure: float = 1.0 :
	set(value):
		if environment:
			environment.tonemap_exposure = value
	get:
		return environment.tonemap_exposure if environment else tonemap_exposure


@export_range(0, 16, 0.005) var skydome_energy: float = 1.0 :
	set(value):
		if sky:
			sky.exposure = value
	get:
		return sky.exposure if sky else skydome_energy


@export_range(0, 16, 0.005) var cloud_intensity: float = 0.6 :
	set(value):
		if sky:
			sky.cumulus_intensity = value
	get:
		return sky.cumulus_intensity if sky else cloud_intensity


@export_range(0, 16, 0.005) var sun_energy: float = 1.0 :
	set(value):
		if sky:
			sky.sun_light_energy = value
	get:
		return sky.sun_light_energy if sky else sun_energy


@export_range(0, 1, 0.005) var sun_shadow_opacity: float = 1.0 :
	set(value):
		if sun:
			sun.shadow_opacity = value
	get:
		return sun.shadow_opacity if sun else sun_shadow_opacity


@export_range(0, 1, 0.005) var sky_contribution: float = 1.0 :
	set(value):
		if environment:
			sky_contribution = value
			environment.ambient_light_sky_contribution = value
			_start_sky_contrib_tween()


@export_range(0, 16, 0.005) var ambient_energy: float = 1.0 :
	set(value):
		environment.ambient_light_energy = value
		_start_sky_contrib_tween()
	get:
		return environment.ambient_light_energy if environment else ambient_energy


@export_subgroup("Night")


@export_range(0, 16, 0.005) var moon_energy: float = 0.3 :
	set(value):
		if sky:
			sky.moon_light_energy = value
	get:
		return sky.moon_light_energy if sky else moon_energy


@export_range(0, 1, 0.005) var moon_shadow_opacity: float = 1.0 :
	set(value):
		if moon:
			moon.shadow_opacity = value
	get:
		return moon.shadow_opacity if moon else moon_shadow_opacity


@export var night_ambient_boost: bool = true :
	set(value):
		night_ambient_boost = value
		_start_sky_contrib_tween()


@export_range(0, 1, 0.005) var night_sky_contribution: float = 0.7 :
	set(value):
		night_sky_contribution = value
		if night_ambient_boost:
			_start_sky_contrib_tween()


@export_range(0, 30, 0.05) var contribution_tween_time: float = 3.0


@export_subgroup("Auto Exposure")


@export var auto_exposure: bool = false :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_enabled = value
	get:
		return camera_attributes.auto_exposure_enabled if camera_attributes else auto_exposure


@export_range(0.01, 16, 0.005) var auto_exposure_scale: float = 0.4 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_scale = value
	get:
		return camera_attributes.auto_exposure_scale if camera_attributes else auto_exposure_scale


@export_range(0, 1600, 0.5) var auto_exposure_min: float = 0.0 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_min_sensitivity = value
			if value > auto_exposure_max:
				auto_exposure_max = value
	get:
		return camera_attributes.auto_exposure_min_sensitivity if camera_attributes else auto_exposure_min


@export_range(30, 64000, 0.5) var auto_exposure_max: float = 800.0 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_max_sensitivity = value
			if value < auto_exposure_min:
				auto_exposure_min = value
	get:
		return camera_attributes.auto_exposure_max_sensitivity if camera_attributes else auto_exposure_max


@export_range(0.1, 64, 0.1) var auto_exposure_speed: float = 0.5 :
	set(value):
		if camera_attributes:
			camera_attributes.auto_exposure_speed = value
	get:
		return camera_attributes.auto_exposure_speed if camera_attributes else auto_exposure_speed



@export_group("Weather")

@export_custom(PROPERTY_HINT_RANGE, "0,120,0.1,or_greater,or_less,suffix:m/s") var wind_speed: float = 1.0 :
	set(value):
		if sky:
			sky.wind_speed = value
	get:
		return sky.wind_speed if sky else wind_speed

@export_custom(PROPERTY_HINT_RANGE, "-180,180,0.1,radians_as_degrees") var wind_direction: float = 0.0 :
	set(value):
		if sky:
			sky.wind_direction = value
	get:
		return sky.wind_direction if sky else wind_direction



@export_group("Overlays")


@export var show_azimuthal_grid: bool = false :
	set(value):
		if sky:
			sky.show_azimuthal_grid = value
	get:
		return sky.show_azimuthal_grid if sky else show_azimuthal_grid


@export var show_equatorial_grid: bool = false :
	set(value):
		if sky:
			sky.show_equatorial_grid = value
	get:
		return sky.show_equatorial_grid if sky else show_equatorial_grid




func _notification(what: int) -> void:
	if what in [ NOTIFICATION_SCENE_INSTANTIATED, NOTIFICATION_ENTER_TREE ]:
		_initialize()


func _initialize() -> void:
	if environment == null:
		environment = Environment.new()
		environment.background_mode = Environment.BG_SKY
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.ambient_light_sky_contribution = 0.7
		environment.ambient_light_energy = 1.0
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		environment.tonemap_white = 6
		emit_signal("environment_changed", environment)

	if environment.sky == null or environment.sky.sky_material is PhysicalSkyMaterial:
		environment.sky = Sky.new()
		environment.sky.sky_material = ShaderMaterial.new()
		environment.sky.sky_material.shader = load(SKY_SHADER)

	sky_material = environment.sky.sky_material

	if camera_attributes == null:
		camera_attributes = CameraAttributesPractical.new()


	if has_node("SunLight"):
		sun = $SunLight
	elif is_inside_tree():
		sun = DirectionalLight3D.new()
		sun.name = "SunLight"
		add_child(sun, true)
		sun.owner = get_tree().edited_scene_root
		sun.shadow_enabled = true

	if has_node("MoonLight"):
		moon = $MoonLight
	elif is_inside_tree():
		moon = DirectionalLight3D.new()
		moon.name = "MoonLight"
		add_child(moon, true)
		moon.owner = get_tree().edited_scene_root
		moon.shadow_enabled = true

	if has_node("Skydome"):
		$Skydome.name = "SkyDome"
	if has_node("SkyDome"):
		sky = $SkyDome
		sky.environment = environment
	elif is_inside_tree():
		sky = SkyDome.new()
		sky.name = "SkyDome"
		add_child(sky, true)
		sky.owner = get_tree().edited_scene_root
		sky.sun_light_path = "../SunLight"
		sky.moon_light_path = "../MoonLight"
		sky.environment = environment

	if has_node("TimeOfDay"):
		tod = $TimeOfDay
	elif is_inside_tree():
		tod = TimeOfDay.new()
		tod.name = "TimeOfDay"
		add_child(tod, true)
		tod.owner = get_tree().edited_scene_root
		tod.dome_path = "../SkyDome"
	if sky and not sky.day_night_changed.is_connected(_start_sky_contrib_tween):
		sky.day_night_changed.connect(_start_sky_contrib_tween)


func _enter_tree() -> void:
	_start_sky_contrib_tween()


func _set(property: StringName, value: Variant) -> bool:
	match property:
		"environment":
			sky.environment = value
			environment = value
			emit_signal("environment_changed", environment)
			return true
	return false
