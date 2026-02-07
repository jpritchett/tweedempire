extends Node3D
## Visual representation of an enemy entity.
## Dark spiky mesh, health bar, death animation.

const ICON_START := 0.6
const ICON_FULL := 0.85

var _mat: StandardMaterial3D
var _selected := false
var _icon_base := Color(0.9, 0.3, 0.3)      # Red for enemies
var _icon_selected := Color(1.0, 0.6, 0.6)
var _hp_bar_mat: StandardMaterial3D
var _max_hp: int = 100
var _dying := false

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $Label3D
@onready var _icon: Sprite3D = $Icon
@onready var _hp_bar: MeshInstance3D = $HPBar

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.25, 0.12, 0.18)
	_mat.roughness = 0.8
	_mesh.material_override = _mat
	_icon.texture = _make_icon_texture(_icon_base)
	_icon.visible = false
	# HP bar material
	_hp_bar_mat = StandardMaterial3D.new()
	_hp_bar_mat.albedo_color = Color(0.8, 0.15, 0.1)
	_hp_bar_mat.roughness = 1.0
	_hp_bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_bar.material_override = _hp_bar_mat

func set_label(t: String) -> void:
	_label.text = t

func set_selected(sel: bool) -> void:
	_selected = sel
	_mat.albedo_color = Color(0.6, 0.25, 0.25) if sel else Color(0.25, 0.12, 0.18)
	_update_icon_color()

func set_max_hp(hp: int) -> void:
	_max_hp = maxi(hp, 1)

func update_hp(current_hp: int) -> void:
	var frac := clampf(float(current_hp) / float(_max_hp), 0.0, 1.0)
	# Scale bar width based on HP fraction
	_hp_bar.scale.x = frac
	# Color: green at full, yellow at half, red at low
	if frac > 0.5:
		_hp_bar_mat.albedo_color = Color(0.2, 0.8, 0.15).lerp(Color(0.9, 0.8, 0.1), 1.0 - (frac - 0.5) * 2.0)
	else:
		_hp_bar_mat.albedo_color = Color(0.9, 0.8, 0.1).lerp(Color(0.85, 0.15, 0.1), 1.0 - frac * 2.0)

func play_death() -> void:
	if _dying:
		return
	_dying = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func flash_damage() -> void:
	_mat.albedo_color = Color(0.9, 0.3, 0.2)
	var tween := create_tween()
	var base_color := Color(0.6, 0.25, 0.25) if _selected else Color(0.25, 0.12, 0.18)
	tween.tween_property(_mat, "albedo_color", base_color, 0.15)

func set_zoom_lod(zoom_t: float) -> void:
	var t = _smoothstep(ICON_START, ICON_FULL, zoom_t)
	_mesh.visible = zoom_t < 0.8
	_hp_bar.visible = zoom_t < 0.8
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
