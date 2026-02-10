extends RefCounted
class_name WeatherSimulation
## 2D fluid simulation for weather: wind, rain, fog, temperature.
## Runs on a 64x64 grid covering the world map. Deterministic when
## given a seeded RandomNumberGenerator.
##
## Based on Jos Stam's "Stable Fluids" — advection + diffusion + pressure
## projection, operating on PackedFloat32Arrays for speed.

const GRID_SIZE := 64
const CELL_COUNT := GRID_SIZE * GRID_SIZE

# Grids (flat arrays, row-major: index = y * GRID_SIZE + x)
var wind_x: PackedFloat32Array
var wind_y: PackedFloat32Array
var rain: PackedFloat32Array
var fog: PackedFloat32Array
var temperature: PackedFloat32Array

# Scratch buffers for advection
var _tmp_a: PackedFloat32Array
var _tmp_b: PackedFloat32Array

# World dimensions (used for world-space queries)
var _world_size: Vector2
var _cell_size: Vector2

# Active weather patterns
var patterns: Array[Dictionary] = []

# Baked textures for shader upload
var wind_texture: ImageTexture
var rain_fog_temp_texture: ImageTexture

func _init() -> void:
	_world_size = Vector2(256.0, 256.0)
	_cell_size = _world_size / float(GRID_SIZE)
	_alloc_grids()

func setup(world_size: Vector2) -> void:
	_world_size = world_size
	_cell_size = _world_size / float(GRID_SIZE)

func _alloc_grids() -> void:
	wind_x = PackedFloat32Array()
	wind_x.resize(CELL_COUNT)
	wind_y = PackedFloat32Array()
	wind_y.resize(CELL_COUNT)
	rain = PackedFloat32Array()
	rain.resize(CELL_COUNT)
	fog = PackedFloat32Array()
	fog.resize(CELL_COUNT)
	temperature = PackedFloat32Array()
	temperature.resize(CELL_COUNT)
	# Initialise temperature to 0.5 (mild)
	for i in range(CELL_COUNT):
		temperature[i] = 0.5
	_tmp_a = PackedFloat32Array()
	_tmp_a.resize(CELL_COUNT)
	_tmp_b = PackedFloat32Array()
	_tmp_b.resize(CELL_COUNT)

# ── Index helpers ────────────────────────────────────────────────
func _idx(x: int, y: int) -> int:
	return clampi(y, 0, GRID_SIZE - 1) * GRID_SIZE + clampi(x, 0, GRID_SIZE - 1)

func _world_to_cell(wx: float, wz: float) -> Vector2:
	return Vector2(
		clampf(wx / _cell_size.x, 0.0, float(GRID_SIZE - 1)),
		clampf(wz / _cell_size.y, 0.0, float(GRID_SIZE - 1))
	)

# ── Main step (called every weather tick) ────────────────────────
func step(rng: RandomNumberGenerator) -> void:
	# 1) Inject forces from active patterns
	_inject_patterns(rng)

	# 2) Diffuse wind
	_diffuse(wind_x, 0.0001)
	_diffuse(wind_y, 0.0001)

	# 3) Advect wind by itself (self-advection)
	_advect(wind_x, wind_x, wind_y)
	_advect(wind_y, wind_x, wind_y)

	# 4) Pressure projection (make velocity divergence-free)
	_project()

	# 5) Advect rain, fog, temperature by wind
	_advect(rain, wind_x, wind_y)
	_advect(fog, wind_x, wind_y)
	_advect(temperature, wind_x, wind_y)

	# 6) Decay scalar fields
	for i in range(CELL_COUNT):
		rain[i] = maxf(rain[i] * 0.985 - 0.001, 0.0)
		fog[i] = maxf(fog[i] * 0.99 - 0.0005, 0.0)
		# Temperature relaxes toward 0.5
		temperature[i] = lerpf(temperature[i], 0.5, 0.005)

	# 7) Advance pattern positions and lifespans
	_advance_patterns()

	# 8) Auto-spawn patterns to maintain 2-4 active
	_auto_spawn_patterns(rng)

# ── Pattern injection ────────────────────────────────────────────
func _inject_patterns(rng: RandomNumberGenerator) -> void:
	for pat in patterns:
		var cx: float = pat.cell_x
		var cy: float = pat.cell_y
		var radius: float = pat.get("radius", 10.0)
		var life_frac: float = _pattern_life_fraction(pat)
		var fade: float = _pattern_fade(life_frac)

		var r_int := int(ceil(radius))
		var cx_i := int(cx)
		var cy_i := int(cy)

		for dy in range(-r_int, r_int + 1):
			for dx in range(-r_int, r_int + 1):
				var gx := cx_i + dx
				var gy := cy_i + dy
				if gx < 0 or gx >= GRID_SIZE or gy < 0 or gy >= GRID_SIZE:
					continue
				var dist := sqrt(float(dx * dx + dy * dy))
				if dist > radius:
					continue
				var falloff := 1.0 - (dist / radius)
				falloff *= falloff  # quadratic
				falloff *= fade
				var idx := _idx(gx, gy)

				# Wind
				var wx: float = pat.get("wind_x", 0.0)
				var wy: float = pat.get("wind_y", 0.0)
				# Rotation for cyclone/anticyclone
				var rotation: float = pat.get("rotation", 0.0)
				if rotation != 0.0:
					var angle := atan2(float(dy), float(dx))
					var tang_x := -sin(angle) * rotation
					var tang_y := cos(angle) * rotation
					wx += tang_x * pat.get("wind_strength", 1.0)
					wy += tang_y * pat.get("wind_strength", 1.0)
				wind_x[idx] += wx * falloff * 0.15
				wind_y[idx] += wy * falloff * 0.15

				# Rain
				var r_val: float = pat.get("rain_amount", 0.0)
				if r_val > 0.0:
					rain[idx] = minf(rain[idx] + r_val * falloff * 0.08, 1.0)

				# Fog
				var f_val: float = pat.get("fog_amount", 0.0)
				if f_val > 0.0:
					fog[idx] = minf(fog[idx] + f_val * falloff * 0.06, 1.0)

				# Temperature
				var t_val: float = pat.get("temp_offset", 0.0)
				if t_val != 0.0:
					temperature[idx] = clampf(temperature[idx] + t_val * falloff * 0.02, 0.0, 1.0)

func _pattern_life_fraction(pat: Dictionary) -> float:
	var age: float = pat.get("age", 0.0)
	var lifespan: float = pat.get("lifespan", 100.0)
	return clampf(age / lifespan, 0.0, 1.0)

func _pattern_fade(life_frac: float) -> float:
	# Fade in over first 20%, fade out over last 20%
	if life_frac < 0.2:
		return life_frac / 0.2
	elif life_frac > 0.8:
		return (1.0 - life_frac) / 0.2
	return 1.0

func _advance_patterns() -> void:
	var to_remove: Array[int] = []
	for i in range(patterns.size()):
		var pat := patterns[i]
		pat.age = pat.get("age", 0.0) + 1.0
		# Move with local wind field
		var cx_i := clampi(int(pat.cell_x), 0, GRID_SIZE - 1)
		var cy_i := clampi(int(pat.cell_y), 0, GRID_SIZE - 1)
		var idx := _idx(cx_i, cy_i)
		var move_speed: float = pat.get("move_speed", 0.3)
		pat.cell_x += wind_x[idx] * move_speed + pat.get("drift_x", 0.0)
		pat.cell_y += wind_y[idx] * move_speed + pat.get("drift_y", 0.0)
		# Remove expired or off-grid patterns
		if pat.age >= pat.get("lifespan", 100.0):
			to_remove.append(i)
		elif pat.cell_x < -10 or pat.cell_x > GRID_SIZE + 10:
			to_remove.append(i)
		elif pat.cell_y < -10 or pat.cell_y > GRID_SIZE + 10:
			to_remove.append(i)
	# Remove in reverse order
	to_remove.reverse()
	for idx in to_remove:
		patterns.remove_at(idx)

# ── Diffusion (Gauss-Seidel relaxation, 4 iterations) ───────────
func _diffuse(field: PackedFloat32Array, diff_rate: float) -> void:
	var a := diff_rate * float(CELL_COUNT)
	for _iter in range(4):
		for y in range(1, GRID_SIZE - 1):
			for x in range(1, GRID_SIZE - 1):
				var idx := y * GRID_SIZE + x
				field[idx] = (field[idx] + a * (
					field[idx - 1] + field[idx + 1] +
					field[idx - GRID_SIZE] + field[idx + GRID_SIZE]
				)) / (1.0 + 4.0 * a)

# ── Semi-Lagrangian advection ────────────────────────────────────
func _advect(field: PackedFloat32Array, vel_x: PackedFloat32Array, vel_y: PackedFloat32Array) -> void:
	# Copy field to tmp_a, write result back to field
	for i in range(CELL_COUNT):
		_tmp_a[i] = field[i]

	var dt := 1.0  # one weather tick
	for y in range(1, GRID_SIZE - 1):
		for x in range(1, GRID_SIZE - 1):
			var idx := y * GRID_SIZE + x
			# Trace back
			var src_x := float(x) - vel_x[idx] * dt
			var src_y := float(y) - vel_y[idx] * dt
			# Clamp
			src_x = clampf(src_x, 0.5, float(GRID_SIZE) - 1.5)
			src_y = clampf(src_y, 0.5, float(GRID_SIZE) - 1.5)
			# Bilinear interpolation
			var x0 := int(floor(src_x))
			var y0 := int(floor(src_y))
			var x1 := x0 + 1
			var y1 := y0 + 1
			var sx := src_x - float(x0)
			var sy := src_y - float(y0)
			field[idx] = lerpf(
				lerpf(_tmp_a[_idx(x0, y0)], _tmp_a[_idx(x1, y0)], sx),
				lerpf(_tmp_a[_idx(x0, y1)], _tmp_a[_idx(x1, y1)], sx),
				sy
			)

# ── Pressure projection (Helmholtz-Hodge decomposition) ─────────
func _project() -> void:
	# tmp_a = divergence, tmp_b = pressure
	for i in range(CELL_COUNT):
		_tmp_a[i] = 0.0
		_tmp_b[i] = 0.0

	# Compute divergence
	var h := 1.0 / float(GRID_SIZE)
	for y in range(1, GRID_SIZE - 1):
		for x in range(1, GRID_SIZE - 1):
			var idx := y * GRID_SIZE + x
			_tmp_a[idx] = -0.5 * h * (
				wind_x[idx + 1] - wind_x[idx - 1] +
				wind_y[idx + GRID_SIZE] - wind_y[idx - GRID_SIZE]
			)

	# Solve pressure (Jacobi, 4 iterations)
	for _iter in range(4):
		for y in range(1, GRID_SIZE - 1):
			for x in range(1, GRID_SIZE - 1):
				var idx := y * GRID_SIZE + x
				_tmp_b[idx] = (_tmp_a[idx] +
					_tmp_b[idx - 1] + _tmp_b[idx + 1] +
					_tmp_b[idx - GRID_SIZE] + _tmp_b[idx + GRID_SIZE]
				) / 4.0

	# Subtract pressure gradient from velocity
	for y in range(1, GRID_SIZE - 1):
		for x in range(1, GRID_SIZE - 1):
			var idx := y * GRID_SIZE + x
			wind_x[idx] -= 0.5 * float(GRID_SIZE) * (_tmp_b[idx + 1] - _tmp_b[idx - 1])
			wind_y[idx] -= 0.5 * float(GRID_SIZE) * (_tmp_b[idx + GRID_SIZE] - _tmp_b[idx - GRID_SIZE])

# ── Texture baking ───────────────────────────────────────────────
func bake_textures() -> void:
	# Wind texture: RG = wind_x, wind_y (encoded 0-1, 0.5 = zero)
	var wind_img := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGBA8)
	# Rain/fog/temp texture: R = rain, G = fog, B = temperature
	var rft_img := Image.create(GRID_SIZE, GRID_SIZE, false, Image.FORMAT_RGBA8)

	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var idx := y * GRID_SIZE + x
			# Encode wind: range [-5, 5] -> [0, 1]
			var wx_enc := clampf(wind_x[idx] / 10.0 + 0.5, 0.0, 1.0)
			var wy_enc := clampf(wind_y[idx] / 10.0 + 0.5, 0.0, 1.0)
			wind_img.set_pixel(x, y, Color(wx_enc, wy_enc, 0.0, 1.0))

			var r_val := clampf(rain[idx], 0.0, 1.0)
			var f_val := clampf(fog[idx], 0.0, 1.0)
			var t_val := clampf(temperature[idx], 0.0, 1.0)
			rft_img.set_pixel(x, y, Color(r_val, f_val, t_val, 1.0))

	if wind_texture == null:
		wind_texture = ImageTexture.create_from_image(wind_img)
	else:
		wind_texture.update(wind_img)

	if rain_fog_temp_texture == null:
		rain_fog_temp_texture = ImageTexture.create_from_image(rft_img)
	else:
		rain_fog_temp_texture.update(rft_img)

# ── CPU-side sampling ────────────────────────────────────────────
func sample_at_world(wx: float, wz: float) -> Dictionary:
	var cell := _world_to_cell(wx, wz)
	var x0 := int(floor(cell.x))
	var y0 := int(floor(cell.y))
	var x1 := mini(x0 + 1, GRID_SIZE - 1)
	var y1 := mini(y0 + 1, GRID_SIZE - 1)
	var sx := cell.x - float(x0)
	var sy := cell.y - float(y0)

	return {
		"wind_x": _bilerp(wind_x, x0, y0, x1, y1, sx, sy),
		"wind_y": _bilerp(wind_y, x0, y0, x1, y1, sx, sy),
		"rain": _bilerp(rain, x0, y0, x1, y1, sx, sy),
		"fog": _bilerp(fog, x0, y0, x1, y1, sx, sy),
		"temperature": _bilerp(temperature, x0, y0, x1, y1, sx, sy),
	}

func _bilerp(field: PackedFloat32Array, x0: int, y0: int, x1: int, y1: int, sx: float, sy: float) -> float:
	return lerpf(
		lerpf(field[_idx(x0, y0)], field[_idx(x1, y0)], sx),
		lerpf(field[_idx(x0, y1)], field[_idx(x1, y1)], sx),
		sy
	)

# ── Auto-spawn patterns ──────────────────────────────────────────
func _auto_spawn_patterns(rng: RandomNumberGenerator) -> void:
	if patterns.size() >= 4:
		return
	# ~2% chance per weather tick when below target count
	if patterns.size() < 2 or rng.randf() < 0.02:
		var preset := WeatherPresets.get_random_preset(rng)
		# Spawn at random edge position
		var edge := rng.randi() % 4
		var cx: float
		var cy: float
		match edge:
			0: # top
				cx = rng.randf() * GRID_SIZE
				cy = 0.0
			1: # right
				cx = float(GRID_SIZE - 1)
				cy = rng.randf() * GRID_SIZE
			2: # bottom
				cx = rng.randf() * GRID_SIZE
				cy = float(GRID_SIZE - 1)
			_: # left
				cx = 0.0
				cy = rng.randf() * GRID_SIZE
		spawn_pattern(preset, cx, cy)

# ── Spawn a pattern from preset ─────────────────────────────────
func spawn_pattern(preset: Dictionary, cell_x: float, cell_y: float) -> void:
	var pat := preset.duplicate(true)
	pat.cell_x = cell_x
	pat.cell_y = cell_y
	pat.age = 0.0
	patterns.append(pat)

# ── Serialization for save/load ──────────────────────────────────
func serialize() -> Dictionary:
	return {
		"wind_x": Array(wind_x),
		"wind_y": Array(wind_y),
		"rain": Array(rain),
		"fog": Array(fog),
		"temperature": Array(temperature),
		"patterns": patterns.duplicate(true),
	}

func deserialize(data: Dictionary) -> void:
	wind_x = PackedFloat32Array(data.get("wind_x", []))
	wind_y = PackedFloat32Array(data.get("wind_y", []))
	rain = PackedFloat32Array(data.get("rain", []))
	fog = PackedFloat32Array(data.get("fog", []))
	temperature = PackedFloat32Array(data.get("temperature", []))
	patterns.assign(data.get("patterns", []))
	if wind_x.size() != CELL_COUNT:
		_alloc_grids()
