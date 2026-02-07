extends Node3D

const ICON_START := 0.6
const ICON_FULL := 0.85

var _mat: StandardMaterial3D
var _selected := false
var _icon_base := Color(0.8, 0.82, 0.86)
var _icon_selected := Color(1.0, 0.95, 0.6)
var _model_path: String = ""
var _model_node: Node3D = null
var _original_colors: Dictionary = {}  # MeshInstance3D -> Color

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $Label3D
@onready var _icon: Sprite3D = $Icon

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.6, 0.6, 0.65)
	_mat.roughness = 1.0
	_mesh.material_override = _mat
	_icon.texture = _make_icon_texture(_icon_base)
	_icon.visible = false

func set_label(t: String) -> void:
	_label.text = t

func set_model(path: String) -> void:
	_model_path = path
	if path.is_empty():
		_use_fallback_mesh()
		return

	if not ResourceLoader.exists(path):
		push_warning("Model not found: %s, using fallback" % path)
		_use_fallback_mesh()
		return

	var scene = load(path) as PackedScene
	if scene == null:
		push_warning("Failed to load model: %s, using fallback" % path)
		_use_fallback_mesh()
		return

	var instance = scene.instantiate()
	if instance == null:
		push_warning("Failed to instantiate model: %s, using fallback" % path)
		_use_fallback_mesh()
		return

	# Hide the default fallback mesh and add the full model as a child
	_mesh.visible = false
	if _model_node != null:
		_model_node.queue_free()
	_model_node = instance
	_original_colors.clear()
	_cache_original_colors(_model_node)
	add_child(_model_node)

func _use_fallback_mesh() -> void:
	# Show the default mesh, remove any loaded model
	_mesh.visible = true
	if _model_node != null:
		_model_node.queue_free()
		_model_node = null
	_original_colors.clear()

func set_selected(sel: bool) -> void:
	_selected = sel
	_mat.albedo_color = Color(1.0, 0.85, 0.2) if sel else Color(0.6, 0.6, 0.65)
	_update_icon_color()
	# Also update materials on loaded model
	if _model_node != null:
		_update_model_selection(_model_node, sel)

func _cache_original_colors(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		# Handle material_override first (highest priority in Godot's material lookup)
		if mesh_inst.material_override != null and mesh_inst.material_override is StandardMaterial3D:
			var mat_copy = mesh_inst.material_override.duplicate() as StandardMaterial3D
			mesh_inst.material_override = mat_copy
			_original_colors[Vector2i(mesh_inst.get_instance_id(), -1)] = mat_copy.albedo_color
		else:
			# Handle per-surface materials
			var mesh = mesh_inst.mesh
			if mesh != null:
				var surface_count = mesh.get_surface_count()
				for surface_idx in range(surface_count):
					# Check surface override first, then fall back to mesh-embedded material
					var mat = mesh_inst.get_surface_override_material(surface_idx)
					if mat == null:
						mat = mesh.surface_get_material(surface_idx)
					if mat != null and mat is StandardMaterial3D:
						# Duplicate the material so each instance has its own copy
						# This prevents selection highlighting from affecting all tanks of the same type
						var mat_copy = mat.duplicate() as StandardMaterial3D
						mesh_inst.set_surface_override_material(surface_idx, mat_copy)
						_original_colors[Vector2i(mesh_inst.get_instance_id(), surface_idx)] = mat_copy.albedo_color
	for child in node.get_children():
		_cache_original_colors(child)

func _update_model_selection(node: Node, sel: bool) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		# Handle material_override first (index -1 in our cache)
		if mesh_inst.material_override != null and mesh_inst.material_override is StandardMaterial3D:
			var std_mat := mesh_inst.material_override as StandardMaterial3D
			var key = Vector2i(mesh_inst.get_instance_id(), -1)
			var orig = _original_colors.get(key, std_mat.albedo_color)
			if sel:
				std_mat.albedo_color = orig.lightened(0.3)
			else:
				std_mat.albedo_color = orig
		else:
			# Handle per-surface materials
			var mesh = mesh_inst.mesh
			if mesh != null:
				var surface_count = mesh.get_surface_count()
				for surface_idx in range(surface_count):
					var mat = mesh_inst.get_surface_override_material(surface_idx)
					if mat != null and mat is StandardMaterial3D:
						var std_mat := mat as StandardMaterial3D
						var key = Vector2i(mesh_inst.get_instance_id(), surface_idx)
						var orig = _original_colors.get(key, std_mat.albedo_color)
						if sel:
							std_mat.albedo_color = orig.lightened(0.3)
						else:
							std_mat.albedo_color = orig
	for child in node.get_children():
		_update_model_selection(child, sel)

func set_zoom_lod(zoom_t: float) -> void:
	var t = _smoothstep(ICON_START, ICON_FULL, zoom_t)
	var show_3d = zoom_t < 0.8
	# Show fallback mesh only if no custom model is loaded
	_mesh.visible = show_3d and _model_node == null
	if _model_node != null:
		_model_node.visible = show_3d
	_icon.visible = zoom_t > ICON_START
	_icon.modulate.a = t
	_label.visible = zoom_t <= ICON_START

func _update_icon_color() -> void:
	var c = _icon_selected if _selected else _icon_base
	_icon.modulate.r = c.r
	_icon.modulate.g = c.g
	_icon.modulate.b = c.b

func _make_icon_texture(base_color: Color) -> Texture2D:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center = Vector2(size / 2.0, size / 2.0)
	var inner = size * 0.22
	var outer = size * 0.35
	for y in range(size):
		for x in range(size):
			var d = center.distance_to(Vector2(x, y))
			if d <= inner:
				img.set_pixel(x, y, base_color)
			elif d <= outer:
				img.set_pixel(x, y, base_color.darkened(0.25))
	return ImageTexture.create_from_image(img)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
