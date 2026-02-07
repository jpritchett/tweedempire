extends CanvasLayer
class_name InventoryHUD
## Simple HUD showing collected verb runes in the player's inventory.

var _panel: PanelContainer
var _vbox: VBoxContainer
var _title_label: Label
var _verb_container: HBoxContainer
var _verb_labels := {}  # verb_id -> Label

func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 10.0
	_panel.offset_top = -10.0
	_panel.offset_right = 300.0
	_panel.offset_bottom = -10.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", style)

	_vbox = VBoxContainer.new()
	_panel.add_child(_vbox)

	_title_label = Label.new()
	_title_label.text = "Inventory"
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.6))
	_vbox.add_child(_title_label)

	_verb_container = HBoxContainer.new()
	_verb_container.add_theme_constant_override("separation", 6)
	_vbox.add_child(_verb_container)

	add_child(_panel)

	# Connect to rune pickup signal
	Simulation.rune_picked_up.connect(_on_rune_picked_up)
	# Initial sync
	_rebuild()

func _on_rune_picked_up(_verb_id: String) -> void:
	_rebuild()

func _rebuild() -> void:
	# Clear existing
	for child in _verb_container.get_children():
		child.queue_free()
	_verb_labels.clear()

	# Count verbs in inventory
	var counts := {}
	for verb_id in Simulation.state.inventory:
		counts[verb_id] = counts.get(verb_id, 0) + 1

	if counts.is_empty():
		_title_label.text = "Inventory (empty)"
		return
	_title_label.text = "Inventory"

	for verb_id in counts.keys():
		var chip := _make_verb_chip(verb_id, counts[verb_id])
		_verb_container.add_child(chip)

func _make_verb_chip(verb_id: String, count: int) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var color := _verb_color(verb_id)
	style.bg_color = Color(color.r, color.g, color.b, 0.3)
	style.border_color = color
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = "%s x%d" % [verb_id, count] if count > 1 else verb_id
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	chip.add_child(lbl)
	_verb_labels[verb_id] = lbl
	return chip

func _verb_color(verb_id: String) -> Color:
	match verb_id:
		"IF": return Color(0.3, 0.7, 1.0)
		"FILTER": return Color(0.2, 0.9, 0.4)
		"NOT": return Color(0.9, 0.3, 0.3)
		"AND": return Color(0.8, 0.8, 0.2)
		"OR": return Color(0.9, 0.6, 0.2)
		"THROTTLE": return Color(0.6, 0.3, 0.9)
		"DELAY": return Color(0.4, 0.5, 0.9)
		"ROUTE": return Color(0.3, 0.8, 0.8)
		"QUEUE": return Color(0.7, 0.5, 0.3)
		"RETRY": return Color(0.9, 0.5, 0.6)
		"BROADCAST": return Color(1.0, 0.8, 0.3)
		"FAILSAFE": return Color(0.6, 0.8, 0.6)
		"QUARANTINE": return Color(0.7, 0.2, 0.5)
		_: return Color(0.8, 0.8, 0.8)
