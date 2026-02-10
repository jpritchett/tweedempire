extends Node3D
class_name WeatherController
## View orchestrator for the weather system. Reads WeatherSimulation data
## and pushes it to shaders, particle effects, fog, and lightning.
## This is the view layer — no simulation logic here.

var _sky_mat: ShaderMaterial
var _terrain_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _env: Environment
var _sun: DirectionalLight3D
var _camera: Camera3D

var _rain_effect: RainEffect
var _snow_effect: SnowEffect
var _lightning_effect: LightningEffect
var _fog_controller: FogController

# Debug overlay
var _debug_overlay: CanvasLayer
var _debug_visible: bool = false
var _debug_wind_rect: TextureRect
var _debug_rft_rect: TextureRect
var _debug_label: Label

# Cached weather values at camera position
var _local_wind := Vector2.ZERO
var _local_rain: float = 0.0
var _local_fog: float = 0.0
var _local_temp: float = 0.5

func setup(sky_mat: ShaderMaterial, terrain_mat: ShaderMaterial,
		   water_mat: ShaderMaterial, env: Environment,
		   sun: DirectionalLight3D, camera: Camera3D) -> void:
	_sky_mat = sky_mat
	_terrain_mat = terrain_mat
	_water_mat = water_mat
	_env = env
	_sun = sun
	_camera = camera

	# Create sub-effects
	_rain_effect = RainEffect.new()
	add_child(_rain_effect)

	_snow_effect = SnowEffect.new()
	add_child(_snow_effect)

	_lightning_effect = LightningEffect.new()
	_lightning_effect.setup(_sky_mat, _sun)
	add_child(_lightning_effect)

	_fog_controller = FogController.new()
	_fog_controller.setup(_env)
	add_child(_fog_controller)

	# Connect weather stepped signal
	Simulation.weather_stepped.connect(_on_weather_stepped)

	# Create debug overlay
	_create_debug_overlay()

func _on_weather_stepped() -> void:
	# Bake textures for shader upload
	var sim := Simulation.weather_sim
	sim.bake_textures()

	# Push rain/fog/temp texture to terrain shader
	if _terrain_mat != null and sim.rain_fog_temp_texture != null:
		_terrain_mat.set_shader_parameter("weather_rain_fog_tex", sim.rain_fog_temp_texture)

	# Update debug overlay textures
	if _debug_visible:
		_update_debug_overlay()

func _process(_delta: float) -> void:
	if _camera == null:
		return

	var cam_pos := _camera.global_position
	var sim := Simulation.weather_sim

	# Sample weather at camera position (world xz)
	var sample := sim.sample_at_world(cam_pos.x, cam_pos.z)
	_local_wind = Vector2(sample.wind_x, sample.wind_y)
	_local_rain = sample.rain
	_local_fog = sample.fog
	_local_temp = sample.temperature

	# Sky shader uniforms
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("weather_wind", _local_wind)
		_sky_mat.set_shader_parameter("weather_cloud_boost", clampf(_local_rain + _local_fog * 0.5, 0.0, 1.0))
		_sky_mat.set_shader_parameter("weather_fog_intensity", _local_fog)

	# Water shader uniforms
	if _water_mat != null:
		var wind_strength := _local_wind.length()
		_water_mat.set_shader_parameter("weather_wind_strength", wind_strength)
		_water_mat.set_shader_parameter("weather_rain_intensity", _local_rain)

	# Rain vs snow based on temperature
	var is_cold := _local_temp < 0.3
	if is_cold:
		_rain_effect.set_intensity(0.0)
		_snow_effect.set_intensity(_local_rain)
		_snow_effect.set_wind(_local_wind)
		_snow_effect.follow_camera(cam_pos)
	else:
		_snow_effect.set_intensity(0.0)
		_rain_effect.set_intensity(_local_rain)
		_rain_effect.set_wind(_local_wind)
		_rain_effect.follow_camera(cam_pos)

	# Lightning
	_lightning_effect.set_rain_intensity(_local_rain)

	# Fog
	_fog_controller.update_fog(_local_fog, _local_rain)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			_toggle_debug_overlay()

# ── Debug Overlay ────────────────────────────────────────────────

func _create_debug_overlay() -> void:
	_debug_overlay = CanvasLayer.new()
	_debug_overlay.layer = 100
	_debug_overlay.visible = false
	add_child(_debug_overlay)

	var panel := PanelContainer.new()
	panel.position = Vector2(10, 10)
	_debug_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	_debug_label = Label.new()
	_debug_label.text = "Weather Debug"
	vbox.add_child(_debug_label)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	# Wind texture display
	var wind_vbox := VBoxContainer.new()
	hbox.add_child(wind_vbox)
	var wind_lbl := Label.new()
	wind_lbl.text = "Wind"
	wind_vbox.add_child(wind_lbl)
	_debug_wind_rect = TextureRect.new()
	_debug_wind_rect.custom_minimum_size = Vector2(128, 128)
	_debug_wind_rect.stretch_mode = TextureRect.STRETCH_SCALE
	wind_vbox.add_child(_debug_wind_rect)

	# Rain/fog/temp texture display
	var rft_vbox := VBoxContainer.new()
	hbox.add_child(rft_vbox)
	var rft_lbl := Label.new()
	rft_lbl.text = "Rain/Fog/Temp"
	rft_vbox.add_child(rft_lbl)
	_debug_rft_rect = TextureRect.new()
	_debug_rft_rect.custom_minimum_size = Vector2(128, 128)
	_debug_rft_rect.stretch_mode = TextureRect.STRETCH_SCALE
	rft_vbox.add_child(_debug_rft_rect)

func _toggle_debug_overlay() -> void:
	_debug_visible = not _debug_visible
	_debug_overlay.visible = _debug_visible
	if _debug_visible:
		_update_debug_overlay()

func _update_debug_overlay() -> void:
	var sim := Simulation.weather_sim
	if sim.wind_texture != null:
		_debug_wind_rect.texture = sim.wind_texture
	if sim.rain_fog_temp_texture != null:
		_debug_rft_rect.texture = sim.rain_fog_temp_texture

	# Update label with local weather info
	var pattern_info := ""
	for i in range(sim.patterns.size()):
		var p := sim.patterns[i]
		pattern_info += "\n  %s @ (%.0f,%.0f) age=%.0f/%.0f" % [
			p.get("name", "?"), p.get("cell_x", 0), p.get("cell_y", 0),
			p.get("age", 0), p.get("lifespan", 0)]

	_debug_label.text = "Weather Debug\nWind: (%.2f, %.2f)\nRain: %.2f  Fog: %.2f  Temp: %.2f\nPatterns: %d%s" % [
		_local_wind.x, _local_wind.y, _local_rain, _local_fog, _local_temp,
		sim.patterns.size(), pattern_info]
