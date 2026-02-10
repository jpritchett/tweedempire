extends Node3D
class_name HeightmapTerrain

@export var heightmap: Texture2D
@export var size_x: float = 64.0
@export var size_z: float = 64.0
@export var height_scale: float = 8.0
@export var subdivisions_x: int = 127
@export var subdivisions_z: int = 127

## Mandelbrot heightmap generation
@export_group("Mandelbrot Generation")
@export var use_mandelbrot: bool = false
@export var mandelbrot_preset: String = "seahorse_valley"
@export var mandelbrot_resolution: int = 512
@export var mandelbrot_max_iterations: int = 512
@export var mandelbrot_exponent: float = 2.0
@export var mandelbrot_invert: bool = false

## UK terrain generation
@export_group("UK Terrain Generation")
@export var use_uk_terrain: bool = false
@export var uk_preset: String = "peak_district"
@export var uk_resolution: int = 512
@export var uk_seed: int = 42

## Terrain shader
@export_group("Terrain Material")
@export var use_terrain_shader: bool = true

## Water plane
@export_group("Water")
@export var water_enabled: bool = true
@export var water_level: float = 0.18  # normalised height (0-1)

var _image: Image
var _mesh_instance: MeshInstance3D
var _water_instance: MeshInstance3D

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

	# Generate heightmap (UK terrain takes priority over Mandelbrot)
	if use_uk_terrain:
		_generate_uk_heightmap()
	elif use_mandelbrot:
		_generate_mandelbrot_heightmap()

	_generate()
	# Add a simple collider (trimesh) for mouse picking
	var body := StaticBody3D.new()
	add_child(body)
	var col := CollisionShape3D.new()
	body.add_child(col)
	col.shape = _mesh_instance.mesh.create_trimesh_shape()

	# Water plane
	if water_enabled:
		_create_water_plane()

func _generate_mandelbrot_heightmap() -> void:
	var generator := MandelbrotHeightmap.new()
	generator.resolution = Vector2i(mandelbrot_resolution, mandelbrot_resolution)
	generator.max_iterations = mandelbrot_max_iterations
	generator.height_exponent = mandelbrot_exponent
	generator.invert_height = mandelbrot_invert
	generator.use_preset(mandelbrot_preset)

	var img := generator.generate()
	heightmap = ImageTexture.create_from_image(img)

func _generate_uk_heightmap() -> void:
	var generator := UKHeightmap.new()
	generator.resolution = Vector2i(uk_resolution, uk_resolution)
	generator.seed_value = uk_seed
	generator.use_preset(uk_preset)

	var img := generator.generate()
	heightmap = ImageTexture.create_from_image(img)

func _generate() -> void:
	if heightmap == null:
		push_warning("HeightmapTerrain: heightmap not set")
		return
	_image = heightmap.get_image()
	_image.decompress()
	_image.convert(Image.FORMAT_L8)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var w := subdivisions_x + 1
	var h := subdivisions_z + 1

	for z in range(h-1):
		for x in range(w-1):
			# Create two triangles per quad
			var p00 = _vertex_world(x, z)
			var p10 = _vertex_world(x+1, z)
			var p01 = _vertex_world(x, z+1)
			var p11 = _vertex_world(x+1, z+1)

			var uv00 = Vector2(float(x)/float(w-1), float(z)/float(h-1))
			var uv10 = Vector2(float(x+1)/float(w-1), float(z)/float(h-1))
			var uv01 = Vector2(float(x)/float(w-1), float(z+1)/float(h-1))
			var uv11 = Vector2(float(x+1)/float(w-1), float(z+1)/float(h-1))

			# Tri 1: p00, p10, p11
			st.set_uv(uv00); st.add_vertex(p00)
			st.set_uv(uv10); st.add_vertex(p10)
			st.set_uv(uv11); st.add_vertex(p11)
			# Tri 2: p00, p11, p01
			st.set_uv(uv00); st.add_vertex(p00)
			st.set_uv(uv11); st.add_vertex(p11)
			st.set_uv(uv01); st.add_vertex(p01)

	# Normals
	st.generate_normals()
	_mesh_instance.mesh = st.commit()

	# Apply material
	if use_terrain_shader:
		_apply_terrain_shader()
	else:
		_apply_simple_material()

func _apply_simple_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.35, 0.18)
	mat.albedo_texture = _make_terrain_texture()
	mat.roughness = 1.0
	mat.uv1_scale = Vector3(8.0, 8.0, 1.0)
	_mesh_instance.material_override = mat

func _apply_terrain_shader() -> void:
	var shader := load("res://src/terrain/terrain_shader.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader

	# Generate procedural biome textures
	mat.set_shader_parameter("peat_texture", _make_peat_texture())
	mat.set_shader_parameter("meadow_texture", _make_meadow_texture())
	mat.set_shader_parameter("woodland_texture", _make_woodland_texture())
	mat.set_shader_parameter("moorland_texture", _make_moorland_texture())
	mat.set_shader_parameter("rock_texture", _make_rock_texture())

	# Texture tiling — scale with terrain size so detail density stays consistent
	var tile_size := 8.0
	mat.set_shader_parameter("texture_tile_size", tile_size)

	# Height range for blending
	mat.set_shader_parameter("height_min", 0.0)
	mat.set_shader_parameter("height_max", height_scale)

	# Default weather texture (no rain, no fog, mild temperature 0.5)
	var weather_img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	weather_img.fill(Color(0.0, 0.0, 0.5, 1.0))  # R=rain=0, G=fog=0, B=temp=0.5
	mat.set_shader_parameter("weather_rain_fog_tex", ImageTexture.create_from_image(weather_img))
	mat.set_shader_parameter("weather_world_size", Vector2(size_x, size_z))

	_mesh_instance.material_override = mat

func _create_water_plane() -> void:
	var water_y := water_level * height_scale
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(size_x * 10.0, size_z * 10.0)
	water_mesh.subdivide_width = 512
	water_mesh.subdivide_depth = 512
	_water_instance = MeshInstance3D.new()
	_water_instance.mesh = water_mesh
	_water_instance.position = Vector3(size_x * 0.5, water_y, size_z * 0.5)
	add_child(_water_instance)

	var shader := load("res://src/terrain/water_shader.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_water_instance.material_override = mat

func _vertex_world(ix: int, iz: int) -> Vector3:
	var x = (float(ix) / float(subdivisions_x)) * size_x
	var z = (float(iz) / float(subdivisions_z)) * size_z
	var y = sample_height_world(x, z)
	return Vector3(x, y, z)

func sample_height_world(wx: float, wz: float) -> float:
	# Map world x/z to heightmap pixel coordinates
	if _image == null:
		return 0.0
	var u: float = clampf(wx / size_x, 0.0, 1.0)
	var v: float = clampf(wz / size_z, 0.0, 1.0)
	var px := int(round(u * float(_image.get_width() - 1)))
	var py := int(round(v * float(_image.get_height() - 1)))
	var c := _image.get_pixel(px, py).r # 0..1 in L8
	return c * height_scale

func world_bounds() -> Rect2:
	return Rect2(Vector2(0,0), Vector2(size_x, size_z))

# --- Procedural biome textures ---

func _make_terrain_texture() -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var a := Color(0.12, 0.3, 0.15)
	var b := Color(0.22, 0.42, 0.22)
	for y in range(size):
		for x in range(size):
			var n = noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			img.set_pixel(x, y, a.lerp(b, n))
	return ImageTexture.create_from_image(img)

func _make_peat_texture() -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 4001
	noise.frequency = 0.06
	noise.fractal_octaves = 4
	var noise2 := FastNoiseLite.new()
	noise2.seed = 4002
	noise2.frequency = 0.14
	noise2.fractal_octaves = 2
	var base := Color(0.12, 0.08, 0.05)
	var light := Color(0.18, 0.12, 0.08)
	var dark := Color(0.06, 0.04, 0.03)
	for y in range(size):
		for x in range(size):
			var n1 := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var n2 := noise2.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var c := base.lerp(light, n1 * 0.5)
			c = c.lerp(dark, n2 * 0.35)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_meadow_texture() -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 4010
	noise.frequency = 0.06
	noise.fractal_octaves = 4
	var noise2 := FastNoiseLite.new()
	noise2.seed = 4011
	noise2.frequency = 0.15
	noise2.fractal_octaves = 2
	var base := Color(0.22, 0.45, 0.12)
	var highlight := Color(0.32, 0.55, 0.15)
	var yellow_green := Color(0.38, 0.48, 0.10)
	for y in range(size):
		for x in range(size):
			var n1 := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var n2 := noise2.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var c := base.lerp(highlight, n1 * 0.6)
			c = c.lerp(yellow_green, n2 * 0.25)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_woodland_texture() -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 4020
	noise.frequency = 0.05
	noise.fractal_octaves = 5
	var noise2 := FastNoiseLite.new()
	noise2.seed = 4021
	noise2.frequency = 0.12
	noise2.fractal_octaves = 3
	var base := Color(0.10, 0.30, 0.08)
	var canopy := Color(0.15, 0.38, 0.10)
	var shadow := Color(0.06, 0.20, 0.05)
	for y in range(size):
		for x in range(size):
			var n1 := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var n2 := noise2.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var c := base.lerp(canopy, n1 * 0.5)
			c = c.lerp(shadow, n2 * 0.4)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_moorland_texture() -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 4030
	noise.frequency = 0.05
	noise.fractal_octaves = 4
	var noise2 := FastNoiseLite.new()
	noise2.seed = 4031
	noise2.frequency = 0.10
	noise2.fractal_octaves = 3
	var noise3 := FastNoiseLite.new()
	noise3.seed = 4032
	noise3.frequency = 0.18
	noise3.fractal_octaves = 2
	var heather := Color(0.35, 0.22, 0.25)
	var bracken := Color(0.50, 0.40, 0.20)
	var tawny := Color(0.42, 0.32, 0.18)
	for y in range(size):
		for x in range(size):
			var n1 := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var n2 := noise2.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var n3 := noise3.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var c := heather.lerp(bracken, n1 * 0.5)
			c = c.lerp(tawny, n2 * 0.35)
			# Occasional green patches in the moorland
			c = c.lerp(Color(0.18, 0.32, 0.12), n3 * 0.15)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_rock_texture() -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 4040
	noise.frequency = 0.04
	noise.fractal_octaves = 5
	var noise2 := FastNoiseLite.new()
	noise2.seed = 4041
	noise2.frequency = 0.12
	noise2.fractal_octaves = 3
	# Warm gritstone grey (millstone grit character)
	var base := Color(0.40, 0.38, 0.35)
	var light := Color(0.55, 0.52, 0.48)
	var dark := Color(0.25, 0.23, 0.22)
	for y in range(size):
		for x in range(size):
			var n1 := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var n2 := noise2.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var c := base.lerp(light, n1 * 0.5)
			c = c.lerp(dark, n2 * 0.4)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func get_terrain_material() -> ShaderMaterial:
	if _mesh_instance == null:
		return null
	return _mesh_instance.material_override as ShaderMaterial

func get_water_material() -> ShaderMaterial:
	if _water_instance == null:
		return null
	return _water_instance.material_override as ShaderMaterial
