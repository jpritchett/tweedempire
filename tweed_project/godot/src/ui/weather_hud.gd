extends CanvasLayer
class_name WeatherHUD
## Combination weather indicator: current conditions readout + mini radar.

const CONDITIONS_UPDATE_INTERVAL := 0.25  # ~4 Hz
const RADAR_DISPLAY_SIZE := 96
const GRID_SIZE := 64
const WIND_ARROWS := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]

# UI nodes
var _panel: PanelContainer
var _icon_label: Label
var _temp_label: Label
var _wind_label: Label
var _precip_label: Label
var _radar_rect: TextureRect
var _radar_marker: ColorRect

# Radar compositing
var _radar_image: Image
var _radar_texture: ImageTexture

# References (set via setup())
var _weather_controller: WeatherController
var _camera: Camera3D

# Throttle
var _update_accum: float = 0.0

func setup(controller: WeatherController, camera: Camera3D) -> void:
	_weather_controller = controller
	_camera = camera
	Simulation.weather_stepped.connect(_on_weather_stepped)

func _ready() -> void:
	layer = 10
	_build_ui()

func _process(delta: float) -> void:
	if _weather_controller == null:
		return
	_update_accum += delta
	if _update_accum >= CONDITIONS_UPDATE_INTERVAL:
		_update_accum -= CONDITIONS_UPDATE_INTERVAL
		_update_conditions()

# ── UI Construction ──────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -10.0
	_panel.offset_top = 10.0
	_panel.offset_right = -10.0
	_panel.offset_bottom = 10.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_END

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	_panel.add_child(hbox)

	# Left: conditions
	var conditions := VBoxContainer.new()
	conditions.add_theme_constant_override("separation", 2)
	hbox.add_child(conditions)

	_icon_label = Label.new()
	_icon_label.add_theme_font_size_override("font_size", 18)
	_icon_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	conditions.add_child(_icon_label)

	_temp_label = Label.new()
	_temp_label.add_theme_font_size_override("font_size", 12)
	conditions.add_child(_temp_label)

	_wind_label = Label.new()
	_wind_label.add_theme_font_size_override("font_size", 12)
	_wind_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	conditions.add_child(_wind_label)

	_precip_label = Label.new()
	_precip_label.add_theme_font_size_override("font_size", 12)
	_precip_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	conditions.add_child(_precip_label)

	# Right: radar
	var radar_panel := PanelContainer.new()
	var radar_style := StyleBoxFlat.new()
	radar_style.bg_color = Color(0.05, 0.06, 0.1, 0.9)
	radar_style.corner_radius_top_left = 4
	radar_style.corner_radius_top_right = 4
	radar_style.corner_radius_bottom_left = 4
	radar_style.corner_radius_bottom_right = 4
	radar_panel.add_theme_stylebox_override("panel", radar_style)
	hbox.add_child(radar_panel)

	var radar_stack := Control.new()
	radar_stack.custom_minimum_size = Vector2(RADAR_DISPLAY_SIZE, RADAR_DISPLAY_SIZE)
	radar_panel.add_child(radar_stack)

	_radar_rect = TextureRect.new()
	_radar_rect.custom_minimum_size = Vector2(RADAR_DISPLAY_SIZE, RADAR_DISPLAY_SIZE)
	_radar_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_radar_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_radar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar_stack.add_child(_radar_rect)

	_radar_marker = ColorRect.new()
	_radar_marker.color = Color(1.0, 1.0, 0.3, 0.9)
	_radar_marker.size = Vector2(4, 4)
	_radar_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar_stack.add_child(_radar_marker)

	add_child(_panel)

# ── Conditions Update ────────────────────────────────────────────

func _update_conditions() -> void:
	var rain: float = _weather_controller._local_rain
	var fog: float = _weather_controller._local_fog
	var temp: float = _weather_controller._local_temp
	var wind: Vector2 = _weather_controller._local_wind

	_icon_label.text = _get_weather_icon(rain, fog, temp)
	_temp_label.text = _get_temp_word(temp)
	_temp_label.add_theme_color_override("font_color", _get_temp_color(temp))
	_wind_label.text = "%s %s" % [_get_wind_arrow(wind), _get_wind_strength(wind)]
	_precip_label.text = _get_precip_text(rain, temp)

func _get_weather_icon(rain: float, fog: float, temp: float) -> String:
	if fog > 0.4:
		return "Fog"
	if rain > 0.3:
		if temp < 0.3:
			return "Snow"
		elif rain > 0.7:
			return "Storm"
		else:
			return "Rain"
	if rain > 0.05:
		return "Showers"
	return "Clear"

func _get_temp_word(temp: float) -> String:
	if temp < 0.2: return "Cold"
	if temp < 0.35: return "Cool"
	if temp < 0.55: return "Mild"
	if temp < 0.75: return "Warm"
	return "Hot"

func _get_temp_color(temp: float) -> Color:
	if temp < 0.2: return Color(0.4, 0.6, 1.0)
	if temp < 0.35: return Color(0.5, 0.7, 0.9)
	if temp < 0.55: return Color(0.8, 0.8, 0.8)
	if temp < 0.75: return Color(0.9, 0.7, 0.4)
	return Color(1.0, 0.5, 0.3)

func _get_wind_arrow(wind: Vector2) -> String:
	if wind.length() < 0.1:
		return "o"
	var angle := wind.angle()
	var idx := int(round(angle / (TAU / 8.0))) % 8
	if idx < 0:
		idx += 8
	return WIND_ARROWS[idx]

func _get_wind_strength(wind: Vector2) -> String:
	var speed := wind.length()
	if speed < 0.2: return "Calm"
	if speed < 0.8: return "Light"
	if speed < 1.5: return "Moderate"
	if speed < 3.0: return "Strong"
	return "Gale"

func _get_precip_text(rain: float, temp: float) -> String:
	if rain < 0.05:
		return "No precip"
	var type_word := "Snow" if temp < 0.3 else "Rain"
	if rain < 0.3: return "Light %s" % type_word
	if rain < 0.6: return "%s" % type_word
	return "Heavy %s" % type_word

# ── Radar Update ─────────────────────────────────────────────────

func _on_weather_stepped() -> void:
	_update_radar()
	_update_marker()

func _update_radar() -> void:
	var sim := Simulation.weather_sim
	if sim == null:
		return

	if _radar_image == null:
		_radar_image = Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGBA8)

	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var idx := y * GRID_SIZE + x
			var r_val := clampf(sim.rain[idx], 0.0, 1.0)
			var f_val := clampf(sim.fog[idx], 0.0, 1.0)
			var t_val := clampf(sim.temperature[idx], 0.0, 1.0)

			# Dark base
			var color := Color(0.05, 0.06, 0.1, 0.9)

			# Temperature tint
			if t_val < 0.4:
				var cold_t := (0.4 - t_val) / 0.4
				color = color.lerp(Color(0.1, 0.15, 0.25, 0.9), cold_t * 0.4)
			elif t_val > 0.6:
				var warm_t := (t_val - 0.6) / 0.4
				color = color.lerp(Color(0.2, 0.12, 0.05, 0.9), warm_t * 0.3)

			# Fog: grey overlay
			if f_val > 0.05:
				color = color.lerp(Color(0.6, 0.6, 0.6, 0.9), f_val * 0.5)

			# Precipitation
			if r_val > 0.05:
				var precip_color: Color
				if t_val < 0.3:
					precip_color = Color(0.8, 0.85, 1.0, 0.9)  # Snow
				else:
					precip_color = Color(0.2, 0.4, 0.9, 0.9)   # Rain
				color = color.lerp(precip_color, r_val * 0.7)

			_radar_image.set_pixel(x, y, color)

	if _radar_texture == null:
		_radar_texture = ImageTexture.create_from_image(_radar_image)
	else:
		_radar_texture.update(_radar_image)
	_radar_rect.texture = _radar_texture

func _update_marker() -> void:
	if _camera == null:
		return
	var cam_pos := _camera.global_position
	var sim := Simulation.weather_sim
	if sim == null:
		return
	var u := clampf(cam_pos.x / sim._world_size.x, 0.0, 1.0)
	var v := clampf(cam_pos.z / sim._world_size.y, 0.0, 1.0)
	_radar_marker.position = Vector2(
		u * RADAR_DISPLAY_SIZE - 2.0,
		v * RADAR_DISPLAY_SIZE - 2.0
	)
