extends Node3D

@export var footprint := Vector2i(2, 2)
@export var cell_size: float = 1.0

@onready var mesh: MeshInstance3D = $MeshInstance3D

func set_valid(is_valid: bool) -> void:
	var m: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.2, 0.9, 0.2, 0.35)
		m.roughness = 1.0
		mesh.material_override = m
	m.albedo_color = Color(0.2, 0.9, 0.2, 0.35) if is_valid else Color(0.9, 0.2, 0.2, 0.35)

func set_size_from_footprint() -> void:
	$MeshInstance3D.mesh.size = Vector3(float(footprint.x) * cell_size, 0.3, float(footprint.y) * cell_size)
	$Decal.size = Vector3(float(footprint.x) * cell_size, 0.2, float(footprint.y) * cell_size)
