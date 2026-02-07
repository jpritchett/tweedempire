extends Node3D
class_name CameraRig

@export var zoom_speed: float = 1.08
@export var pan_speed_base: float = 0.8
@export var edge_pan_margin_px: int = 12
@export var rotate_speed: float = 0.014
@export var tilt_min_deg: float = -25.0
@export var tilt_max_deg: float = -85.0
@export var auto_tilt_strength: float = 1.0
@export var smoothing: float = 12.0
@export var zoom_key_rate: float = 5.0
@export var overscan_factor: float = 0.25
@export var overscan_max: float = 40.0

var zoom_min: float = 10.0
var zoom_max: float = 200.0

var _bounds: Rect2 = Rect2()
var _margin: float = 0.0
var _cell_size: float = 1.0
var _heightmap = null

var _focus: Vector3 = Vector3.ZERO
var _target_focus: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _target_yaw: float = 0.0
var _pitch: float = deg_to_rad(-45.0)
var _target_pitch: float = deg_to_rad(-45.0)
var _zoom: float = 50.0
var _target_zoom: float = 50.0
var _default_zoom: float = 50.0
var _bookmarks: Array = []

@onready var yaw_pivot: Node3D = $YawPivot
@onready var pitch_pivot: Node3D = $YawPivot/PitchPivot
@onready var cam: Camera3D = $YawPivot/PitchPivot/Camera3D

func _ready() -> void:
	_ensure_input_actions()
	cam.make_current()
	_bookmarks.resize(9)
	_apply_transform(true)

func _ensure_input_actions() -> void:
	_ensure_action("cam_zoom_in", [_key(KEY_Q), _mouse_button(MOUSE_BUTTON_WHEEL_UP)])
	_ensure_action("cam_zoom_out", [_key(KEY_E), _mouse_button(MOUSE_BUTTON_WHEEL_DOWN)])
	_ensure_action("cam_pan_forward", [_key(KEY_W), _key(KEY_UP)])
	_ensure_action("cam_pan_back", [_key(KEY_S), _key(KEY_DOWN)])
	_ensure_action("cam_pan_left", [_key(KEY_A), _key(KEY_LEFT)])
	_ensure_action("cam_pan_right", [_key(KEY_D), _key(KEY_RIGHT)])
	_ensure_action("cam_rotate", [_key(KEY_SPACE)])
	_ensure_action("cam_fast", [_key(KEY_SHIFT)])
	_ensure_action("cam_reset", [_key(KEY_V)])

func _ensure_action(name: String, events: Array[InputEvent]) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name)
	for ev in events:
		if not InputMap.action_has_event(name, ev):
			InputMap.action_add_event(name, ev)

func _key(keycode: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	return ev

func _mouse_button(button_index: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button_index
	ev.pressed = true
	return ev

func configure(bounds: Rect2, cell_size: float, heightmap) -> void:
	_bounds = bounds
	_margin = cell_size * 2.0
	_cell_size = cell_size
	_heightmap = heightmap
	var extent = max(bounds.size.x, bounds.size.y)
	zoom_min = extent * 0.3
	zoom_max = extent * 3.0
	_focus = Vector3(bounds.position.x + bounds.size.x * 0.5, 0.0, bounds.position.y + bounds.size.y * 0.5)
	_target_focus = _focus
	_zoom = extent * 0.9
	_target_zoom = _zoom
	_default_zoom = _zoom
	_yaw = 0.0
	_target_yaw = 0.0
	_pitch = deg_to_rad(_auto_tilt_pitch(_get_zoom_t()))
	_target_pitch = _pitch
	_apply_transform(true)

func get_camera() -> Camera3D:
	return cam

func set_focus(p: Vector3) -> void:
	_target_focus = _clamp_focus(p)

func get_focus() -> Vector3:
	return _focus

func get_zoom_t() -> float:
	return _get_zoom_t()

func screen_to_ground(screen_pos: Vector2) -> Dictionary:
	return _ray_pick(screen_pos)

func _process(delta: float) -> void:
	_handle_zoom_input(delta)
	_handle_pan_input(delta)
	_handle_reset_input()

	if not Input.is_action_pressed("cam_rotate"):
		var auto_pitch = deg_to_rad(_auto_tilt_pitch(_get_zoom_t()))
		_target_pitch = lerp(_target_pitch, auto_pitch, clamp(auto_tilt_strength, 0.0, 1.0))

	var alpha = clamp(smoothing * delta, 0.0, 1.0)
	_focus = _focus.lerp(_target_focus, alpha)
	_yaw = lerp_angle(_yaw, _target_yaw, alpha)
	_pitch = lerp(_pitch, _target_pitch, alpha)
	_zoom = lerp(_zoom, _target_zoom, alpha)

	_apply_transform(false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom_steps(1.0, get_viewport().get_mouse_position())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom_steps(-1.0, get_viewport().get_mouse_position())

	if event is InputEventMouseMotion and Input.is_action_pressed("cam_rotate"):
		_target_yaw -= event.relative.x * rotate_speed
		_target_pitch -= event.relative.y * rotate_speed
		_target_pitch = clamp(_target_pitch, deg_to_rad(tilt_max_deg), deg_to_rad(tilt_min_deg))

	if event is InputEventKey and event.pressed and not event.echo:
		var idx = _fkey_index(event.keycode)
		if idx != -1:
			if event.ctrl_pressed:
				_save_bookmark(idx)
			elif not event.alt_pressed and not event.shift_pressed:
				_load_bookmark(idx)

func _handle_zoom_input(delta: float) -> void:
	var zoom_input = 0.0
	if Input.is_action_pressed("cam_zoom_in"):
		zoom_input += 1.0
	if Input.is_action_pressed("cam_zoom_out"):
		zoom_input -= 1.0
	if zoom_input != 0.0:
		var speed = zoom_key_rate * delta
		if Input.is_key_pressed(KEY_CTRL):
			speed *= 3.0
		_apply_zoom_steps(zoom_input * speed, get_viewport().get_mouse_position())

func _handle_pan_input(delta: float) -> void:
	var dir = Vector2.ZERO
	if Input.is_action_pressed("cam_pan_right"):
		dir.x += 1.0
	if Input.is_action_pressed("cam_pan_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("cam_pan_forward"):
		dir.y += 1.0
	if Input.is_action_pressed("cam_pan_back"):
		dir.y -= 1.0

	var edge_dir = _edge_pan_dir()
	if edge_dir != Vector2.ZERO:
		dir += edge_dir

	if dir == Vector2.ZERO:
		return
	dir = dir.normalized()

	var speed = pan_speed_base * _target_zoom
	if Input.is_action_pressed("cam_fast"):
		speed *= 2.5

	var basis = Basis(Vector3.UP, _target_yaw)
	var right = basis.x
	var forward = -basis.z
	var move = (right * dir.x + forward * dir.y) * speed * delta
	_target_focus = _clamp_focus(_target_focus + Vector3(move.x, 0.0, move.z))

func _handle_reset_input() -> void:
	if Input.is_action_just_pressed("cam_reset"):
		_target_yaw = 0.0
		_target_zoom = _default_zoom
		_target_pitch = deg_to_rad(_auto_tilt_pitch(_get_zoom_t()))

func _edge_pan_dir() -> Vector2:
	var vp_size = get_viewport().get_visible_rect().size
	var mp = get_viewport().get_mouse_position()
	var dir = Vector2.ZERO
	if mp.x <= edge_pan_margin_px:
		dir.x -= 1.0
	elif mp.x >= vp_size.x - edge_pan_margin_px:
		dir.x += 1.0
	if mp.y <= edge_pan_margin_px:
		dir.y += 1.0
	elif mp.y >= vp_size.y - edge_pan_margin_px:
		dir.y -= 1.0
	return dir

func _apply_zoom_steps(steps: float, _mouse_pos: Vector2) -> void:
	if steps == 0.0:
		return
	# Simple zoom: just change the distance, no cursor tracking
	_target_zoom = clamp(_target_zoom * pow(zoom_speed, -steps), zoom_min, zoom_max)

func _ray_pick(screen_pos: Vector2) -> Dictionary:
	var from = cam.project_ray_origin(screen_pos)
	var dir = cam.project_ray_normal(screen_pos)
	var to = from + dir * 2000.0
	var space_state = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)

func _ray_pick_with_zoom(screen_pos: Vector2, zoom_override: float) -> Dictionary:
	var prev_zoom = _zoom
	_zoom = zoom_override
	_apply_transform(true)
	var hit = _ray_pick(screen_pos)
	_zoom = prev_zoom
	_apply_transform(true)
	return hit

func _ground_pick(screen_pos: Vector2) -> Dictionary:
	# Only use heightmap for ground picking (ignores all objects)
	if _heightmap != null:
		var hit = _heightmap_pick(screen_pos)
		if hit.has("position"):
			return hit
	# Fallback to simple plane intersection at y=0 if no heightmap
	return _plane_pick(screen_pos, 0.0)

func _plane_pick(screen_pos: Vector2, plane_y: float) -> Dictionary:
	var from = cam.project_ray_origin(screen_pos)
	var dir = cam.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.0001:
		return {}
	var t = (plane_y - from.y) / dir.y
	if t < 0.0:
		return {}
	var hit_pos = from + dir * t
	return {"position": hit_pos}

func _ground_pick_with_zoom(screen_pos: Vector2, zoom_override: float) -> Dictionary:
	var prev_zoom = _zoom
	_zoom = zoom_override
	_apply_transform(true)
	var hit = _ground_pick(screen_pos)
	_zoom = prev_zoom
	_apply_transform(true)
	return hit

func _heightmap_pick(screen_pos: Vector2) -> Dictionary:
	if _bounds.size == Vector2.ZERO:
		return {}
	var from = cam.project_ray_origin(screen_pos)
	var dir = cam.project_ray_normal(screen_pos).normalized()
	var max_dist = 2000.0
	var step = max(_cell_size, 0.5)
	var t = 0.0
	var prev_t = -1.0
	var prev_d = 0.0
	while t <= max_dist:
		var p = from + dir * t
		if not _bounds.has_point(Vector2(p.x, p.z)):
			t += step
			continue
		var h = _heightmap.sample_height_world(p.x, p.z)
		var d = p.y - h
		if prev_t >= 0.0 and prev_d > 0.0 and d <= 0.0:
			var t0 = prev_t
			var t1 = t
			for _i in range(8):
				var tm = (t0 + t1) * 0.5
				var pm = from + dir * tm
				var hm = _heightmap.sample_height_world(pm.x, pm.z)
				var dm = pm.y - hm
				if dm > 0.0:
					t0 = tm
				else:
					t1 = tm
			var hit_pos = from + dir * t1
			var hit_h = _heightmap.sample_height_world(hit_pos.x, hit_pos.z)
			return {"position": Vector3(hit_pos.x, hit_h, hit_pos.z)}
		prev_t = t
		prev_d = d
		t += step
	return {}

func _apply_transform(_force: bool) -> void:
	yaw_pivot.global_position = _focus
	yaw_pivot.rotation = Vector3(0.0, _yaw, 0.0)
	pitch_pivot.rotation = Vector3(_pitch, 0.0, 0.0)
	cam.position = Vector3(0.0, 0.0, _zoom)

	# Clamp camera to stay above terrain (with small buffer)
	_clamp_camera_above_terrain()

func _clamp_camera_above_terrain() -> void:
	if _heightmap == null:
		return
	var cam_pos = cam.global_position
	# Check if camera is within terrain bounds
	if not _bounds.has_point(Vector2(cam_pos.x, cam_pos.z)):
		return
	var terrain_height = _heightmap.sample_height_world(cam_pos.x, cam_pos.z)
	var min_height = terrain_height + 3.0  # 3 unit buffer above terrain
	if cam_pos.y < min_height:
		# Increase zoom (distance) to push camera back up
		var pitch_sin = abs(sin(_pitch))
		if pitch_sin > 0.1:
			var height_needed = min_height - cam_pos.y
			var zoom_increase = height_needed / pitch_sin
			_zoom = _zoom + zoom_increase
			_target_zoom = maxf(_target_zoom, _zoom)
			cam.position = Vector3(0.0, 0.0, _zoom)

func _clamp_focus(p: Vector3) -> Vector3:
	if _bounds.size == Vector2.ZERO:
		return p
	var extra = min(overscan_max, _target_zoom * overscan_factor)
	var pad = _margin + extra
	var min_x = _bounds.position.x - pad
	var max_x = _bounds.position.x + _bounds.size.x + pad
	var min_z = _bounds.position.y - pad
	var max_z = _bounds.position.y + _bounds.size.y + pad
	var clamped_x = clamp(p.x, min_x, max_x)
	var clamped_z = clamp(p.z, min_z, max_z)
	# Set focus Y to terrain height if within bounds
	var focus_y = p.y
	if _heightmap != null and _bounds.has_point(Vector2(clamped_x, clamped_z)):
		focus_y = _heightmap.sample_height_world(clamped_x, clamped_z)
	return Vector3(clamped_x, focus_y, clamped_z)

func _auto_tilt_pitch(zoom_t: float) -> float:
	return lerp(tilt_min_deg, tilt_max_deg, zoom_t)

func _get_zoom_t() -> float:
	if zoom_max <= zoom_min:
		return 0.0
	return clamp((_zoom - zoom_min) / (zoom_max - zoom_min), 0.0, 1.0)

func _fkey_index(keycode: int) -> int:
	if keycode < KEY_F1 or keycode > KEY_F9:
		return -1
	return keycode - KEY_F1

func _save_bookmark(idx: int) -> void:
	if idx < 0 or idx >= _bookmarks.size():
		return
	_bookmarks[idx] = {
		"focus": _target_focus,
		"yaw": _target_yaw,
		"pitch": _target_pitch,
		"zoom": _target_zoom
	}

func _load_bookmark(idx: int) -> void:
	if idx < 0 or idx >= _bookmarks.size():
		return
	var b = _bookmarks[idx]
	if b == null:
		return
	_target_focus = _clamp_focus(b.focus)
	_target_yaw = b.yaw
	_target_pitch = clamp(b.pitch, deg_to_rad(tilt_max_deg), deg_to_rad(tilt_min_deg))
	_target_zoom = clamp(b.zoom, zoom_min, zoom_max)
