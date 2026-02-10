extends Node
class_name FogController
## Drives Environment fog parameters from weather simulation data.

var _env: Environment

func setup(env: Environment) -> void:
	_env = env
	if _env != null:
		_env.fog_enabled = true
		_env.fog_density = 0.0
		_env.fog_light_color = Color(0.7, 0.75, 0.8)

func update_fog(fog_amount: float, rain_amount: float) -> void:
	if _env == null:
		return
	# Base density + weather contribution
	var density := fog_amount * 0.03 + rain_amount * 0.01
	_env.fog_density = clampf(density, 0.0, 0.06)

	# Darken fog colour in heavy fog
	var darkness := clampf(fog_amount * 0.3, 0.0, 0.3)
	var base_col := Color(0.7, 0.75, 0.8)
	var dark_col := Color(0.4, 0.42, 0.45)
	_env.fog_light_color = base_col.lerp(dark_col, darkness)
