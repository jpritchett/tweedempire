extends Node
class_name SkyController

## Controls the day/night cycle by rotating a DirectionalLight3D (sun).
## Attach to any node and assign the sun reference.

@export var sun: DirectionalLight3D
@export var cycle_enabled: bool = true

## Full day/night cycle duration in seconds
@export var cycle_duration: float = 120.0

## Current time of day (0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset)
@export_range(0.0, 1.0) var time_of_day: float = 0.3

## Axis around which the sun rotates (usually X for east-west movement)
@export var rotation_axis: Vector3 = Vector3(1, 0, 0)

## Tilt angle to add variation to the sun path
@export var orbit_tilt: float = 15.0

## Sun light energy at different times
@export var noon_energy: float = 1.8
@export var sunset_energy: float = 0.8
@export var night_energy: float = 0.1

## Sun color at different times
@export var noon_color: Color = Color(1.0, 0.98, 0.95)
@export var sunset_color: Color = Color(1.0, 0.6, 0.3)
@export var night_color: Color = Color(0.2, 0.2, 0.4)

signal time_changed(new_time: float)
signal day_phase_changed(phase: String)

var _last_phase: String = ""

func _ready() -> void:
	if sun == null:
		push_warning("SkyController: No sun DirectionalLight3D assigned")
	_update_sun()

func _process(delta: float) -> void:
	if not cycle_enabled or sun == null:
		return

	# Advance time
	time_of_day += delta / cycle_duration
	if time_of_day >= 1.0:
		time_of_day -= 1.0

	_update_sun()
	time_changed.emit(time_of_day)

	# Check for phase changes
	var phase = get_day_phase()
	if phase != _last_phase:
		_last_phase = phase
		day_phase_changed.emit(phase)

func _update_sun() -> void:
	if sun == null:
		return

	# Sun arc: time_of_day 0.0 = midnight (below), 0.5 = noon (above)
	# DirectionalLight3D shines along local -Z
	# rotation.x = PI/2 → -Z points to +Y (upward, below horizon)
	# rotation.x = -PI/2 → -Z points to -Y (downward, sun overhead)
	var sun_pitch = PI * 0.5 - time_of_day * TAU
	sun.rotation = Vector3(sun_pitch, deg_to_rad(orbit_tilt), 0.0)

	# Update sun energy based on height
	# Direction toward the sun (opposite of light direction), positive Y = sun above horizon
	var sun_dir = sun.basis.z
	var sun_height = sun_dir.y

	# Calculate energy
	var energy: float
	if sun_height > 0.1:
		# Day time
		energy = lerp(sunset_energy, noon_energy, smoothstep(0.1, 0.5, sun_height))
	elif sun_height > -0.1:
		# Sunset/sunrise
		energy = lerp(night_energy, sunset_energy, smoothstep(-0.1, 0.1, sun_height))
	else:
		# Night
		energy = night_energy

	sun.light_energy = energy

	# Calculate sun color
	var sun_col: Color
	if sun_height > 0.2:
		sun_col = noon_color
	elif sun_height > -0.1:
		var sunset_t = smoothstep(-0.1, 0.2, sun_height)
		sun_col = night_color.lerp(sunset_color, smoothstep(0.0, 0.5, sunset_t))
		sun_col = sun_col.lerp(noon_color, smoothstep(0.5, 1.0, sunset_t))
	else:
		sun_col = night_color

	sun.light_color = sun_col

## Get the current phase of day as a string
func get_day_phase() -> String:
	if time_of_day < 0.2:
		return "night"
	elif time_of_day < 0.3:
		return "dawn"
	elif time_of_day < 0.45:
		return "morning"
	elif time_of_day < 0.55:
		return "noon"
	elif time_of_day < 0.7:
		return "afternoon"
	elif time_of_day < 0.8:
		return "dusk"
	else:
		return "night"

## Set time of day directly (0.0 to 1.0)
func set_time(t: float) -> void:
	time_of_day = clamp(t, 0.0, 1.0)
	_update_sun()
	time_changed.emit(time_of_day)

## Set time to a specific phase
func set_phase(phase: String) -> void:
	match phase:
		"midnight":
			set_time(0.0)
		"dawn":
			set_time(0.25)
		"morning":
			set_time(0.35)
		"noon":
			set_time(0.5)
		"afternoon":
			set_time(0.6)
		"dusk":
			set_time(0.75)
		"night":
			set_time(0.85)

## Smoothstep helper
func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Get hours as 0-24 float
func get_hours() -> float:
	return time_of_day * 24.0

## Get formatted time string (HH:MM)
func get_time_string() -> String:
	var hours = int(time_of_day * 24.0)
	var minutes = int(fmod(time_of_day * 24.0 * 60.0, 60.0))
	return "%02d:%02d" % [hours, minutes]
