extends Node3D
## Visual representation of a dropped verb rune.
## Floating, bobbing diamond with verb-coloured glow.

const ICON_START := 0.6
const ICON_FULL := 0.85

## Verb ID -> display color
const VERB_COLORS := {
	"IF": Color(0.3, 0.7, 1.0),
	"FILTER": Color(0.2, 0.9, 0.4),
	"NOT": Color(0.9, 0.3, 0.3),
	"AND": Color(0.8, 0.8, 0.2),
	"OR": Color(0.9, 0.6, 0.2),
	"THROTTLE": Color(0.6, 0.3, 0.9),
	"DELAY": Color(0.4, 0.5, 0.9),
	"ROUTE": Color(0.3, 0.8, 0.8),
	"QUEUE": Color(0.7, 0.5, 0.3),
	"RETRY": Color(0.9, 0.5, 0.6),
	"BROADCAST": Color(1.0, 0.8, 0.3),
	"FAILSAFE": Color(0.6, 0.8, 0.6),
	"QUARANTINE": Color(0.7, 0.2, 0.5),
}

var _mat: StandardMaterial3D
var _selected := false
var _icon_base := Color(1.0, 0.85, 0.2)
var _icon_selected := Color(1.0, 0.95, 0.6)
var _bob_offset := 0.0
var _base_y := 0.0
var _verb_id := ""

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _label: Label3D = $Label3D
@onready var _icon: Sprite3D = $Icon

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1.0, 0.85, 0.2)
	_mat.roughness = 0.3
	_mat.metallic = 0.4
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.85, 0.2)
	_mat.emission_energy_multiplier = 0.5
	_mesh.material_override = _mat
	_icon.texture = _make_icon_texture(_icon_base)
	_icon.visible = false
	_bob_offset = randf() * TAU  # Randomize bob phase per rune

func _process(delta: float) -> void:
	# Bobbing animation
	_bob_offset += delta * 2.5
	_mesh.position.y = sin(_bob_offset) * 0.2 + 0.5
	# Slow rotation
	_mesh.rotation.y += delta * 1.5

func set_verb(verb_id: String) -> void:
	_verb_id = verb_id
	var color: Color = VERB_COLORS.get(verb_id, Color(1.0, 0.85, 0.2))
	_mat.albedo_color = color
	_mat.emission = color
	_icon_base = color
	_icon.texture = _make_icon_texture(color)
	_update_icon_color()

func set_label(t: String) -> void:
	_label.text = t

func set_selected(sel: bool) -> void:
	_selected = sel
	_update_icon_color()

func play_pickup() -> void:
	# Quick scale-up then vanish
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.5, 1.5, 1.5), 0.1)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.15)
	tween.tween_callback(queue_free)

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
	# Diamond shape for runes
	var half := size * 0.35
	for y in range(size):
		for x in range(size):
			var dx = abs(float(x) - center.x)
			var dy = abs(float(y) - center.y)
			if dx / half + dy / half <= 1.0:
				var edge_dist = 1.0 - (dx / half + dy / half)
				if edge_dist > 0.3:
					img.set_pixel(x, y, base_color)
				else:
					img.set_pixel(x, y, base_color.darkened(0.3))
	return ImageTexture.create_from_image(img)

func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
