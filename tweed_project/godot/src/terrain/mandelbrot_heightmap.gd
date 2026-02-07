extends RefCounted
class_name MandelbrotHeightmap

## Generates heightmap images from the Mandelbrot set.
## The fractal's natural structure creates interesting terrain with
## valleys, ridges, and varied detail.

## Complex plane window (which region of the Mandelbrot set to render)
var region_min: Vector2 = Vector2(-0.77, 0.05)  # Seahorse Valley default
var region_max: Vector2 = Vector2(-0.73, 0.12)

## Maximum iterations before considering a point "inside" the set
var max_iterations: int = 512

## Height post-processing
var height_exponent: float = 2.0  # Power curve to emphasise extremes
var use_smooth_iteration: bool = true  # Smooth iteration count to avoid terracing
var invert_height: bool = false  # Invert so "inside" points become peaks

## Output resolution
var resolution: Vector2i = Vector2i(512, 512)

## Preset regions for interesting terrain
const PRESETS := {
	"seahorse_valley": {
		"min": Vector2(-0.77, 0.05),
		"max": Vector2(-0.73, 0.12),
		"description": "Classic area with spirals and varied detail"
	},
	"elephant_valley": {
		"min": Vector2(0.25, 0.0),
		"max": Vector2(0.40, 0.15),
		"description": "Elephant trunk shapes with rolling terrain"
	},
	"antenna_tip": {
		"min": Vector2(-1.790, -0.01),
		"max": Vector2(-1.740, 0.04),
		"description": "Sharp peaks and deep valleys at the antenna"
	},
	"mini_brot": {
		"min": Vector2(-0.1012, 0.9555),
		"max": Vector2(-0.0988, 0.9580),
		"description": "Miniature Mandelbrot with surrounding detail"
	},
	"spiral_arms": {
		"min": Vector2(-0.745, 0.11),
		"max": Vector2(-0.735, 0.12),
		"description": "Tight spirals creating ridge-like terrain"
	},
	"full_set": {
		"min": Vector2(-2.5, -1.5),
		"max": Vector2(1.0, 1.5),
		"description": "The complete Mandelbrot set (less interesting as terrain)"
	}
}

## Apply a preset region
func use_preset(preset_name: String) -> void:
	if PRESETS.has(preset_name):
		var preset = PRESETS[preset_name]
		region_min = preset["min"]
		region_max = preset["max"]
	else:
		push_warning("MandelbrotHeightmap: Unknown preset '%s'" % preset_name)

## Generate the heightmap image
func generate() -> Image:
	var img := Image.create(resolution.x, resolution.y, false, Image.FORMAT_RF)

	var raw_heights: Array[float] = []
	raw_heights.resize(resolution.x * resolution.y)

	var min_height := INF
	var max_height := -INF

	# First pass: compute raw iteration values
	for py in range(resolution.y):
		for px in range(resolution.x):
			var u := float(px) / float(resolution.x - 1)
			var v := float(py) / float(resolution.y - 1)

			# Map UV to complex plane coordinates
			var c_real := lerpf(region_min.x, region_max.x, u)
			var c_imag := lerpf(region_min.y, region_max.y, v)

			var height := _compute_height(c_real, c_imag)

			var idx := py * resolution.x + px
			raw_heights[idx] = height

			min_height = minf(min_height, height)
			max_height = maxf(max_height, height)

	# Second pass: normalise and apply post-processing
	var height_range := max_height - min_height
	if height_range < 0.0001:
		height_range = 1.0  # Avoid division by zero

	for py in range(resolution.y):
		for px in range(resolution.x):
			var idx := py * resolution.x + px
			var height := raw_heights[idx]

			# Normalise to 0-1
			height = (height - min_height) / height_range

			# Apply power curve to emphasise extremes
			height = pow(height, height_exponent)

			# Optionally invert
			if invert_height:
				height = 1.0 - height

			img.set_pixel(px, py, Color(height, height, height, 1.0))

	return img

## Compute the height value for a point in the complex plane
func _compute_height(c_real: float, c_imag: float) -> float:
	var z_real := 0.0
	var z_imag := 0.0
	var iteration := 0

	# Mandelbrot iteration: z = z² + c
	while iteration < max_iterations:
		var z_real_sq := z_real * z_real
		var z_imag_sq := z_imag * z_imag

		# Check escape condition (|z|² > 4)
		if z_real_sq + z_imag_sq > 4.0:
			break

		# z = z² + c
		var new_real := z_real_sq - z_imag_sq + c_real
		z_imag = 2.0 * z_real * z_imag + c_imag
		z_real = new_real

		iteration += 1

	if iteration == max_iterations:
		# Point is inside the set - return lowest value
		return 0.0

	if use_smooth_iteration:
		# Smooth iteration count to avoid terracing
		# Formula: n - log2(log2(|z|))
		var z_mag_sq := z_real * z_real + z_imag * z_imag
		var log_zn := log(z_mag_sq) / 2.0  # log(|z|)
		var nu := log(log_zn / log(2.0)) / log(2.0)
		return float(iteration) + 1.0 - nu
	else:
		return float(iteration)

## Generate and save to file
func generate_to_file(path: String) -> Error:
	var img := generate()

	# Determine format from extension
	var ext := path.get_extension().to_lower()
	match ext:
		"png":
			return img.save_png(path)
		"exr":
			return img.save_exr(path, false)  # false = don't use 16-bit grayscale
		_:
			push_warning("MandelbrotHeightmap: Unknown format '%s', saving as PNG" % ext)
			return img.save_png(path)

## Create a texture from the heightmap
func generate_texture() -> ImageTexture:
	var img := generate()
	return ImageTexture.create_from_image(img)

## Get a list of available preset names
static func get_preset_names() -> Array[String]:
	var names: Array[String] = []
	for key in PRESETS.keys():
		names.append(key)
	return names

## Get description for a preset
static func get_preset_description(preset_name: String) -> String:
	if PRESETS.has(preset_name):
		return PRESETS[preset_name]["description"]
	return ""
