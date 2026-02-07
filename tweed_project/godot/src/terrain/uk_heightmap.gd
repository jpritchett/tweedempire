extends RefCounted
class_name UKHeightmap

## Generates heightmap images inspired by central UK terrain.
## Uses layered noise to create rolling hills, ridges, and valleys
## reminiscent of the Peak District / Pennines.

## Output resolution
var resolution: Vector2i = Vector2i(512, 512)

## Noise parameters
var base_frequency: float = 0.004
var ridge_frequency: float = 0.008
var valley_frequency: float = 0.003
var detail_frequency: float = 0.03

var base_amplitude: float = 0.6
var ridge_strength: float = 0.25
var valley_depth: float = 0.2
var detail_amplitude: float = 0.08

## Post-processing
var height_exponent: float = 1.8
var height_ceiling: float = 1.0  # max output height (scales down peaks)

## Seed for reproducibility
var seed_value: int = 42

## Preset configurations
const PRESETS := {
	"peak_district": {
		"base_frequency": 0.004,
		"ridge_frequency": 0.008,
		"ridge_strength": 0.18,
		"valley_depth": 0.15,
		"detail_amplitude": 0.05,
		"height_exponent": 1.3,
		"height_ceiling": 0.72,
		"description": "Rolling hills with gentle ridges"
	},
	"midlands": {
		"base_frequency": 0.003,
		"ridge_frequency": 0.006,
		"ridge_strength": 0.10,
		"valley_depth": 0.10,
		"detail_amplitude": 0.05,
		"height_exponent": 1.4,
		"description": "Gentle rolling farmland"
	},
	"pennine_dales": {
		"base_frequency": 0.005,
		"ridge_frequency": 0.010,
		"ridge_strength": 0.20,
		"valley_depth": 0.35,
		"detail_amplitude": 0.10,
		"height_exponent": 2.0,
		"description": "Deep V-shaped valleys with broad ridges"
	}
}

## Apply a preset
func use_preset(preset_name: String) -> void:
	if PRESETS.has(preset_name):
		var p = PRESETS[preset_name]
		base_frequency = p["base_frequency"]
		ridge_frequency = p["ridge_frequency"]
		ridge_strength = p["ridge_strength"]
		valley_depth = p["valley_depth"]
		detail_amplitude = p["detail_amplitude"]
		height_exponent = p["height_exponent"]
		height_ceiling = p.get("height_ceiling", 1.0)
	else:
		push_warning("UKHeightmap: Unknown preset '%s'" % preset_name)

## Generate the heightmap image
func generate() -> Image:
	var img := Image.create(resolution.x, resolution.y, false, Image.FORMAT_RF)

	# Set up noise layers
	var base_noise := FastNoiseLite.new()
	base_noise.seed = seed_value
	base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base_noise.frequency = base_frequency
	base_noise.fractal_octaves = 4
	base_noise.fractal_lacunarity = 2.0
	base_noise.fractal_gain = 0.5

	var ridge_noise := FastNoiseLite.new()
	ridge_noise.seed = seed_value + 100
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge_noise.frequency = ridge_frequency
	ridge_noise.fractal_octaves = 3
	ridge_noise.fractal_lacunarity = 2.2
	ridge_noise.fractal_gain = 0.45

	var valley_noise := FastNoiseLite.new()
	valley_noise.seed = seed_value + 200
	valley_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	valley_noise.frequency = valley_frequency
	valley_noise.fractal_octaves = 2
	valley_noise.fractal_lacunarity = 2.0
	valley_noise.fractal_gain = 0.5

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = seed_value + 300
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = detail_frequency
	detail_noise.fractal_octaves = 3
	detail_noise.fractal_lacunarity = 2.5
	detail_noise.fractal_gain = 0.4

	# Warp noise for natural-looking distortion
	var warp_noise := FastNoiseLite.new()
	warp_noise.seed = seed_value + 400
	warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp_noise.frequency = 0.002
	warp_noise.fractal_octaves = 2

	var raw_heights: Array[float] = []
	raw_heights.resize(resolution.x * resolution.y)

	var min_height := INF
	var max_height := -INF

	# First pass: compute raw heights
	for py in range(resolution.y):
		for px in range(resolution.x):
			var fx := float(px)
			var fy := float(py)

			# Domain warp for more organic shapes
			var warp_x := warp_noise.get_noise_2d(fx, fy) * 40.0
			var warp_y := warp_noise.get_noise_2d(fx + 500.0, fy + 500.0) * 40.0
			var wx := fx + warp_x
			var wy := fy + warp_y

			# Base rolling hills (0 to 1 range from noise -1..1)
			var base := (base_noise.get_noise_2d(wx, wy) * 0.5 + 0.5) * base_amplitude

			# Ridged noise: 1.0 - abs(noise) creates sharp ridges
			var ridge_raw := ridge_noise.get_noise_2d(wx, wy)
			var ridge := (1.0 - absf(ridge_raw)) * ridge_strength

			# Valley carving: where valley noise is low, push terrain down
			var valley_raw := valley_noise.get_noise_2d(fx, fy) * 0.5 + 0.5
			var valley_mask := clampf(valley_raw, 0.0, 1.0)
			# Sharpen the valley mask so valleys are narrower
			valley_mask = valley_mask * valley_mask
			var valley := (1.0 - valley_mask) * valley_depth

			# Fine detail
			var detail := (detail_noise.get_noise_2d(wx, wy) * 0.5 + 0.5) * detail_amplitude

			# Combine layers
			var height := base + ridge - valley + detail

			var idx := py * resolution.x + px
			raw_heights[idx] = height
			min_height = minf(min_height, height)
			max_height = maxf(max_height, height)

	# Second pass: normalise and apply post-processing
	var height_range := max_height - min_height
	if height_range < 0.0001:
		height_range = 1.0

	# Edge falloff: slope terrain below water near map borders
	# edge_margin is in pixels — terrain within this margin slopes to 0
	var edge_margin := int(resolution.x * 0.08)  # 8% of map width

	for py in range(resolution.y):
		for px in range(resolution.x):
			var idx := py * resolution.x + px
			var height := raw_heights[idx]

			# Normalise to 0-1
			height = (height - min_height) / height_range

			# Power curve to push peaks higher and valleys deeper
			height = pow(height, height_exponent)

			# Scale down so peaks don't reach full rock zone
			height *= height_ceiling

			# Edge falloff: smoothly ramp down near borders
			var dist_left := px
			var dist_right := resolution.x - 1 - px
			var dist_top := py
			var dist_bottom := resolution.y - 1 - py
			var dist_edge := mini(mini(dist_left, dist_right), mini(dist_top, dist_bottom))
			if dist_edge < edge_margin:
				var t := float(dist_edge) / float(edge_margin)
				# Smoothstep for a natural-looking slope
				t = t * t * (3.0 - 2.0 * t)
				# Ramp from -0.05 (below water) up to the actual height
				height = lerpf(-0.05, height, t)

			img.set_pixel(px, py, Color(height, height, height, 1.0))

	return img

## Generate and save to file
func generate_to_file(path: String) -> Error:
	var img := generate()
	var ext := path.get_extension().to_lower()
	match ext:
		"png":
			return img.save_png(path)
		"exr":
			return img.save_exr(path, false)
		_:
			push_warning("UKHeightmap: Unknown format '%s', saving as PNG" % ext)
			return img.save_png(path)

## Create a texture from the heightmap
func generate_texture() -> ImageTexture:
	var img := generate()
	return ImageTexture.create_from_image(img)

## Get a list of available preset names
static func get_preset_names() -> Array[String]:
	var names: Array[String] = []
	for k in PRESETS.keys():
		names.append(k)
	return names

## Get description for a preset
static func get_preset_description(preset_name: String) -> String:
	if PRESETS.has(preset_name):
		return PRESETS[preset_name]["description"]
	return ""
