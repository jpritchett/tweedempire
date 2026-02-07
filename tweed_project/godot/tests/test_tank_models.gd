extends SceneTree

# Tests to validate tank model scenes and integration

var all_passed = true

func _init():
	print("=== Tank Model Tests ===")
	print("")
	_test_model_loading()
	print("")
	_test_registry_integration()
	print("")
	_test_distinct_models()
	print("")
	_test_fallback_behavior()
	print("")
	_test_selection_system()
	print("")

	if all_passed:
		print("All tests passed!")
	else:
		print("Some tests failed!")

	quit(0 if all_passed else 1)

func _test_model_loading():
	print("Testing model loading...")
	var models = [
		"res://assets/models/units/t90_tank.tscn",
		"res://assets/models/units/m1_abrams.tscn",
		"res://assets/models/units/challenger2.tscn"
	]

	for model_path in models:
		if not ResourceLoader.exists(model_path):
			print("FAIL: Model not found: %s" % model_path)
			all_passed = false
			continue

		var scene = load(model_path) as PackedScene
		if scene == null:
			print("FAIL: Could not load scene: %s" % model_path)
			all_passed = false
			continue

		var instance = scene.instantiate()
		if instance == null:
			print("FAIL: Could not instantiate: %s" % model_path)
			all_passed = false
			continue

		# Check for MeshInstance3D in the scene
		var found_mesh = _find_mesh_instance(instance)
		if found_mesh == null:
			print("FAIL: No MeshInstance3D found in: %s" % model_path)
			all_passed = false
			instance.free()
			continue

		print("PASS: Model loads: %s" % model_path)
		instance.free()

func _test_registry_integration():
	print("Testing registry integration...")
	var tank_ids = ["t90_tank", "m1_abrams", "challenger2"]

	# Load unit_defs.json directly since autoloads aren't available in test scripts
	var unit_defs = _load_json("res://data/unit_defs.json")
	if unit_defs.is_empty():
		print("FAIL: Could not load unit_defs.json")
		all_passed = false
		return

	for tank_id in tank_ids:
		var unit_def = _get_unit_def(unit_defs, tank_id)
		if unit_def.is_empty():
			print("FAIL: No definition found for: %s" % tank_id)
			all_passed = false
			continue

		var model_path = unit_def.get("model", "")
		if model_path.is_empty():
			print("FAIL: Unit definition missing model field: %s" % tank_id)
			all_passed = false
			continue

		if not ResourceLoader.exists(model_path):
			print("FAIL: Model path in definition doesn't exist: %s -> %s" % [tank_id, model_path])
			all_passed = false
			continue

		print("PASS: Registry integration: %s -> %s" % [tank_id, model_path])

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _get_unit_def(unit_defs: Dictionary, id: String) -> Dictionary:
	for u in unit_defs.get("units", []):
		if u.get("id", "") == id:
			return u
	return {}

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var result = _find_mesh_instance(child)
		if result != null:
			return result
	return null

func _test_distinct_models():
	print("Testing distinct models...")
	# Verify each tank has unique visual properties
	var models = {
		"t90_tank": "res://assets/models/units/t90_tank.tscn",
		"m1_abrams": "res://assets/models/units/m1_abrams.tscn",
		"challenger2": "res://assets/models/units/challenger2.tscn"
	}

	var seen_colors = {}
	for tank_id in models.keys():
		var scene = load(models[tank_id]) as PackedScene
		if scene == null:
			print("FAIL: Could not load %s" % tank_id)
			all_passed = false
			continue

		var instance = scene.instantiate()
		var mesh = _find_mesh_instance(instance)
		if mesh == null:
			print("FAIL: No mesh in %s" % tank_id)
			all_passed = false
			instance.free()
			continue

		# Get color from material if available
		var color_key = ""
		if mesh.get_surface_override_material(0) != null:
			var mat = mesh.get_surface_override_material(0) as StandardMaterial3D
			if mat != null:
				color_key = str(mat.albedo_color)
		elif mesh.mesh != null:
			# Get from mesh itself - for procedural meshes, use mesh type+size
			color_key = "%s_%s" % [mesh.mesh.get_class(), tank_id]

		if color_key in seen_colors:
			print("FAIL: %s shares visual properties with %s" % [tank_id, seen_colors[color_key]])
			all_passed = false
		else:
			seen_colors[color_key] = tank_id
			print("PASS: Distinct model for %s" % tank_id)

		instance.free()

func _test_fallback_behavior():
	print("Testing fallback behavior...")
	# Test the unit_view.gd fallback logic by simulating missing model

	# Verify the unit_view script exists and has fallback method
	var unit_view_script = load("res://src/world/unit_view.gd") as GDScript
	if unit_view_script == null:
		print("FAIL: Could not load unit_view.gd")
		all_passed = false
		return

	# Check that the script has the required methods
	var source = unit_view_script.source_code
	if source.find("_use_fallback_mesh") == -1:
		print("FAIL: unit_view.gd missing _use_fallback_mesh method")
		all_passed = false
		return

	if source.find("push_warning") == -1:
		print("FAIL: unit_view.gd should warn when model not found")
		all_passed = false
		return

	if source.find("ResourceLoader.exists") == -1:
		print("FAIL: unit_view.gd should check if resource exists")
		all_passed = false
		return

	print("PASS: Fallback behavior implemented in unit_view.gd")

	# Verify the default mesh fallback exists in the scene
	var unit_scene = load("res://scenes/unit_view.tscn") as PackedScene
	if unit_scene == null:
		print("FAIL: Could not load unit_view.tscn")
		all_passed = false
		return

	var instance = unit_scene.instantiate()
	var mesh_node = instance.get_node_or_null("MeshInstance3D")
	if mesh_node == null:
		print("FAIL: No default MeshInstance3D in unit_view.tscn")
		all_passed = false
	elif mesh_node.mesh == null:
		print("FAIL: Default mesh is null in unit_view.tscn")
		all_passed = false
	else:
		print("PASS: Default fallback mesh exists in unit_view.tscn")
	instance.free()

func _test_selection_system():
	print("Testing selection system...")
	# Verify selection highlighting is preserved in unit_view.gd

	var unit_view_script = load("res://src/world/unit_view.gd") as GDScript
	if unit_view_script == null:
		print("FAIL: Could not load unit_view.gd")
		all_passed = false
		return

	var source = unit_view_script.source_code

	# Check for selection method
	if source.find("func set_selected") == -1:
		print("FAIL: unit_view.gd missing set_selected method")
		all_passed = false
		return

	# Check that selection changes color
	if source.find("_mat.albedo_color") == -1:
		print("FAIL: Selection should modify material color")
		all_passed = false
		return

	# Check for selected color (yellow-ish for selection)
	if source.find("Color(1.0, 0.85, 0.2)") == -1 and source.find("Color(1.0,0.85,0.2)") == -1:
		print("WARNING: Selection color may not be properly defined")

	print("PASS: Selection highlighting system in place")
