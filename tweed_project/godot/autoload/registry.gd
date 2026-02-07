extends Node
## Loads data-driven definitions (blocks, verbs, units).
## Keep this autoload very lightweight; it should not simulate anything.

var block_defs: Dictionary
var unit_defs: Dictionary

func _ready() -> void:
	block_defs = _load_json("res://data/block_defs.json")
	unit_defs = _load_json("res://data/unit_defs.json")

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Failed to open %s" % path)
		return {}
	var txt := f.get_as_text()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON in %s" % path)
		return {}
	return parsed

func get_verb(id: String) -> Dictionary:
	for v in block_defs.get("verbs", []):
		if v.get("id","") == id:
			return v
	return {}

func get_unit_def(id: String) -> Dictionary:
	for u in unit_defs.get("units", []):
		if u.get("id","") == id:
			return u
	return {}

func get_structure_def(id: String) -> Dictionary:
	for s in unit_defs.get("structures", []):
		if s.get("id","") == id:
			return s
	return {}
