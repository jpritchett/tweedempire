extends Node3D
class_name TerrainVegetation

## Reference to the heightmap terrain (must be set before adding to tree)
var terrain: HeightmapTerrain

## Random seed for deterministic placement
var seed_value: int = 123

# Biome height thresholds (normalised 0-1, matching terrain_shader.gdshader)
const WATER_LEVEL := 0.22  # above actual water (0.18) to keep vegetation clear of shoreline
const PEAT_UPPER := 0.12
const MEADOW_UPPER := 0.45
const WOODLAND_UPPER := 0.65
const MOORLAND_UPPER := 0.88
const SLOPE_THRESHOLD := 0.65

# Layer spacing (world units between candidate points)
const LARGE_TREE_SPACING := 4.0
const SMALL_TREE_SPACING := 3.0
const GRASS_SPACING := 1.5
const FLOWER_SPACING := 2.0

func _ready() -> void:
	if terrain == null:
		push_error("TerrainVegetation: terrain not set")
		return
	generate()

func generate() -> void:
	# Large trees
	var large_mesh := _make_tree_mesh(1.2, 0.12, 1.6, 0.9, Color(0.25, 0.16, 0.08), Color(0.12, 0.32, 0.08))
	var large_mat := _make_opaque_material()
	_generate_layer(LARGE_TREE_SPACING, large_mesh, large_mat, _biome_large_tree, 0)

	# Small trees / bushes
	var small_mesh := _make_tree_mesh(0.5, 0.06, 0.9, 0.55, Color(0.28, 0.18, 0.08), Color(0.18, 0.38, 0.10))
	var small_mat := _make_opaque_material()
	_generate_layer(SMALL_TREE_SPACING, small_mesh, small_mat, _biome_small_tree, 100)

	# Grass clumps
	var grass_mesh := _make_cross_billboard(0.5, 0.4, Color(0.22, 0.42, 0.12))
	var grass_mat := _make_opaque_material()
	_generate_layer(GRASS_SPACING, grass_mesh, grass_mat, _biome_grass, 200)

	# Wildflowers
	var flower_mesh := _make_cross_billboard(0.3, 0.3, Color(0.45, 0.35, 0.55))
	var flower_mat := _make_opaque_material()
	_generate_layer(FLOWER_SPACING, flower_mesh, flower_mat, _biome_flower, 300)

# ─── Layer generation ──────────────────────────────────────────────────────────

func _generate_layer(spacing: float, mesh: Mesh, material: Material, biome_func: Callable, seed_offset: int) -> void:
	var jitter_noise := FastNoiseLite.new()
	jitter_noise.seed = seed_value + seed_offset
	jitter_noise.frequency = 0.15
	jitter_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	var threshold_noise := FastNoiseLite.new()
	threshold_noise.seed = seed_value + seed_offset + 50
	threshold_noise.frequency = 0.08
	threshold_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	var transforms: Array[Transform3D] = []

	var sx := terrain.size_x
	var sz := terrain.size_z
	var hs := terrain.height_scale
	var water_y := terrain.water_level * hs + 0.5  # world-space water height + buffer

	var wx := 1.0
	while wx < sx - 1.0:
		var wz := 1.0
		while wz < sz - 1.0:
			# Jitter position
			var jx := jitter_noise.get_noise_2d(wx, wz) * spacing * 0.45
			var jz := jitter_noise.get_noise_2d(wx + 1000.0, wz + 1000.0) * spacing * 0.45
			var px := wx + jx
			var pz := wz + jz

			if px < 0.5 or px > sx - 0.5 or pz < 0.5 or pz > sz - 0.5:
				wz += spacing
				continue

			var py := terrain.sample_height_world(px, pz)
			# Skip anything at or below water surface
			if py < water_y:
				wz += spacing
				continue
			var h_norm := py / hs

			var slope := _calc_slope(px, pz)
			var prob: float = biome_func.call(h_norm, slope)

			if prob > 0.0:
				# Use threshold noise to decide placement
				var t := (threshold_noise.get_noise_2d(px * 3.7, pz * 3.7) + 1.0) * 0.5  # 0..1
				if t < prob:
					# Random-ish rotation and scale from noise
					var rot := (jitter_noise.get_noise_2d(px * 7.1, pz * 7.1) + 1.0) * PI
					var scl := 0.7 + (jitter_noise.get_noise_2d(px * 11.3, pz * 11.3) + 1.0) * 0.3  # 0.7 - 1.3

					var xform := Transform3D.IDENTITY
					xform = xform.scaled(Vector3(scl, scl, scl))
					xform = xform.rotated(Vector3.UP, rot)
					xform.origin = Vector3(px, py, pz)
					transforms.append(xform)

			wz += spacing
		wx += spacing

	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	mm.mesh = mesh

	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

# ─── Slope calculation ─────────────────────────────────────────────────────────

func _calc_slope(wx: float, wz: float) -> float:
	var d := 0.5
	var h_c := terrain.sample_height_world(wx, wz)
	var h_r := terrain.sample_height_world(wx + d, wz)
	var h_u := terrain.sample_height_world(wx, wz + d)
	var dx := (h_r - h_c) / d
	var dz := (h_u - h_c) / d
	var normal := Vector3(-dx, 1.0, -dz).normalized()
	return normal.dot(Vector3.UP)  # 1.0 = flat, 0.0 = vertical

# ─── Biome probability functions ───────────────────────────────────────────────

func _biome_large_tree(h_norm: float, slope: float) -> float:
	if slope < SLOPE_THRESHOLD or h_norm < WATER_LEVEL:
		return 0.0
	if h_norm < MEADOW_UPPER:
		return 0.12
	if h_norm < WOODLAND_UPPER:
		return 0.80
	if h_norm < MOORLAND_UPPER:
		return 0.02
	return 0.0

func _biome_small_tree(h_norm: float, slope: float) -> float:
	if slope < SLOPE_THRESHOLD or h_norm < WATER_LEVEL:
		return 0.0
	if h_norm < MEADOW_UPPER:
		return 0.20
	if h_norm < WOODLAND_UPPER:
		return 0.55
	if h_norm < WOODLAND_UPPER + 0.10:
		return 0.12
	return 0.0

func _biome_grass(h_norm: float, slope: float) -> float:
	if h_norm < WATER_LEVEL:
		return 0.0
	if slope < SLOPE_THRESHOLD:
		return 0.0
	if h_norm < MEADOW_UPPER:
		return 0.75
	if h_norm < WOODLAND_UPPER:
		return 0.30
	if h_norm < MOORLAND_UPPER:
		return 0.35
	return 0.0

func _biome_flower(h_norm: float, slope: float) -> float:
	if slope < SLOPE_THRESHOLD or h_norm < WATER_LEVEL:
		return 0.0
	if h_norm < MEADOW_UPPER:
		return 0.40
	if h_norm < WOODLAND_UPPER:
		return 0.15
	if h_norm < MOORLAND_UPPER:
		return 0.25
	return 0.0

# ─── Procedural mesh builders ─────────────────────────────────────────────────

func _make_tree_mesh(trunk_h: float, trunk_r: float, canopy_h: float, canopy_r: float, trunk_col: Color, canopy_col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Trunk — cylinder approximation (8 sides)
	var segments := 8
	_add_cylinder(st, trunk_r, trunk_r * 0.8, trunk_h, 0.0, segments, trunk_col)

	# Canopy — cone (top_radius = 0)
	_add_cylinder(st, canopy_r, 0.02, canopy_h, trunk_h, segments, canopy_col)

	st.generate_normals()
	return st.commit()

func _add_cylinder(st: SurfaceTool, bottom_r: float, top_r: float, height: float, y_offset: float, segments: int, col: Color) -> void:
	for i in segments:
		var a0 := float(i) / float(segments) * TAU
		var a1 := float(i + 1) / float(segments) * TAU
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)

		# Bottom triangle
		var b0 := Vector3(c0 * bottom_r, y_offset, s0 * bottom_r)
		var b1 := Vector3(c1 * bottom_r, y_offset, s1 * bottom_r)
		# Top triangle
		var t0 := Vector3(c0 * top_r, y_offset + height, s0 * top_r)
		var t1 := Vector3(c1 * top_r, y_offset + height, s1 * top_r)

		# Side quad as two triangles
		st.set_color(col)
		st.add_vertex(b0)
		st.set_color(col)
		st.add_vertex(t0)
		st.set_color(col)
		st.add_vertex(b1)

		st.set_color(col)
		st.add_vertex(b1)
		st.set_color(col)
		st.add_vertex(t0)
		st.set_color(col)
		st.add_vertex(t1)

	# Bottom cap
	var center_bottom := Vector3(0, y_offset, 0)
	for i in segments:
		var a0 := float(i) / float(segments) * TAU
		var a1 := float(i + 1) / float(segments) * TAU
		st.set_color(col)
		st.add_vertex(center_bottom)
		st.set_color(col)
		st.add_vertex(Vector3(cos(a1) * bottom_r, y_offset, sin(a1) * bottom_r))
		st.set_color(col)
		st.add_vertex(Vector3(cos(a0) * bottom_r, y_offset, sin(a0) * bottom_r))

	# Top cap
	var center_top := Vector3(0, y_offset + height, 0)
	for i in segments:
		var a0 := float(i) / float(segments) * TAU
		var a1 := float(i + 1) / float(segments) * TAU
		st.set_color(col)
		st.add_vertex(center_top)
		st.set_color(col)
		st.add_vertex(Vector3(cos(a0) * top_r, y_offset + height, sin(a0) * top_r))
		st.set_color(col)
		st.add_vertex(Vector3(cos(a1) * top_r, y_offset + height, sin(a1) * top_r))

func _make_cross_billboard(width: float, height: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw := width * 0.5

	# Quad 1 — aligned along X
	var col_top := col.lightened(0.15)
	var col_base := col.darkened(0.2)

	_add_tapered_quad(st, Vector3(-hw, 0, 0), Vector3(hw, 0, 0), height, col_base, col_top)

	# Quad 2 — aligned along Z (rotated 90°)
	_add_tapered_quad(st, Vector3(0, 0, -hw), Vector3(0, 0, hw), height, col_base, col_top)

	st.generate_normals()
	return st.commit()

func _add_tapered_quad(st: SurfaceTool, bl: Vector3, br: Vector3, height: float, col_bottom: Color, col_top: Color) -> void:
	# Tapered — top edge is narrower for a grass-blade look
	var taper := 0.3
	var dir := (br - bl)
	var center := (bl + br) * 0.5
	var half_top := dir * taper * 0.5
	var tl := center + Vector3(0, height, 0) - half_top
	var tr := center + Vector3(0, height, 0) + half_top

	# Front face
	st.set_color(col_bottom)
	st.add_vertex(bl)
	st.set_color(col_top)
	st.add_vertex(tl)
	st.set_color(col_bottom)
	st.add_vertex(br)

	st.set_color(col_bottom)
	st.add_vertex(br)
	st.set_color(col_top)
	st.add_vertex(tl)
	st.set_color(col_top)
	st.add_vertex(tr)

	# Back face (reversed winding)
	st.set_color(col_bottom)
	st.add_vertex(br)
	st.set_color(col_top)
	st.add_vertex(tl)
	st.set_color(col_bottom)
	st.add_vertex(bl)

	st.set_color(col_bottom)
	st.add_vertex(tr)
	st.set_color(col_top)
	st.add_vertex(tl)
	st.set_color(col_bottom)
	st.add_vertex(br)

func _make_opaque_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
