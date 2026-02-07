extends Node3D

const ICON_START := 0.6
const ICON_FULL := 0.85

var _mat: StandardMaterial3D
var _selected := false
var _icon_base := Color(0.9, 0.78, 0.5)
var _icon_selected := Color(1.0, 0.9, 0.65)

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $Label3D
@onready var _icon: Sprite3D = $Icon

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.35, 0.35, 0.4)
	_mat.roughness = 1.0
	_mesh.material_override = _mat
	_icon.texture = _make_icon_texture(_icon_base)
	_icon.visible = false

func set_label(t: String) -> void:
	_label.text = t

func set_selected(sel: bool) -> void:
	_selected = sel
	_mat.albedo_color = Color(0.9, 0.6, 0.2) if sel else Color(0.35, 0.35, 0.4)
	_update_icon_color()

func set_size(size_x: float, size_z: float) -> void:
	(_mesh.mesh as BoxMesh).size = Vector3(size_x, 0.9, size_z)

func set_zoom_lod(zoom_t: float) -> void:
	var t = _smoothstep(ICON_START, ICON_FULL, zoom_t)
	_mesh.visible = zoom_t < 0.8
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
	var inner = size * 0.24
	var outer = size * 0.38
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
